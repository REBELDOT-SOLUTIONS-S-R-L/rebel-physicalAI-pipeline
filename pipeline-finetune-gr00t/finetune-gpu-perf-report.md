# GR00T Fine-tuning — GPU Utilization Investigation & Performance Report

## Context

- **Model:** GR00T N1.7-3B fine-tune (`launch_finetune.py`)
- **Hardware:** Brev VM — 1× NVIDIA A100-SXM4-80GB, 24 vCPU, ~116 GB RAM, `/ephemeral` scratch disk
- **Dataset:** `so101_cube_bucket_green` (single-arm SO-101, 2 cameras top+wrist, 480×640, 25 fps, ~68k frames)
- **Symptom:** GPU utilization low and unstable during training — far below the >80% sustained seen on a previous GCP run with the same code.

The investigation was done by SSH-ing into the running VM, sampling `nvidia-smi`, `/proc/loadavg`, `iostat`, `py-spy`, and the training step log, and running controlled A/B restarts.

---

## Measurement methodology & caveats

- **Primary metric: throughput in samples/s = `batch_size × it/s`** read from the step log at **steady state (≥ ~step 100)**. This is far more reliable than instantaneous GPU utilization.
- GPU "utilization" was sampled at 1 Hz; because a training step is sub-second to ~1.6 s, single-second samples land mid-step and look noisy. Used only as a coarse indicator.
- **Early steps (first ~100) are warmup-slow** — dataloader workers spawn at step 0, prefetch buffers fill, torch compiles/autotunes, dataset shards load lazily. Several early readings were initially misleading and had to be re-measured at steady state.

---

## Tests & results

### Test 0 — Baseline (AV1 video, original dataset)
- **GPU util:** ~10%, effectively constant.
- **CPU load:** ~56 on 24 cores (≈2.3× oversubscribed).
- **Finding:** Dataset videos were AV1 (`codec=av1`). The A100 has **no AV1 hardware decoder (NVDEC)**, so every frame decoded on CPU. CPU was the wall; the GPU sat idle waiting for batches.

### Test 1 — Transcode AV1 → H.264 (default GOP ≈ 250)
- **GPU util:** sawtooth, **0 ↔ 92%**; fewer dips than baseline.
- **Step rate:** ~1.2 it/s in good phases, periodically collapsing to **1.0–2.6 s/it**.
- **Finding:** Codec fixed (H.264 decodes much cheaper, and is NVDEC-eligible), but libx264's default GOP (~250) made random single-frame seeks decode up to ~250 frames each → latency-bound, bursty.

### Test 2 — Transcode H.264 with GOP=2
- **Verification:** `ffprobe` confirmed frame pattern `I P I P …` (keyframe every 2 frames), matching LeRobot's native AV1 encoding.
- **GPU util:** still sawtooth **0 ↔ 92%**.
- **CPU load:** **53** on 24 cores.
- **Finding:** Cheap seeks confirmed, but the sawtooth persisted and CPU was still saturated → seeking was **not** the dominant problem.

### Test 3 — Root cause: torchcodec ffmpeg thread oversubscription
- **py-spy** of a dataloader worker showed decoding via `torchcodec … get_frames_at`.
- Source inspection of `gr00t/utils/video_utils.py` revealed the decoder is constructed as:
  ```python
  torchcodec.decoders.VideoDecoder(video_path, device="cpu", dimension_order="NHWC", num_ffmpeg_threads=0)
  ```
  `num_ffmpeg_threads=0` means **"use all cores" per decoder**. With `--dataloader_num_workers 16`, each worker's per-sample decoder spawned ~24 ffmpeg threads → **~16 × 24 ≈ 380 threads contending for 24 cores** → massive context-switch thrash (load 53), starving the GPU.
- **Fix:** cap to `num_ffmpeg_threads=1` (parallelism comes from the 16 workers, not from threads-per-decode, which barely help a single-frame fetch anyway).

### Test 4 — After thread-cap patch (`num_ffmpeg_threads=1`), bs=64, workers=16
- **GPU util:** **~83% avg (58–100%)**.
- **CPU load:** **18 → 9** (dropped well under 24 cores; ample headroom).
- **Step rate:** steady **1.19 it/s**, no collapses.
- **Throughput:** **≈76 samples/s.**
- **VRAM:** 43.7 / 81.9 GB (≈53%).
- **Finding:** This was the dominant fix — GPU went from ~10–40% to ~80%+. Verified live and confirmed reproducible after a clean restart.

### Test 5 — Batch size 128 (workers=16, threads=1)
- **VRAM:** 59.3 / 81.9 GB (≈72%) — fits, no OOM, ~22 GB headroom.
- **Step rate:** 0.61 it/s → **≈78 samples/s.**
- **CPU load:** ~18 (≈2× the bs64 decode demand).
- **Finding:** Throughput **unchanged** (78 vs 76 samples/s). Larger batch consumed more VRAM and more CPU but produced **no speedup**.

### Test 6 — Workers 24 (bs=64, threads=1)
- **Step rate (steady, step ~155):** **1.19–1.20 it/s → ≈76 samples/s.**
- **CPU load:** ~5 (even more idle).
- **Finding:** Identical throughput to 16 workers. Extra workers gave **no gain**.

---

## Comparison

| Test | Config | GPU util | CPU load (/24) | Step rate | Throughput | VRAM | Verdict |
|------|--------|----------|----------------|-----------|------------|------|---------|
| 0 | AV1, w16 | ~10% flat | ~56 | — | — | — | CPU-bound on AV1 decode |
| 1 | H.264 GOP~250, w16 | 0–92% sawtooth | ~16–53 | 1.2 it/s ↔ 2.6 s/it | bursty | — | Big-GOP seek latency |
| 2 | H.264 GOP=2, w16 | 0–92% sawtooth | 53 | bursty | — | — | Seeks cheap, still thrash |
| 3→4 | **GOP=2 + `num_ffmpeg_threads=1`, bs64, w16** | **~83% (58–100)** | **9–18** | **1.19 it/s** | **~76 s/s** | 53% | **Dominant fix** |
| 5 | bs128, w16 | dips 42–100 | ~18 | 0.61 it/s | ~78 s/s | 72% | No speedup, +VRAM |
| 6 | bs64, w24 | dips 52–100 | ~5 | 1.19 it/s | ~76 s/s | 53% | No speedup |

---

## Root cause

The GPU starvation had **two stacked causes**, one dominant:

1. **Dominant — ffmpeg thread oversubscription.** `gr00t/utils/video_utils.py` hardcodes `num_ffmpeg_threads=0` (all cores) when building the torchcodec `VideoDecoder`. Multiplied across 16 dataloader workers, this created ~380 threads on 24 cores. Fix: cap to `1`. Result: GPU ~10–40% → ~80%+, CPU load 53 → 9.
2. **Secondary — video decode cost.** AV1 has no NVDEC on the A100 (CPU-only decode); transcoding to H.264 with a small GOP (=2, matching LeRobot's native encoding) made decode cheap and seeks instant. Necessary, but not the limiting factor on its own.

The previous GCP run masked cause #1 simply by having more vCPUs, so the thread storm didn't fully saturate the CPU there.

---

## Conclusions

- **Single highest-impact change:** `num_ffmpeg_threads=0 → 1` in `gr00t/utils/video_utils.py`. Applied as a post-install patch in `2-gr00t-install.ipynb` so every fresh VM gets it.
- **Post-fix throughput ceiling ≈ 76–78 samples/s is GPU-bound, not data-bound.** CPU is idle (load 5–9). Batch size (64 vs 128) and worker count (16 vs 24) do **not** move throughput — the remaining 40–60% util dips are the 3B model's own per-step overhead (kernel-launch gaps, attention, optimizer/sync), which these knobs cannot fix.
- **Recommended fine-tuning config for this VM:** `--global_batch_size 64`, `--dataloader_num_workers 16`, `num_ffmpeg_threads=1`. This is at the practical ceiling for the hardware.
- **Batch size is not an efficiency lever here.** Increasing it only changes gradient statistics/convergence (and would require LR re-tuning); it does not speed up training. Leave at 64 unless changing the training recipe deliberately.

---

## Other notes

- **NVDEC path (not pursued):** torchcodec on this box is CUDA-capable and ffmpeg has `h264_cuvid`, so `device="cuda"` could offload decode to the GPU's hardware decoder. It was unnecessary (the thread cap freed plenty of CPU) and is risky inside forked DataLoader workers — left as a future option if a smaller-CPU box ever makes decode the bottleneck again.
- **Checkpoint cadence:** `save_steps=15000` ≈ one checkpoint per ~3.5 h at 1.2 it/s. For a "train and pick the best checkpoint by live evaluation" workflow, consider a smaller `save_steps` (e.g. 2000–5000) for a finer selection grid.
- **Diagnosing data starvation (playbook):** compare `cat /proc/loadavg` to `nproc` (load ≫ cores ⇒ CPU/thread thrash); `iostat -x` on the dataset disk (high `%util`/`await` ⇒ disk-bound); `py-spy dump` a worker to see the decode path; and always read **steady-state** step rate, not early steps or 1 Hz GPU samples.

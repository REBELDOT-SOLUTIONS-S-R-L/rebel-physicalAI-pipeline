# Gr00t Pipeline — Metrics Reference Report

## Overview

The pipeline collects metrics from two Python scripts running on the Brev instance: `convert_videos` and `data_and_meta_convert`. After each run, metrics are written as JSON files to `~/conversion_metrics/` on Brev, then copied to Databricks and loaded into 3 Delta Tables.

All 3 tables share a common `run_id` field which links them together, enabling cross-table joins in dashboard queries.

---

## How Tables Relate

```
pipeline_runs (1 row per run)
    └── run_id ──► data_conversion_metrics (1 row per episode)
                       └── run_id + episode_id ──► video_conversion_metrics (1 row per episode per camera)
```

**Unique keys:**
- `pipeline_runs`: `run_id`
- `data_conversion_metrics`: `(run_id, episode_id)`
- `video_conversion_metrics`: `(run_id, episode_id, camera)`

---

## Table 1: `video_conversion_metrics`

One row per episode per camera (3 rows per episode: `top` + `left_wrist` + `right_wrist`)

**Unique key:** `(run_id, episode_id, camera)`

| Field | Type | Description |
|---|---|---|
| run_id | string | Unique identifier for the full pipeline run. Shared across all three tables. Format: `YYYYMMDDTHHMMSS` |
| episode_id | int | Zero-based index of the episode within the HDF5 dataset. Episode 0 = demo_0, episode 1 = demo_1, etc. |
| camera | string | Which camera stream was encoded. Values: `'top'` (overhead camera), `'left_wrist'`, or `'right_wrist'` (end-effector cameras). |
| num_frames | int | Total number of frames in the episode for this camera, read directly from the HDF5 dataset shape. |
| resolution | string | Video resolution as `'WxH'` string, e.g. `'640x480'`. Read from HDF5 dataset dimensions. **NULL if encoding failed.** |
| encode_time_sec | double | Wall-clock seconds ffmpeg took to encode the full episode. Measured from `Popen()` to `proc.wait()`. Includes frame piping time. |
| encode_fps | double | Encoding throughput in frames per second. Higher = faster. Derived metric: `num_frames / encode_time_sec`. |
| video_size_mb | double | Output MP4 file size in megabytes after encoding. **Sentinel value: `0` if the file does not exist (encoding failed) — not NULL.** |
| status | string | Encoding outcome. `'success'` = ffmpeg exited 0 and no exception. `'failed'` = ffmpeg returned non-zero exit code or Python exception. |
| error_msg | string | Human-readable error message. **NULL when `status = 'success'`.** Contains ffmpeg exit code or Python exception string when `status = 'failed'`. |
| ts | string | Timestamp of when this specific episode + camera metric was recorded. Format: `YYYY-MM-DDTHH:MM:SS` |
| hdf5_source | string | Name of the source HDF5 file that every episode was converted from. |

---

## Table 2: `data_conversion_metrics`

One row per episode. Covers parquet writing and robot action quality statistics.

**Unique key:** `(run_id, episode_id)`

| Field | Type | Description |
|---|---|---|
| run_id | string | Unique identifier for the full pipeline run. Shared across all three tables. Format: `YYYYMMDDTHHMMSS` |
| episode_id | int | Zero-based index of the episode within the HDF5 dataset. Episode 0 = demo_0, episode 1 = demo_1, etc. |
| num_frames | int | Total number of frames in the episode, read directly from the HDF5 dataset shape. |
| duration_sec | double | Episode duration in seconds, computed as `num_frames / 30`. Represents actual robot demo duration in real time. **Assumption: recording framerate is fixed at 30 fps. If this changes, values will be incorrect.** |
| parquet_size_mb | double | Size of the written `.parquet` file in megabytes. Contains `observation.state`, `action`, `frame_index`, `timestamp`, `index` columns. |
| parquet_write_time_sec | double | Wall-clock seconds taken to write the `.parquet` file. |
| action_mean | array\<double\> | Array of 6 doubles — mean action value per joint across all T frames. Index maps to: `[action_0, action_1, action_2, action_3, action_4, action_5]`. Values in radians. **Expected range: approximately `[-π, π]` per joint.** |
| action_std | array\<double\> | Array of 6 doubles — standard deviation of action per joint across T frames. Low std (near 0) means the joint barely moved. High std means active movement. **Values near 0 may indicate a stuck or unused joint.** |
| obs_mean | array\<double\> | Array of 6 doubles — mean observation state per joint across T frames. Corresponds to obs/actions in HDF5 (joint positions as observed, not commanded). **Expected range: approximately `[-π, π]` per joint.** |
| obs_std | array\<double\> | Array of 6 doubles — standard deviation of observed joint state per joint. Should closely mirror `action_std` if the robot is following commands well. **Large divergence from `action_std` may indicate tracking error.** |
| ts | string | Timestamp of when this specific episode metric was recorded. Format: `YYYY-MM-DDTHH:MM:SS` |
| hdf5_source | string | Name of the source HDF5 file that every episode was converted from. |

---

## Table 3: `pipeline_runs`

One row per full pipeline run. This is the top-level index table.

**Unique key:** `run_id`

| Field | Type | Description |
|---|---|---|
| run_id | string | Unique identifier for the full pipeline run. Shared across all three tables. Format: `YYYYMMDDTHHMMSS` |
| hdf5_size_mb | double | Size of the input `dataset.hdf5` file in MB at conversion time. Tracks dataset growth over successive data collection sessions. |
| total_episodes | int | Number of episodes (demos) found in the HDF5. Each episode = one robot teleoperation demonstration. |
| total_frames | int | Sum of all frames across all episodes in this run. Represents total timesteps available for Gr00t fine-tuning. |
| total_duration_sec | double | Total wall-clock time of the full pipeline in seconds — from job start to metrics loaded. Injected by the Databricks metrics loader cell, NOT only computed on Brev. Includes video encoding + data conversion + SSH overhead. |
| avg_frames_per_episode | double | Mean number of frames per episode for this run. Derived metric: `total_frames / total_episodes`. Consistent value across runs = uniform demo length. Large variation = inconsistent teleoperation sessions. |
| ts | string | Timestamp from the end of the `data_and_meta_convert` script on Brev. |

---

## Key Derived Metrics for Dashboard Queries

| metric_name | description |
|---|---|
| encode_performance | Measures the overall encoding efficiency and speed for video processing pipelines, used to monitor and benchmark encoder throughput across runs. |
| total_run_time_pipeline_minutes | Tracks the total elapsed time in minutes for a complete pipeline run from start to finish, used to identify bottlenecks and measure end-to-end processing duration. |
| conversion_speed_trend | Shows the trend of video conversion speed over time or across runs, used to detect performance regressions or improvements in the encoding workflow. |
| encode_fps_trend_per_camera_over_runs | Tracks frames-per-second (FPS) encoding rate per individual camera across multiple runs, used to compare per-camera encoding performance and identify outliers. |
| failed_episodes_counter | Counts the number of episodes that failed during processing, used to monitor pipeline reliability and trigger alerts when failure rates exceed thresholds. |
| total_video_output_size | Aggregates the total file size of all encoded video outputs, used to track storage consumption and assess the impact of encoding settings on output size. |
| encode_time_difference | Calculates the difference in encoding time between runs or between expected and actual duration, used to detect anomalies and measure the impact of configuration changes. |
| action_mean_per_joint | Computes the mean action value per robot joint across episodes, used to assess motion quality and consistency of joint movements in dataset recordings. |
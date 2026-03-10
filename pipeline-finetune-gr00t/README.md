# GR00T Fine-Tuning Pipeline

End-to-end pipeline for fine-tuning NVIDIA GR00T N1.6-3B on custom robot datasets. Orchestrated as a sequence of Databricks notebooks that provision a Brev GPU instance, prepare the environment, install GR00T, and run training — all via SSH from Databricks.

## How it works

Databricks acts as the control plane. It doesn't run any training itself — instead, each notebook SSHs into a remote Brev GPU instance and executes commands there. Secrets (API keys, SSH keys, tokens) are pulled from Databricks secret scopes and passed as environment variables between notebooks.

The pipeline runs sequentially: spin up the instance, install dependencies, install GR00T, download the model, transfer the dataset, and kick off fine-tuning.

## Pipeline

| Step | Notebook | What it does |
|------|----------|--------------|
| — | `secrets-template.ipynb` | Loads all secrets from Databricks and sets environment variables |
| 0 | `0-brev-ssh-env-init.ipynb` | Starts the Brev instance, sets up SSH connectivity, retrieves the instance IP |
| 1 | `1-brev-setup-env.ipynb` | SSHs into Brev and installs system dependencies, configures PATH |
| 2 | `2-gr00t-install.ipynb` | Clones Isaac-GR00T repo, downloads the GR00T N1.6-3B model, creates output directories |
| 3 | `3-gr00t-finetune.ipynb` | Transfers dataset and modality configs from Databricks Volumes to Brev, runs fine-tuning in a tmux session |

## Notebook Details

### `secrets-template.ipynb` — Environment Setup 

Template notebook that loads credentials from three Databricks secret scopes and exports them as environment variables. This must run before everything else.

| Scope | Keys |
|---|---|
| `brev` | `token`, `instance`, `brev_ip`, `ssh_public_key`, `ssh_private_key`, `dataset_name`, `max_steps`, `save_steps`, `task_name` |
| `wandb` | `token` |
| `databricks` | `pat` |

Also sets hardcoded paths for datasets (`/Volumes/workspace/default/datasets`) and modality files (`/Volumes/workspace/default/modality_files`).

### `0-brev-ssh-env-init.ipynb` — Instance Init & SSH 

Starts the Brev GPU instance using the Brev API, waits for it to become reachable, and retrieves its IP address. Writes the IP to `/tmp/brev_ip.txt` and loads it into `BREV_INSTANCE_IP` for subsequent notebooks. Cleans up the temp file at the end.

### `1-brev-setup-env.ipynb` — System Dependencies

SSHs into the Brev instance and prepares it for ML work:
- Copies the SSH private key to `/tmp/ssh_private_key_2` for this notebook's connections
- Runs `apt-get update` and installs system-level dependencies
- Ensures `~/.local/bin` is in PATH (persisted in `.bashrc`)

### `2-gr00t-install.ipynb` — GR00T Installation

SSHs into Brev and sets up the GR00T framework:
- Downloads the `nvidia/GR00T-N1.6-3B` model via `uv run hf download`
- Creates the `finetuned_models` and `databricks_datasets` directories under `Isaac-GR00T`

### `3-gr00t-finetune.ipynb` — Dataset Transfer & Training

The main event. SSHs into Brev and:
- Downloads `modality.json` and the modality Python config (`so100_top_wrist_config.py`) from Databricks Volumes to the Brev instance using the Databricks Files API
- Launches fine-tuning inside a `tmux` session named `finetune` (so it survives SSH disconnects)
- Writes `TRAINING_DONE` or `TRAINING_FAILED` marker files to `$HOME` on completion 


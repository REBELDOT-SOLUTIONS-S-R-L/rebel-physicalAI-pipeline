# Upload LeRobot Dataset 

Basically takes a dataset from databricks and loads it into the brev instance. Nothing more.

## How it works

Databricks acts as the control plane. It doesn't run any training itself — instead, each notebook SSHs into a remote Brev GPU instance and executes commands there. Secrets (API keys, SSH keys, tokens) are pulled from Databricks secret scopes and passed as environment variables between notebooks.

The pipeline gets the needed secrets from databricks, ssh into the instance and copies the dataset.

## Pipeline

| Step | Notebook | What it does |
|------|----------|--------------|
| — | `secrets-template.ipynb` | Loads all secrets from Databricks and sets environment variables |
| 0 | `0-brev-ssh-env-init.ipynb` | Starts the Brev instance, sets up SSH connectivity, retrieves the instance IP |
| 1 | `1-upload-lerobot-dataset.ipynb` | SSHs into BRev and copies the dataset|

### `secrets-template.ipynb` — Environment Setup 

> This notebook is stored in __pipeline-finetune-gr00t__ but it's used here too for secret retrieval

Template notebook that loads credentials from three Databricks secret scopes and exports them as environment variables. This must run before everything else.

| Scope | Keys |
|---|---|
| `brev` | `token`, `instance`, `brev_ip`, `ssh_public_key`, `ssh_private_key`, `dataset_name`, `max_steps`, `save_steps`, `task_name` |
| `wandb` | `token` |
| `databricks` | `pat` |

### `0-brev-ssh-env-init.ipynb` — Instance Init & SSH 

> This notebook is stored in __pipeline-finetune-gr00t__ but it's used here too for creating the ssh connection

Starts the Brev GPU instance using the Brev API, waits for it to become reachable, and retrieves its IP address. Writes the IP to `/tmp/brev_ip.txt` and loads it into `BREV_INSTANCE_IP` for subsequent notebooks. Cleans up the temp file at the end.

### `1-upload-lerobot-dataset` - Upload LeRobot dataset to instance

- Copies the SSH private key locally for use in SSH commands
- Creates the directory structure `(lerobot_datasets/merged_dataset)` on the remote instance
- Uses `scp` to transfer your dataset from Databricks Volumes `(/Volumes/workspace/default/finetune_lerobot_datasets/$DATASET_NAME)` to the Brev instance
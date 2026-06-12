#!/usr/bin/env bash
#
# Poll the GR00T fine-tune on this VM, then upload the finetuned model to
# Hugging Face once training finishes. Designed to run DETACHED (tmux) so the
# Databricks pipeline can finish while training keeps running for hours.
#
# Usage:  poll_and_upload_hf.sh <HF_USER> <DATASET_NAME> [INSTANCE_NAME]
#
#   - Waits for the fine-tune cell's flag files:
#       $HOME/TRAINING_DONE    -> success, proceed to upload
#       $HOME/TRAINING_FAILED  -> failure, skip upload (and skip delete)
#   - Uploads the ENTIRE model dir: /ephemeral/finetuned-models/<DATASET_NAME>
#   - Target repo: <HF_USER>/<DATASET_NAME>, created as a PRIVATE *model* repo
#     if it does not already exist.
#   - HF auth reuses the token written by the pipeline's "Hugging Face login"
#     cell (~/.cache/huggingface/token); no token is passed in here.
#   - If INSTANCE_NAME is given AND the upload succeeds, the Brev instance is
#     deleted with `brev delete` (terminates it / stops billing). Requires the
#     brev CLI + ~/.brev/credentials.json to be present on the VM (set up by the
#     pipeline's "Install brev CLI + restore creds" cell). On TRAINING_FAILED or
#     a failed upload, the instance is LEFT RUNNING for debugging.
#
# This script lives in Databricks at:
#   /Volumes/workspace/default/hdf52lerobot_script_files_metrics/poll_and_upload_hf.sh
# and is copied to the VM by the pipeline before being launched.

set -uo pipefail

HF_USER="${1:?usage: poll_and_upload_hf.sh <HF_USER> <DATASET_NAME> [INSTANCE_NAME]}"
DATASET_NAME="${2:?usage: poll_and_upload_hf.sh <HF_USER> <DATASET_NAME> [INSTANCE_NAME]}"
INSTANCE_NAME="${3:-}"

REPO_ID="${HF_USER}/${DATASET_NAME}"
MODEL_DIR="/ephemeral/finetuned-models/${DATASET_NAME}"
DONE_FLAG="${HOME}/TRAINING_DONE"
FAILED_FLAG="${HOME}/TRAINING_FAILED"
VENV_PY="${HOME}/Isaac-GR00T/.venv/bin/python"

export PATH="${HOME}/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

echo "[poll_and_upload_hf] repo=${REPO_ID}  model_dir=${MODEL_DIR}  instance=${INSTANCE_NAME:-<none>}"
echo "[poll_and_upload_hf] waiting for training to finish (TRAINING_DONE / TRAINING_FAILED) ..."
while true; do
  if [ -f "${FAILED_FLAG}" ]; then
    echo "[poll_and_upload_hf] TRAINING_FAILED present -> skipping upload and delete."
    exit 1
  fi
  if [ -f "${DONE_FLAG}" ]; then
    echo "[poll_and_upload_hf] TRAINING_DONE present -> proceeding to upload."
    break
  fi
  sleep 60
done

if [ ! -d "${MODEL_DIR}" ]; then
  echo "[poll_and_upload_hf] model dir not found: ${MODEL_DIR} -> abort (instance left running)."
  exit 1
fi

if REPO_ID="${REPO_ID}" MODEL_DIR="${MODEL_DIR}" "${VENV_PY}" - <<'PY'
import os
from huggingface_hub import create_repo, upload_large_folder

repo = os.environ["REPO_ID"]
folder = os.environ["MODEL_DIR"]

# Private model repo; no-op if it already exists.
create_repo(repo, repo_type="model", private=True, exist_ok=True)

# Resumable upload of the whole directory (all checkpoints).
upload_large_folder(repo_id=repo, folder_path=folder, repo_type="model")

print(f"[poll_and_upload_hf] uploaded {folder} -> https://huggingface.co/{repo}")
PY
then
  echo "[poll_and_upload_hf] upload OK."
  if [ -n "${INSTANCE_NAME}" ]; then
    if command -v brev >/dev/null; then
      echo "[poll_and_upload_hf] upload succeeded -> deleting Brev instance '${INSTANCE_NAME}'."
      # brev refreshes its access token from ~/.brev/credentials.json (non-rotating).
      brev delete "${INSTANCE_NAME}" || echo "[poll_and_upload_hf] WARNING: 'brev delete' failed; delete the instance manually."
    else
      echo "[poll_and_upload_hf] brev CLI not found on PATH -> skipping instance delete."
    fi
  else
    echo "[poll_and_upload_hf] no INSTANCE_NAME given -> not deleting instance."
  fi
else
  echo "[poll_and_upload_hf] upload FAILED -> NOT deleting instance (left running for debugging)."
  exit 1
fi

echo "[poll_and_upload_hf] done."

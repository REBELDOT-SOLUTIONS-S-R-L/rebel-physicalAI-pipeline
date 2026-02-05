# AI Model Training Workflows

Automated pipelines for training, evaluating, and deploying machine learning models. This repository contains reusable GitHub Actions workflows  that handle the repetitive parts of the ML lifecycle so you can focus on the actual modeling work.

## What's inside
At the moment of the creation of this README.md (5/2/2026) this repo contains 3 workflows:

+ Brev Environment Setup 
+ GR00T Setup
+ GR00T Fine-tune

### [___Brev Environment Setup___](https://github.com/REBELDOT-SOLUTIONS-S-R-L/ROBOTICS-AI-training-pipeline/blob/main/.github/workflows/brev-setup-env.yml)

This workflow provisions a GPU-enabled remote development environment on Brev with CUDA 12.4 and Python tooling. Installs system dependencies, configures NVIDIA CUDA toolkit, and sets up uv for fast Python package management. Designed to prepare the instance for ML/AI workloads like GR00T and flash-attention.
#### Steps:

+ Manual steps: (Create an instence using the NvidiaBrev UI and start it. Right now Brev CLI does not support creating instances that are not on GCP)
+ Install Brev CLI: Installs the Brev CLI
+ Login to Brev: Login using a token stored in BREV_TOKEN
+ Enter Brev with shell to create ssh config: Use shell to enter the instance (after some tests, the file <code>~/.brev/ssh_config</code> file is not created unless we use the <code>brev shell instance-name</code>, file which is needed so we can execute commands on the instance using ssh conection)
+ Step 0: Verifies the remote instance is accessible and has a working NVIDIA GPU driver by printing the OS version and running <code>nvidia-smi</code>
+ Step 1: Installs essential build tools and development libraries needed for compiling Python packages and CUDA-dependent software.
+ Step 2: Removes Ubuntu's outdated bundled CUDA toolkit to avoid version conflicts before installing the official NVIDIA CUDA 12.4.
+ Step 3: Adds NVIDIA's official CUDA repository (auto-detecting Ubuntu version) and installs CUDA Toolkit 12.4.
+ Step 4: Configures environment variables to use CUDA 12.4 (persists to .bashrc) and verifies nvcc points to the correct version.
+ Step 4.5: Adds ~/.local/bin to PATH in .bashrc so user-installed tools like uv are accessible without full paths.
+ Step 5: Installs uv (a fast Python package manager) and verifies the installation.

### Needed Vars and Secrets:
+ secrets.BREV_TOKEN
+ vars.BREV_INSTANCE_NAME

### [___GR00T Setup___](https://github.com/REBELDOT-SOLUTIONS-S-R-L/ROBOTICS-AI-training-pipeline/blob/main/.github/workflows/gr00t-install.yml)

Installs NVIDIA's Isaac GR00T robotics foundation model on the Brev instance. Runs automatically after the environment setup (previous workflow) completes (or manually). Clones the repo, creates a Python 3.10 environment with uv, installs PyTorch with CUDA 12.4 support, builds flash-attention for optimized inference, configures Hugging Face authentication, downloads the GR00T-N1.6-3B model weights, and pulls custom modality files.

#### Steps: 

+ Step 0: Installs the Brev CLI on the GitHub runner to enable SSH access to the remote instance.
+ Step 1: Authenticates with Brev using a stored token and generates the SSH config needed to connect to the instance.
+ Step 2: Clones the NVIDIA Isaac-GR00T repository (with submodules), or pulls latest changes if it already exists.
+ Step 3: Creates a Python 3.10 virtual environment with uv and installs the GR00T package in editable mode.
+ Step 4: Installs PyTorch with CUDA 12.4 support and verifies GPU acceleration is working.
+ Step 5: Builds and installs flash-attention (optimized for Ampere GPUs) using all CPU cores, then verifies the import.
+ Step 5: Installs Hugging Face tools with fast transfer support, configures authentication token, and verifies login.
+ Step 6: Downloads the GR00T-N1.6-3B model weights from Hugging Face.
+ Step 7: Clones custom modality configuration files from Hugging Face, or pulls latest if already present.

#### Needed Vars and Secrets:

+ secrets.BREV_TOKEN
+ vars.BREV_INSTANCE_NAME
+ secrets.HF_TOKEN

### [___GR00T Fine-tune___](https://github.com/REBELDOT-SOLUTIONS-S-R-L/ROBOTICS-AI-training-pipeline/blob/main/.github/workflows/gr00t-finetune.yml)
Runs after _GR00T Setup_ completes (or manually). Downloads a custom dataset from Hugging Face and launches fine-tuning on the GR00T-N1.6-3B model with configurable hyperparameters, modality config, and checkpoint settings.

#### Steps: 
+ Step 0: Installs Brev CLI, authenticates, and generates SSH config for connecting to the remote instance.
+ Step 1: Downloads the training dataset from Hugging Face into the local `hf_datasets` directory.
+ Step 2: Launches GR00T fine-tuning on a single GPU with the downloaded dataset, custom modality config, and configurable training hyperparameters.

#### Needed Vars and Secrets:

+ secrets.BREV_TOKEN
+ vars.BREV_INSTANCE_NAME
+ vars.HF_REPO_NAME
+ vars.MODALITY_FILE
+ vars.SAVE_STEPS
+ vars.MAX_STEPS
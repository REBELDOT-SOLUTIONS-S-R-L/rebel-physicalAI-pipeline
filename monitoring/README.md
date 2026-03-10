# Brev Instance Monitor

Automated watchdog that monitors the Brev GPU instance and shuts it down when no Databricks jobs are running. Scheduled as a Databricks notebook job to prevent idle GPU costs.

## What it does

1. Checks if the Brev instance is reachable via SSH
2. If it's off — does nothing
3. If it's on — queries the Databricks API for active job runs
4. If jobs are running — logs them and leaves the instance alone
5. If no jobs are running — shuts down the instance via SSH (`sudo shutdown -h now`)
6. Sends a status report via email and Slack after every run

## Architecture

## Architecture

| Component | Protocol | Purpose |
|---|---|---|
| Brev Instance | SSH | Health check + shutdown |
| Databricks API | REST | Check active job runs |
| Gmail | SMTP | Email notifications |
| Slack | Webhook | Slack notifications |

The Databricks scheduler triggers this notebook on a recurring basis. The notebook connects to each component above, decides whether to shut down the Brev instance, and sends a status report.

## Used Secrets 
<em style="color: red;">No need to change any of these secrets</em>

Usefull databricks commands:
- `databricks secrets list-scopes`
- `databricks secrets list-secrets <scope-name>`
- `databricks secrets get-secret <scope-name> <key-name> | jq -r .value | base64 --decode`
- `databricks secrets put-secret <scope-name> <key-name> --string-value "<actual-secret>"`

| Scope | Key | Description |
|---|---|---|
| `brev` | `ssh_private_key` | SSH private key to connect to the Brev instance |
| `brev` | `brev_ip` | Public IP of the Brev instance |
| `brev` | `email_sender` | Gmail address used to send notifications |
| `brev` | `email_password` | Gmail app password (not the account password) |
| `brev` | `email_receivers` | Comma-separated list of recipient emails |
| `brev` | `slack_webhook` | Slack incoming webhook URL |
| `databricks` | `pat` | Databricks personal access token |

## Schedule

Runs every day at the set hour via Databricks job scheduler.

Job ID: `129636104529500`  
This job excludes itself when checking for active runs.

## Notifications

Every run sends a report to both email and Slack with one of these outcomes:

- **Instance is OFF** — no action taken
- **Instance is ON, jobs running** — lists active jobs, no action taken
- **Instance is ON, no jobs running** — instance shut down

## Setup

1. Ensure all secrets listed above are configured in Databricks
2. The Gmail account needs an [App Password](https://support.google.com/accounts/answer/185833) (not the regular password)
3. The Slack webhook must be created via [Slack Apps](https://api.slack.com/messaging/webhooks)
4. The SSH key must have access to `ubuntu@<brev_ip>` with sudo privileges
5. Schedule this notebook as a Databricks job at your desired interval

## Notes

- The notebook self-identifies its job ID (`current_job_id`) to avoid shutting down the instance while it's the only thing running. If the job is recreated, update this ID.
- SSH connection timeout is 10 seconds. If the instance is unreachable, it's treated as off.
- The `email_password` is sanitized for non-breaking spaces (known issue with some secret stores).
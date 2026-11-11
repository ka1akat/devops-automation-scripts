# Simplified GitLab Runner

Self-hosted GitLab group runner in Docker, managed by systemd.
Install, registration and cleanup are automated with scripts.

## Requirements
- Ubuntu with Docker, systemd, curl, jq, make
- GitLab personal access token with `api` scope (you must be the group Owner)

## Usage
```bash
read -rs GITLAB_TOKEN && export GITLAB_TOKEN   # token is never stored in files
make install                                   # install runner container + systemd service
make register GROUP_URL=https://gitlab.com/kbtu-group9974041
make status                                    # service and container status
make logs                                      # last runner logs
make cleanup                                   # remove runner, service, container, config
```

## Files
- `install_gitlab_runner.sh` — pulls `gitlab/gitlab-runner:v17.11.0`, creates persistent config dir, creates the container (no Docker restart policy), installs and starts the systemd service
- `register_gitlab_runner.sh` — finds the group ID, creates a group runner through the API (tag `karakat-runner`, untagged jobs disabled), registers it non-interactively with the Docker executor; repeated runs reuse the runner
- `cleanup.sh` — deletes the runner from GitLab, removes the service, container and config
- `gitlab-runner.service` — systemd unit: start after Docker, graceful stop, restart on failure with delay and rate limit, start at boot
- `.gitlab-ci.yml` — job that runs only on this runner and prints `[runner id] hello, devops.`

## Evidence
- Runner ID: `RUNNER_ID`
- Pipeline: https://gitlab.com/kbtu-group9974041/gitlab-runner/-/pipelines/3042016730
- Job output: `[RUNNER_ID] hello, devops.`
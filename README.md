# devops-automation-scripts

Hands-on DevOps practice from my university DevOps course (KBTU, Fall 2026).
Every folder has its own README: the task, the solution, how to run it and how it was tested.

## Assignments

- [Assignment 1 - PostgreSQL in Docker managed by systemd](ASSIGNMENTS/1_postgresql_systemd) - systemd service for a Docker container: startup dependencies, automatic recovery, non-root user, health checks with a timer, log files and daily log rotation

## Tasks

- [Task 1 - Linux: systemd service and log rotation](TASKS/1_linux_logrotate) - Flask API run by systemd, logs redirected to files, logrotate (1 MB, max 3 files), cron, resource limits
- [Task 2 - HashiCorp Vault in dev mode](TASKS/2_vault_dev) - Vault in Docker Compose
- [Task 3 - HashiCorp Vault in server mode](TASKS/3_vault_server) - volumes, config file, manual init and unseal
- [Task 4 - Investigating a suspicious Docker image](TASKS/4_docker_bomb) - found why the image was broken, fixed it with a new Dockerfile and pushed it to Docker Hub

## Practice

- [Practice 1A - split logs and log rotation](PRACTICE/1A_time_api_logrotate) - stdout and stderr in separate files, logrotate (500 KB, 4 files), cron every 2 minutes

## Lectures

- [LECTURE/1_LEC](LECTURE/1_LEC) - Python automation scripts: service health checks, retry logic, log processing

## Tools

Linux (Ubuntu), systemd, bash, Docker, Docker Compose, HashiCorp Vault, logrotate, cron, GitLab CI/CD, Python

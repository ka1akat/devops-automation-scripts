# Assignment 1: PostgreSQL in Docker managed by systemd

PostgreSQL 16 runs in a Docker container. A systemd service controls the
container: it starts at boot, waits for Docker and the network, restarts
after failures, checks database health, writes logs to files and rotates
them every day.

## Files

- `Dockerfile` - image based on `postgres:16` that runs as the non-root user `devopfall2026_user` (UID 2026).
- `postgresql.service` - the main systemd service that runs the container.
- `postgresql-wait-ready.sh` - startup check: waits up to 60 seconds for `SELECT 1`.
- `postgresql-healthcheck.sh` - one health check; restarts the service after 3 failures in a row.
- `postgresql-healthcheck.service` / `.timer` - run the health check every 30 seconds.
- `postgresql-logrotate.conf` - log rotation rules.
- `postgresql-logrotate.service` / `.timer` - run log rotation once a day.

## How each requirement is met

1. **Container lifecycle.** `ExecStart` runs `docker run` without `-d`, so systemd sees when the container exits. `ExecStop` runs `docker stop --time 60` for a graceful shutdown. Data is stored on the host in `/srv/postgresql/data` (mounted with `-v`), so it survives restarts and container recreation. `ExecStartPre` removes an old container first, so there are never duplicates.
2. **Startup dependencies.** `Requires=docker.service`, `Wants=network-online.target` and `After=docker.service network-online.target`. `systemd-networkd-wait-online.service` is enabled, so the network target really waits for the network.
3. **Recovery.** `Restart=on-failure` with `RestartSec=5`. Limit: 5 starts in 300 seconds (`StartLimitBurst`, `StartLimitIntervalSec`). A manual `systemctl stop` is not a failure, so the service stays stopped.
4. **Non-root.** The image creates `devopfall2026_user` with UID/GID 2026 and switches to it with `USER`. The data directory on the host is owned by `2026:2026` with mode `700`.
5. **Health checks.** At startup `ExecStartPost` waits up to 60 seconds for `SELECT 1` (`TimeoutStartSec=90`). After that a timer runs a check every 30 seconds with a 5-second timeout. After 3 failures in a row the script writes a message to the journal and runs `systemctl try-restart`, which does nothing if the service was stopped on purpose.
6. **Logs.** `StandardOutput=append:/var/log/postgresql/output.log` and `StandardError=append:/var/log/postgresql/error.log`. Old lines are kept after restarts. Directory mode `750`, files `640`.
7. **Rotation.** A daily timer runs logrotate with its own state file: keep 7 files, compress old ones, skip empty or missing files. `copytruncate` is used because systemd keeps the log files open: the file is copied and then emptied instead of renamed, so logging continues in the same file. Known limitation: a line written in the short moment between copy and truncate can be lost.

## How to install (Ubuntu VM)

```bash
sudo docker build -t devopfall2026/postgres:16 .

sudo mkdir -p /srv/postgresql/data
sudo chown 2026:2026 /srv/postgresql/data
sudo chmod 700 /srv/postgresql/data

sudo mkdir -p /etc/postgresql-docker
echo "POSTGRES_PASSWORD=change-me" | sudo tee /etc/postgresql-docker/secrets.env
sudo chmod 600 /etc/postgresql-docker/secrets.env

sudo mkdir -p /var/log/postgresql
sudo chmod 750 /var/log/postgresql

sudo cp postgresql-wait-ready.sh postgresql-healthcheck.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/postgresql-*.sh
sudo cp postgresql-logrotate.conf /etc/postgresql-docker/
sudo cp *.service *.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now postgresql postgresql-healthcheck.timer postgresql-logrotate.timer
```

The password file is not in the repository.

## How it was tested

- Reboot of the VM: the service started by itself.
- `docker exec postgresql id`: `uid=2026(devopfall2026_user)`.
- Created a table, restarted the service: the data was still there.
- `docker kill postgresql`: systemd restarted it (`NRestarts` went from 0 to 1).
- `systemctl stop postgresql`: the service stayed `inactive`.
- `docker pause postgresql`: health check failed 3 times in a row, then restarted the service.
- Restart of the service: the number of lines in `error.log` grew (append works).
- `logrotate --force`: `error.log` became empty, `error.log.1` was created, and new lines appeared in `error.log` after a restart.
- `docker ps --filter name=postgresql`: exactly one container.

# Task 1 — Linux: systemd service & log rotation

## Task

1. Create a simple API.
2. Create a directory `/home/logs` and redirect all application logs to log files in that folder.
3. Keep at most **3 log files** (delete older ones) with a size limit of **1 MB** per file.
4. Save the execution time of every log rotation to `/home/log_rotates.log`.

**Constraint:** the application code must not be changed — everything is done at the infrastructure level.

## Solution overview

```
Flask API (stdout/stderr)
        │  systemd redirects output
        ▼
/home/logs/app.log
        │  cron runs logrotate every minute
        ▼
app.log → app.log.1 → app.log.2 → deleted
        │  postrotate hook
        ▼
/home/log_rotates.log  (timestamp of each rotation)
```

## Repository structure

```
1_linux_logrotate/
├── app/
│   ├── app.py                  # simple Flask API, logs only to stdout
│   └── requirements.txt        # pinned dependencies
├── systemd/
│   └── simple-api.service      # runs the app, redirects logs, limits resources
├── logrotate/
│   └── simple-api              # rotation rules: 1 MB, 3 files total
├── cron/
│   └── simple-api-logrotate    # runs logrotate every minute
└── proof/                      # real output from the running system
```

## How to reproduce (Ubuntu 24.04)

```bash
# 1. App and dependencies
sudo apt update && sudo apt install -y python3-venv
sudo mkdir -p /opt/simple-api && sudo chown $USER:$USER /opt/simple-api
cp app/app.py app/requirements.txt /opt/simple-api/
python3 -m venv /opt/simple-api/venv
/opt/simple-api/venv/bin/pip install -r /opt/simple-api/requirements.txt

# 2. Log directory and systemd service
sudo mkdir -p /home/logs
sudo cp systemd/simple-api.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now simple-api

# 3. Log rotation
sudo cp logrotate/simple-api /etc/logrotate.d/
sudo cp cron/simple-api-logrotate /etc/cron.d/
```

## Key decisions

- **Logs are redirected by systemd**, not by the app (`StandardOutput=append:` / `StandardError=append:`). The app only prints to stdout and knows nothing about files.
- **`copytruncate`** — the app keeps the log file open and cannot reopen it (code changes are not allowed), so logrotate copies the file and truncates the original in place instead of renaming it.
- **`rotate 2`** — 2 archived files + the current `app.log` = 3 files in total.
- **cron every minute** — by default logrotate runs only once a day, which is not enough to enforce a 1 MB limit.
- **`PYTHONUNBUFFERED=1`** — Python buffers output when writing to a file; this makes every log line appear immediately.
- **Monitoring:** `Restart=always` restarts the app if it crashes; `/health` endpoint for health checks.
- **Resource limits:** `MemoryMax=200M`, `CPUQuota=20%`; the app runs as a non-root user.
- **Dependencies:** isolated in a virtual environment and pinned in `requirements.txt`.

## Verification

```bash
# generate ~1.3 MB of logs
for i in $(seq 1 10000); do curl -s http://localhost:5000/ > /dev/null; done

ls -lh /home/logs          # always max 3 files
cat /home/log_rotates.log  # one timestamp per rotation
```

Real output is saved in [`proof/`](proof/).
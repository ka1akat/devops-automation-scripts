# Task 2 - HashiCorp Vault in dev mode (Docker Compose)

## Task

Prepare a docker-compose file that:

1. Runs the `hashicorp/vault` Docker image
2. Exposes the Vault port (8200 inside the container) on port 8305 of the host machine
3. Uses `vault-dev` as the container name
4. Runs Vault in `dev` mode

Question: *Why do we need IPC_LOCK?*

## Solution

[`docker-compose.yml`](docker-compose.yml):

```yaml
services:
  vault:
    image: hashicorp/vault:latest
    container_name: vault-dev
    ports:
      - "8305:8200"
    environment:
      VAULT_DEV_ROOT_TOKEN_ID: root
      VAULT_DEV_LISTEN_ADDRESS: 0.0.0.0:8200
    cap_add:
      - IPC_LOCK
    command: server -dev
```

| Requirement | How it is done |
|---|---|
| `hashicorp/vault` image | `image: hashicorp/vault:latest` |
| Port 8200 → host 8305 | `ports: "8305:8200"` (host:container) |
| Container name `vault-dev` | `container_name: vault-dev` |
| Dev mode | `command: server -dev` |

`VAULT_DEV_ROOT_TOKEN_ID` sets a simple root token (`root`) instead of a random one, for easy login in a learning environment.

## How to run

```bash
docker compose up -d        # start in the background
docker ps                   # check: vault-dev, Up, 0.0.0.0:8305->8200/tcp
docker logs vault-dev       # check: "WARNING! dev mode is enabled!", "Root Token: root"
```

UI: open `http://localhost:8305` → Method: Token → Token: `root`.

Stop and remove: `docker compose down`.

## Why do we need IPC_LOCK?

Vault keeps secrets in memory in decrypted form. If the OS runs low on RAM, it can move (swap) memory pages to disk — and secrets could stay on disk in plain text.

Vault prevents this with `mlock` (memory lock): it asks the OS never to swap its memory to disk. Containers are not allowed to lock memory by default, so we grant this permission with `cap_add: IPC_LOCK`.

In dev mode Vault disables mlock by itself (data is in memory only and not meant to be secret). This is visible in the logs:

```
$ docker logs vault-dev 2>&1 | grep -i mlock
Mlock: supported: true, enabled: false
```

In server (production) mode mlock is enabled by default, and without `IPC_LOCK` Vault fails to start. Adding it in dev mode keeps the same setup ready for server mode, as recommended by the official image documentation.
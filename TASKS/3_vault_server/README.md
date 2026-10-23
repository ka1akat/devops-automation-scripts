# Task 3 — HashiCorp Vault in server mode (Docker Compose)

## Task

Extend the docker-compose from [Task 2](../2_vault_dev):

1. Create folder `./t/vault` with 3 subfolders: `config`, `file` and `logs`
2. Set up volumes
3. Use `vault-prod` as the container name
4. Run Vault in `server` mode with the given `config.hcl`

## Structure

```
3_vault_server/
├── docker-compose.yml          # vault-dev (Task 2) + vault-prod (this task)
├── .gitignore                  # Vault data and logs are not committed
└── t/vault/
    ├── config/config.hcl       # Vault server configuration
    ├── file/                   # encrypted Vault storage (created at runtime)
    └── logs/                   # Vault logs
```

## Solution

`vault-prod` service in [`docker-compose.yml`](docker-compose.yml):

```yaml
  vault-prod:
    image: hashicorp/vault:latest
    container_name: vault-prod
    ports:
      - "8306:8200"
    volumes:
      - ./t/vault/config:/vault/config
      - ./t/vault/file:/vault/file
      - ./t/vault/logs:/vault/logs
    cap_add:
      - IPC_LOCK
    command: server
```

- **Volumes** connect host folders to container folders (`host:container`). Vault reads its config from `/vault/config` and stores data in `/vault/file`, so the data stays on the host after the container is removed.
- **Port 8306** on the host, because 8305 is used by `vault-dev`.
- **`command: server`** (without `-dev`) — Vault loads the configuration from `/vault/config`.

[`config.hcl`](t/vault/config/config.hcl):

| Setting | Meaning |
|---|---|
| `storage "file"` | store secrets in files in `/vault/file` (on disk, not in memory) |
| `listener "tcp"` | listen on port 8200; `tls_disable = true` — no HTTPS (learning only) |
| `disable_mlock = true` | do not lock memory |
| `api_addr` / `cluster_addr` | addresses for clients and for other Vault nodes |
| `ui = true` | enable the web UI |

## How to run

```bash
mkdir -p t/vault/config t/vault/file t/vault/logs
docker compose up -d
docker exec -e VAULT_ADDR=http://127.0.0.1:8200 vault-prod vault status
# Initialized: false, Sealed: true
```

Then open `http://localhost:8306`:

1. **Initialize** — key shares: 5, key threshold: 3. Vault shows 5 unseal keys and a root token **once**. Save them and never commit them.
2. **Unseal** — enter any 3 of the 5 keys.
3. **Sign in** with the root token.

## Dev mode vs server mode

| | `vault-dev` (Task 2) | `vault-prod` (Task 3) |
|---|---|---|
| Storage | in memory | files on disk (`/vault/file`) |
| Configuration | environment variables | `config.hcl` |
| Start | initialized and unsealed automatically | must be initialized and unsealed manually |
| Root token | `root` (set by us) | random, generated at init |
| After restart | **all secrets are lost** | secrets are kept, Vault is sealed again |

## Verification: data survives a restart

1. Enabled a KV secrets engine at `secret/` and created the secret `secret/shop/database`.
2. Restarted the container: `docker compose restart vault-prod`.
3. Vault came back **sealed** (the root key lives only in memory).
4. After unsealing with 3 keys, the secret `secret/shop/database` was still there — it is stored on disk.

## Security notes

- Unseal keys and the root token are kept outside the repository.
- `t/vault/file/*` and `t/vault/logs/*` are in `.gitignore`: the storage is encrypted, but runtime data should not be committed.
- `tls_disable = true` and `disable_mlock = true` are acceptable for learning, but not for production.
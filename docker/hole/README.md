# The HOLE Foundation Paperclip deployments

These two compose stacks are kept apart from upstream's `docker/` files, so syncing the fork does not cause merge conflicts.

| Stack | Database | File storage | Use |
|---|---|---|---|
| `compose.virgin.yml` | embedded Postgres in the `paperclip-data` volume | local disk in the volume | a fresh instance for trials or throwaway use |
| `compose.central.yml` | central Postgres at `portainer.wolverine-wyrm.ts.net:5433` | Cloudflare R2 | the real instance; redeploy it anywhere and the data comes with it |

Both stacks:

- **Join the tailnet as an ephemeral node.** A `tailscale/tailscale` sidecar holds the network namespace, and Paperclip runs inside it with `network_mode: service:tailscale`. Tailnet IPs and MagicDNS names such as `portainer.wolverine-wyrm.ts.net` resolve and route directly. No host ports are published. The UI is at `http://<PAPERCLIP_TS_HOSTNAME>.wolverine-wyrm.ts.net:3100`, reachable only from the tailnet.
- **Bootstrap their environment from Infisical.** `scripts/hole/infisical-bootstrap.sh` wraps the image entrypoint. It logs in with a machine identity, loads every secret under `/bootstrap` as an environment variable (a non-empty variable already set on the host wins), checks `PAPERCLIP_REQUIRED_ENV`, removes the Infisical client secret from the environment, then starts Paperclip as usual.

## One-time setup

### Tailscale

1. In the ACL file, add `"tagOwners": { "tag:paperclip": ["autogroup:admin"] }` and grant `tag:paperclip` access to `portainer:5433` plus whatever else agents need.
2. Create an **OAuth client** with the `auth_keys` write scope and the `tag:paperclip` tag. Its secret is your `TS_AUTHKEY`. Nodes it registers are ephemeral by default. An auth key with *Ephemeral* checked also works.

Tailscale state is held in memory, so every container start registers a new node, and the old one drops off shortly after it disconnects. If the previous node has not expired yet, the new one gets a `-1` suffix on its name.

### Infisical

Create a project with one environment (default slug `prod`) and a Universal Auth machine identity that has read access to it.

| Folder | Contents | Read by |
|---|---|---|
| `/bootstrap` | instance env vars: `BETTER_AUTH_SECRET`, `PAPERCLIP_SECRETS_MASTER_KEY`, `PAPERCLIP_TOOL_ACTION_SIGNING_SECRET`, `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`; for central also `DATABASE_URL`, `PAPERCLIP_STORAGE_S3_ENDPOINT`, `RUN_LOG_S3_ENDPOINT`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` | `infisical-bootstrap.sh`, on every boot |
| `/paperclip` | secrets agents should use (GitHub tokens, API keys, ...) | `infisical-import-secrets.sh`, on demand |

Generate the instance keys once and never rotate `PAPERCLIP_SECRETS_MASTER_KEY` on the central instance. Every secret stored in the central database is encrypted with it.

```sh
openssl rand -hex 32      # BETTER_AUTH_SECRET, PAPERCLIP_TOOL_ACTION_SIGNING_SECRET
openssl rand -base64 32   # PAPERCLIP_SECRETS_MASTER_KEY
```

On the host, or in the Portainer stack env, set only `TS_AUTHKEY` and the three `INFISICAL_*` values. See `.env.example`.

### Central Postgres (central stack only)

```sql
CREATE ROLE paperclip LOGIN PASSWORD '...';
CREATE DATABASE paperclip OWNER paperclip;
```

The role has to own the database because the migrations create the `pg_trgm` and `fuzzystrmatch` extensions, which are trusted, so a database owner can create them. Migrations run on boot (`PAPERCLIP_MIGRATION_AUTO_APPLY=true`).

**Run one live instance per database.** Two servers on the same database would both run the heartbeat scheduler. For a second independent instance, create a second database and a second R2 prefix.

### Cloudflare R2 (central stack only)

Create a bucket (default name `paperclip`) and an R2 API token with *Object Read & Write* on that bucket only. Put its access key id and secret in `/bootstrap` as `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`, and `https://<account-id>.r2.cloudflarestorage.com` as `PAPERCLIP_STORAGE_S3_ENDPOINT`. Objects go under `PAPERCLIP_STORAGE_S3_PREFIX` (default `central`).

Also add `RUN_LOG_S3_ENDPOINT` to `/bootstrap` with the value `${PAPERCLIP_STORAGE_S3_ENDPOINT}`. That is an Infisical secret reference, and the bootstrap expands it.

What goes where:

- **Attachments, uploads and artifacts** go straight to R2 through Paperclip's S3 storage provider. Paperclip reads one object per API request rather than using R2 as a filesystem.
- **Run logs** are written to the local volume first and mirrored to R2 under `<prefix>/run-logs` when each run finishes (`RUN_LOG_S3_*`). The local volume acts as the cache and R2 as the durable copy, using Paperclip's built-in run-log mirror.
- **Agent working directories** stay on the local `paperclip-data` volume. Git is their source of truth, and putting a git checkout on object storage is the slow, write-heavy pattern to avoid.

No cache proxy sits in front of R2. Neither path uses R2 as a disk, so a proxy would add a service without removing meaningful load.

## Deploy

```sh
cd docker/hole
cp .env.example .env   # TS_AUTHKEY + INFISICAL_* only
docker compose -f compose.central.yml up -d --build   # or compose.virgin.yml
docker compose -f compose.central.yml logs -f paperclip
```

In Portainer, create a stack from this Git repository with compose path `docker/hole/compose.central.yml` and set the same four variables in the stack environment.

If a required value is missing, the central stack exits with `refusing to start; required env missing: ...`. It never falls back to a fresh embedded database.

## Import agent secrets from Infisical

Create a board API key in the Paperclip UI, then:

```sh
docker compose -f compose.central.yml exec \
  -e PAPERCLIP_BOARD_API_KEY=... -e PAPERCLIP_COMPANY_ID=... \
  paperclip sh /app/scripts/hole/infisical-import-secrets.sh
```

Every secret in `/paperclip` (override with `INFISICAL_IMPORT_PATH`) is created in the company's secret store, or rotated to the Infisical value if its key already exists. Re-run it after changing secrets in Infisical.

## Troubleshooting

- `tailscale` never turns healthy: the auth key is wrong or expired, or the tag is not permitted. Check `docker compose logs tailscale`.
- DB connection errors on `*.ts.net`: run `docker compose exec paperclip getent hosts portainer.wolverine-wyrm.ts.net`. If MagicDNS fails, put the tailnet IP in `DATABASE_URL`.
- Bootstrap self-test: `sh scripts/hole/infisical-bootstrap.test.sh`.

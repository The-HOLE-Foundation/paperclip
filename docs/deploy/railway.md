---
title: Railway
summary: Deploy Paperclip on Railway with managed Postgres (Docker Compose equivalent)
---

Deploy Paperclip to [Railway](https://railway.com) as a cloud service using the project's Dockerfile. This gives you a production-like setup with a dedicated managed Postgres database, matching the architecture of `docker/docker-compose.yml`.

Railway provides:
- GitHub-connected continuous deploys
- Managed PostgreSQL (with private networking)
- Persistent Volumes for `/paperclip` data
- Automatic HTTPS + public domains
- Easy env var + secret management

## Prerequisites

- A Railway account (free tier is sufficient to start)
- This repository (connected via GitHub for best results)
- `railway` CLI (optional but recommended): `npm i -g @railway/cli` or `brew install railway`

## High-Level Architecture (Docker Compose → Railway)

| docker-compose.yml     | Railway Equivalent                  |
|------------------------|-------------------------------------|
| `db` (postgres:17)     | Add **PostgreSQL** database service |
| `server` (Dockerfile)  | Your **Paperclip** service (Dockerfile build) |
| named volumes          | Attach **Volume** to the app service at `/paperclip` |
| env vars               | Service Variables (with references) |

## Step-by-Step Setup

### 1. Create a Railway Project

**Recommended (persistent + GitHub deploys):**

1. Go to [Railway dashboard](https://railway.com) → **New Project**
2. Choose **Deploy from GitHub repo**
3. Select your Paperclip fork/repo
4. Railway detects the root `Dockerfile` and starts a build

Or from CLI (from repo root):

```bash
railway init
railway up
```

### 2. Add a Dedicated Postgres Database

In the Railway canvas or CLI:

**Dashboard:**
- Click **+ New** → **Database** → **PostgreSQL**

**CLI:**
```bash
railway add --database postgresql
```

This provisions a managed Postgres instance in the same project. It will expose variables such as:
- `DATABASE_URL`
- `DATABASE_PRIVATE_URL` (recommended for same-project services)
- `PGHOST`, `PGPORT`, `PGUSER`, `PGPASSWORD`, `PGDATABASE`

### 3. Configure the Paperclip Service Variables

Select your Paperclip service → **Variables** tab.

Add / set the following (use the variable reference picker where possible):

**Required:**

| Variable                        | Value / Reference                                      | Notes |
|---------------------------------|--------------------------------------------------------|-------|
| `DATABASE_URL`                  | `${{Postgres.DATABASE_PRIVATE_URL}}` or `DATABASE_URL` from the Postgres service | Use private for security |
| `BETTER_AUTH_SECRET`            | Generate locally: `openssl rand -hex 32` (mark as secret) | **Critical auth secret** |
| `PAPERCLIP_PUBLIC_URL`          | `https://${{RAILWAY_PUBLIC_DOMAIN}}` (or hardcode the assigned domain) | Must be the public HTTPS URL users will access |
| `PAPERCLIP_DEPLOYMENT_MODE`     | `authenticated`                                        | Required for cloud |
| `PAPERCLIP_DEPLOYMENT_EXPOSURE` | `public`                                               | Internet-facing |
| `PAPERCLIP_MIGRATION_AUTO_APPLY`| `true`                                                 | Auto-run migrations on first boot |

**Strongly recommended:**

| Variable             | Value          | Notes |
|----------------------|----------------|-------|
| `HOST`               | `0.0.0.0`      | Dockerfile already sets this |
| `SERVE_UI`           | `true`         | Serve the React UI from the same container |
| `PAPERCLIP_HOME`     | `/paperclip`   | Where persistent data lives (pairs with Volume) |

**Optional (for running agents inside the container):**

- `OPENAI_API_KEY`
- `ANTHROPIC_API_KEY`
- `GEMINI_API_KEY`
- etc.

After changing variables, **redeploy** the service (Railway stages variable changes).

### 4. Attach a Persistent Volume

Paperclip stores uploads, agent workspaces, instance config, and other data under `PAPERCLIP_HOME` (`/paperclip`).

1. Select the Paperclip service
2. Go to **Volumes**
3. **New Volume**
4. Mount path: `/paperclip`
5. Size: start with 5–10 GB (increase later as needed)

This is the equivalent of the `paperclip-data` volume in compose.

> **Note:** The database itself lives in the separate Postgres service. The volume is for file assets and Paperclip instance state.

### 5. Deploy

- Push to your connected GitHub branch, or run:
  ```bash
  railway up --detach -m "Initial Railway deployment"
  ```
- Watch the build in the dashboard or with `railway logs`.

On first successful deploy the server will:
- Connect to the external Postgres
- Apply pending migrations (because we set `PAPERCLIP_MIGRATION_AUTO_APPLY=true`)
- Start listening on Railway's assigned `$PORT`

### 6. Access Your Instance

1. Open the public URL shown in the service (or custom domain you added).
2. Sign up / sign in using the Better Auth flow.
3. For a fresh `authenticated/public` instance you may see a "Claim this instance" option, or use the CLI bootstrap flow.

#### Bootstrap the first admin (if needed)

From a machine with the CLI and linked project (or using `railway run`):

```bash
# Example — adapt as needed
railway run --service <paperclip-service-name> \
  pnpm paperclipai auth bootstrap-ceo
```

Or shell into a running deployment if Railway exec is available for your plan, or run one-off commands.

Many teams start by signing up in the browser, then promote the first user via the board claim link that appears in logs on first boot.

Check startup logs for any one-time claim URL:

```bash
railway logs --service paperclip
```

### 7. (Optional) Custom Domain + HTTPS

Railway gives you a free `*.up.railway.app` domain automatically.

To use your own domain:
- Service → **Settings** → **Domains** → Add domain
- Update `PAPERCLIP_PUBLIC_URL` to your custom domain
- Update any `BETTER_AUTH_TRUSTED_ORIGINS` if you add extra hostnames

### 8. Environment & Redeploys

- Use separate Railway **environments** (production / staging) if desired.
- Database and volumes are per-environment when using environment-scoped resources.
- Redeploy with latest code: `railway redeploy` or push to GitHub.

## Common Environment Variables Reference

See the full list in [environment-variables.md](./environment-variables.md).

Key ones for Railway:

- `DATABASE_URL` (external Postgres)
- `BETTER_AUTH_SECRET`
- `PAPERCLIP_PUBLIC_URL`
- `PAPERCLIP_DEPLOYMENT_MODE=authenticated`
- `PAPERCLIP_DEPLOYMENT_EXPOSURE=public`
- `PAPERCLIP_MIGRATION_AUTO_APPLY=true`

## Health Checks

- App health: `GET /health` (or `/api/health`)
- Railway can monitor this. You can configure a custom healthcheck path in service settings if desired.

## Data & Backups

- **Postgres**: Use Railway's database backups / snapshots from the Postgres service panel. Consider periodic exports.
- **File storage**: The attached Volume is your persistence. For production multi-replica or high durability, consider switching storage provider to S3 (see [storage.md](./storage.md)).

## Config as Code (`.railway/railway.ts`)

This repository includes a starter Infrastructure-as-Code definition:

```sh
.railway/railway.ts
```

It declares:

- A managed Postgres database (`paperclip-db`)
- The Paperclip service built from the root `Dockerfile`
- Wiring for `DATABASE_URL` and key deployment settings

### Useful commands

```bash
# Preview what the IaC would do
railway config plan

# Apply the configuration to a linked Railway project
railway config apply
```

See `.railway/README.md` (generated by Railway) and the [Config as Code docs](https://docs.railway.com/config-as-code/reference) for more.

The simple `railway.toml` at the root also provides build hints (Dockerfile builder) and works alongside the IaC file.

## One-Click Railway Template

Once you have a working deployment, you can turn it into a reusable template:

1. In the Railway dashboard, go to your project.
2. Project **Settings** (top right) → scroll to **Generate Template from Project**.
3. Review the services (Paperclip + Postgres).
4. In the template editor:
   - Add required variables with good defaults / references.
   - For `BETTER_AUTH_SECRET`, use the template function: `${{ secret(32, "hex") }}`
   - Attach guidance for the Volume (`/paperclip`).
5. Save → **Publish** (makes it appear in the marketplace and eligible for the open-source kickback program).

### Deploy button

After publishing, you can share a one-click link:

```md
[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/deploy/your-template-slug)
```

Add it to your README or docs.

**Example (replace with your published template):**

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/new/template/paperclip)

This gives anyone a full Paperclip + dedicated Postgres instance in one click — exactly mirroring the `docker-compose.yml` full stack but fully managed.

### CLI workflow for templates

```bash
# From a deployed/linked project
railway templates create --json

# Then publish (fill in the ID from above)
railway templates publish <template-id> \
  --category "Developer Tools" \
  --description "Paperclip control plane for AI agent teams. Includes Postgres." \
  --readme-file docs/deploy/railway.md
```

You can iterate on the template in the dashboard editor even after creating it via CLI.

## Tips for a High-Quality Template

- Always prefer variable references (e.g. `DATABASE_URL` → the Postgres service variable).
- Mark secrets properly in the template editor.
- Document the first-login / bootstrap flow in the template description.
- Include the healthcheck path (`/health`).
- Mention that users should attach a Volume at `/paperclip` for persistent file storage.

## Summary

You now have three ways to run Paperclip on Railway:

1. Manual (GitHub deploy + add Postgres + variables) — great for learning.
2. Config as Code (`.railway/railway.ts`) — reproducible and versioned.
3. Published Template — one-click for you and others.

Everything stays aligned with the original Docker Compose design: dedicated Postgres, single service serving UI+API, and persistent storage.

## Troubleshooting

### "authenticated public deployments require DATABASE_URL"

You must provide a real `postgres://` connection string. Do not rely on embedded PGlite for public deployments.

### Migrations not applying

Set `PAPERCLIP_MIGRATION_AUTO_APPLY=true` and redeploy. Check logs for migration output.

### Auth / callback issues

Ensure `PAPERCLIP_PUBLIC_URL` exactly matches the URL you open in the browser (including `https://`, no trailing slash issues).

### Permission / volume issues

The Dockerfile + entrypoint handles UID remapping. Railway containers usually run as non-root; the entrypoint is defensive.

### Logs

```bash
railway logs --service <name> --follow
```

## One-Click Template (Future)

Once stable, a Railway template button can be added that provisions:
- Postgres
- Paperclip service (source = your repo)
- Pre-filled variable references
- Volume suggestion

For now, follow the manual steps above — they are reliable and explicit.

## Summary of Differences from Local Docker Compose

- No need to manage `docker-compose.yml` or local volumes in prod.
- Use Railway's managed DB + private networking.
- Set `PAPERCLIP_PUBLIC_URL` and auth secrets explicitly.
- Attach Volume for `/paperclip`.
- GitHub deploys replace `docker compose up --build`.

This gives you a clean, scalable, always-on Paperclip instance in the cloud.

# Paperclip systemd deployment

Runs Paperclip from the **bleeding-edge git source** in this repo (via
`pnpm paperclipai run`) as a boot-persistent systemd service, instead of the
npx-installed release. Built for the cloneable base VPS image.

## Install

```bash
sudo ./scripts/deploy/install-systemd.sh
```

This copies `paperclip.service` to `/etc/systemd/system/`, runs
`daemon-reload`, and `enable --now` (so it also starts on boot).

## Operate

```bash
systemctl status paperclip.service
journalctl -u paperclip -f          # follow logs
sudo systemctl restart paperclip.service
```

## Why the unit looks the way it does

systemd starts processes with an **empty environment** and does **not** source
`~/.bashrc` (which bails early for non-interactive shells anyway). So the unit
reconstructs exactly what an interactive `cd ~/paperclip && pnpm paperclipai run`
sees:

- **`node`** is pinned to the fnm `default` alias
  (`~/.local/share/fnm/aliases/default/bin`). This is a stable path that follows
  node upgrades — unlike the ephemeral `/run/user/.../fnm_multishells/...` path
  a login shell uses, which does not exist under systemd.
- **`pnpm`** is corepack (`#!/usr/bin/env node`), invoked by absolute path from
  nvm's bin dir; it only needs `node` ahead of it on `PATH`, which it has.
- **`HOME=/home/paperclip`** so the CLI resolves `~/.paperclip/instances/default`.

The server reads its bind/host/port and `allowedHostnames` from
`~/.paperclip/instances/default/config.json` (currently `0.0.0.0:3131`), which is
reachable over the netbird `wt0` interface at
`paperclip.eu1.netbird.services` — that hostname must be present in
`allowedHostnames` or requests get a 403.

## Per-clone gotcha

`config.json` may point `database.connectionString` at a shared cloud Postgres
(e.g. Neon). Every clone of this image will share that database unless you update
the connection string per clone.

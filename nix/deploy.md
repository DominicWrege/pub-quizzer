# Deploying pub-quizzer on NixOS

## Overview

The flake produces a self-contained Elixir release and a NixOS module.
Build on the server, run behind your existing Caddy, secrets as plain files.

## 1. Flake setup (one-time)

Add the flake to your server's flake inputs:

```nix
# flake.nix on the server
inputs.pub-quizzer.url = "github:YOURNAME/pub-quizzer";
```

Import the module and overlay — see `nix/example-server.nix` for a
ready-to-copy example.

## 2. Create the environment file (one-time)

All config + secrets go in **one file**:

```bash
sudo mkdir -p /var/lib/pub-quizzer/secrets

sudo tee /var/lib/pub-quizzer/secrets/env <<EOF
SECRET_KEY_BASE=$(nix run nixpkgs#openssl -- rand -base64 48)
RELEASE_COOKIE=$(nix run nixpkgs#openssl -- rand -base64 32)
RESEND_API_KEY=your_resend_key_here
MAIL_FROM=noreply@quizforabetterlife.eu
DATABASE_PATH=/var/lib/pub-quizzer/pub_quizzer.db
EOF

sudo chown pub-quizzer:pub-quizzer /var/lib/pub-quizzer/secrets/env
sudo chmod 640 /var/lib/pub-quizzer/secrets/env
```

> `/var/lib/pub-quizzer/secrets/env` persists across reboots (unlike
> `/run/secrets` which is tmpfs). The systemd `ProtectSystem=strict`
> hardening in the module allows the service to read this path.

## 3. Caddy

Add one block (you already run Caddy — it handles TLS via Let's Encrypt):

```
quizforabetterlife.eu {
    reverse_proxy localhost:4000
}
```

Caddy sets `X-Forwarded-Proto`, which the app's `force_ssl` rewrites on.
No extra TLS config needed.

## 4. Deploy

```bash
# on the server
sudo nixos-rebuild switch --flake .#yourhostname
```

The service auto-runs migrations (`ExecStartPre`) then starts Bandit.

## 5. Verify

```bash
systemctl status pub-quizzer
journalctl -u pub-quizzer -f
curl -I https://quizforabetterlife.eu
```

## 6. Update

Push to GitHub, then on the server:

```bash
sudo nixos-rebuild switch --flake .#yourhostname
```

Nix pulls the new revision, rebuilds the release, and restarts the service.

## Notes

- **SQLite**: the database lives at `/var/lib/pub-quizzer/pub_quizzer.db`.
  Back up this file regularly.
- **Assets**: the release bundles the committed, minified assets from
  `priv/static/`. After changing JS/CSS, run `mix assets.build` locally and
  commit the output before deploying.
- **No distribution**: the app runs as a single node (no `RELEASE_NODE`).
  Clustering is possible via `dnsClusterQuery` if needed later.

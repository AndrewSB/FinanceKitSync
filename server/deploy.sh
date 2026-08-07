#!/usr/bin/env bash
#
# Deploy the sync server to box.
#
# Idempotent: safe to re-run. Only touches /opt/financekitsync and the
# Tailscale serve/funnel config for its OWN port (8501 by default) — every
# other service on this host is left alone.
#
# This service used to serve on :8443, which it shared with box-api at /api and
# the web UI at /. A `tailscale serve --https=8443 <target>` sets the ROOT path
# of that port, so each deploy silently evicted whatever was mounted at / —
# which is exactly what happened to the web UI. Serving on a port this service
# owns outright makes that class of collision impossible, and means a future
# Funnel decision here cannot publish someone else's routes.
#
set -euo pipefail

HOST="${FKS_HOST:-box}"
REMOTE_DIR="${FKS_REMOTE_DIR:-/opt/financekitsync}"
SERVE_PORT="${FKS_SERVE_PORT:-${FKS_FUNNEL_PORT:-8501}}"
LOCAL_PORT=8501

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Syncing source to ${HOST}:${REMOTE_DIR}"
ssh "$HOST" "mkdir -p ${REMOTE_DIR}"
rsync -az --delete \
  --exclude '.env' \
  --exclude 'data/' \
  --exclude '__pycache__/' \
  --exclude '.venv/' \
  "${here}/" "${HOST}:${REMOTE_DIR}/"

echo "==> Ensuring token exists"
# Generated once and left alone on subsequent deploys, so a re-deploy never
# silently invalidates the token already configured in the app.
ssh "$HOST" bash -s <<REMOTE
set -euo pipefail
cd "${REMOTE_DIR}"
if [ ! -f .env ]; then
  token="\$(head -c 32 /dev/urandom | base64 | tr -d '/+=' | head -c 40)"
  printf 'FKS_TOKEN=%s\n' "\$token" > .env
  chmod 600 .env
  echo "    generated a new token"
else
  echo "    keeping existing token"
fi
# The container runs as uid 10001 (see Dockerfile); the bind-mounted data
# directory has to be writable by that uid or SQLite can't create the file.
mkdir -p data
chown -R 10001:10001 data
REMOTE

echo "==> Building and starting the container"
ssh "$HOST" "cd ${REMOTE_DIR} && docker compose up -d --build"

echo "==> Waiting for health"
ssh "$HOST" bash -s <<REMOTE
set -euo pipefail
for i in \$(seq 1 30); do
  if curl -fsS "http://127.0.0.1:${LOCAL_PORT}/health" >/dev/null 2>&1; then
    echo "    healthy"
    exit 0
  fi
  sleep 1
done
echo "    never became healthy; recent logs:" >&2
docker logs --tail 40 financekitsync >&2
exit 1
REMOTE

echo "==> Serving on the tailnet at :${SERVE_PORT}"
ssh "$HOST" "tailscale serve --bg --https=${SERVE_PORT} http://127.0.0.1:${LOCAL_PORT}" >/dev/null

# Funnel is deliberately NOT enabled here.
#
# Funnel is per-PORT, not per-path, which is the other reason this service now
# owns its port: publishing :${SERVE_PORT} publishes this service and nothing
# else, and turning it off again cannot delete a neighbour's config. That was
# not true while this shared :8443 with box-api and the web UI.
#
# Before enabling it, check that the port is Funnel-eligible on this tailnet
# (Funnel is restricted to a small set of ports) and remember what goes public:
# /health is unauthenticated by design, and every other route is one bearer
# token away from the open internet.
#
#   FKS_ENABLE_FUNNEL=1 ./deploy.sh
#
if [ "${FKS_ENABLE_FUNNEL:-0}" = "1" ]; then
  echo "==> Enabling Funnel on :${SERVE_PORT} (this publishes EVERY route on this port)"
  ssh "$HOST" "tailscale serve status | sed -n '/:${SERVE_PORT}/,/^$/p'"
  ssh "$HOST" "tailscale funnel --bg --https=${SERVE_PORT} http://127.0.0.1:${LOCAL_PORT}" >/dev/null
else
  echo "    (tailnet only — set FKS_ENABLE_FUNNEL=1 to publish publicly; see the note in this script)"
fi

dns="$(ssh "$HOST" "tailscale status --json | python3 -c \"import json,sys; print(json.load(sys.stdin)['Self']['DNSName'].rstrip('.'))\"")"
token="$(ssh "$HOST" "grep '^FKS_TOKEN=' ${REMOTE_DIR}/.env | cut -d= -f2-")"

echo
echo "Deployed."
echo "  URL:   https://${dns}:${SERVE_PORT}"
echo "  Token: ${token}"
echo
echo "Enter both in the app under Settings -> Your server."

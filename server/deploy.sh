#!/usr/bin/env bash
#
# Deploy the sync server to box.
#
# Idempotent: safe to re-run. Only touches /opt/financekitsync and the
# localhost service on port 8501. Box API is the only network boundary and
# forwards the namespaced FinanceKit RPC routes.
#
# This service used to have its own Tailscale listener. Keeping it on loopback
# makes exposure impossible here: only Box API decides which RPCs cross the
# machine boundary.
#
set -euo pipefail

HOST="${FKS_HOST:-box}"
REMOTE_DIR="${FKS_REMOTE_DIR:-/opt/financekitsync}"
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

dns="$(ssh "$HOST" "tailscale status --json | python3 -c \"import json,sys; print(json.load(sys.stdin)['Self']['DNSName'].rstrip('.'))\"")"

echo
echo "Deployed."
echo "  URL:   https://${dns}:8443/api/financekit"
echo
echo "The token remains in ${REMOTE_DIR}/.env and is never printed by this script."

#!/usr/bin/env bash
#
# Back up the sync database.
#
# Uses SQLite's online backup API rather than `cp`: the database runs in WAL
# mode, and a plain file copy taken mid-write is not guaranteed consistent.
# `.backup` takes a proper snapshot while the server keeps serving.
#
# Install as a nightly cron job on box:
#   0 3 * * * /opt/financekitsync/backup.sh >> /var/log/financekitsync-backup.log 2>&1
#
set -euo pipefail

DB="${FKS_DB:-/opt/financekitsync/data/financekitsync.db}"
DEST="${FKS_BACKUP_DIR:-/opt/financekitsync/backups}"
KEEP="${FKS_BACKUP_KEEP:-14}"

if [ ! -f "$DB" ]; then
  echo "no database at ${DB}" >&2
  exit 1
fi

mkdir -p "$DEST"
stamp="$(date -u +%Y%m%dT%H%M%SZ)"
target="${DEST}/financekitsync-${stamp}.db"

sqlite3 "$DB" ".backup '${target}'"

# Verify before trusting it. A backup nobody has opened is a hope, not a backup.
if ! sqlite3 "$target" "PRAGMA integrity_check" | grep -q '^ok$'; then
  echo "integrity check FAILED for ${target}" >&2
  exit 1
fi

rows="$(sqlite3 "$target" "SELECT COUNT(*) FROM transactions")"
gzip -f "$target"

echo "$(date -u +%FT%TZ) backed up ${rows} transactions to ${target}.gz"

# Prune, keeping the newest $KEEP.
ls -1t "${DEST}"/financekitsync-*.db.gz 2>/dev/null \
  | tail -n +$((KEEP + 1)) \
  | while read -r old; do
      echo "  pruning $(basename "$old")"
      rm -f "$old"
    done

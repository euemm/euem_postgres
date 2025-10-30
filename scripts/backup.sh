#!/bin/bash
set -euo pipefail

BACKUP_DIR="/srv/postgres/backups"
CONTAINER_NAME="postgres16"

# Pull creds from your .env (if you run `source .env` before calling this script)
DB_NAME="${POSTGRES_DB:-euem_db}"
DB_USER="${POSTGRES_USER:-}"
DB_PASS="${POSTGRES_PASSWORD:-}"

if [ -z "$DB_PASS" ]; then
  echo "ERROR: POSTGRES_PASSWORD not set. Export it or source your .env first." >&2
  exit 1
fi

mkdir -p "$BACKUP_DIR"

DATE="$(date +%Y%m%d_%H%M%S)"
OUT="$BACKUP_DIR/backup_${DB_NAME}_${DATE}.sql.gz"

# Supply the password via env var; force IPv4 localhost to avoid ::1 auth quirks
docker exec -e PGPASSWORD="$DB_PASS" "$CONTAINER_NAME" \
  pg_dump -h 127.0.0.1 -U "$DB_USER" -d "$DB_NAME" -F p | gzip -9 > "$OUT"

find "$BACKUP_DIR" -type f -name "backup_${DB_NAME}_*.sql.gz" -mtime +30 -delete

echo "Backup completed: $OUT"
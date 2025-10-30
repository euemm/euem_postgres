# Backup Guide

This guide covers backup and recovery procedures for the EUEM PostgreSQL database.

## Overview

Regular backups are essential for data protection, disaster recovery, and compliance. This database stores critical user data and authentication information that must be protected against loss.

## Backup Strategies

### Backup Types

**Full Backup**: Complete database snapshot including all tables, indexes, and data.

**Incremental Backup**: Only changes since the last backup (requires WAL archiving).

**Logical Backup**: SQL dumps that can be read and edited, portable across PostgreSQL versions.

**Physical Backup**: Raw data files, faster but less portable.

For this setup, we recommend regular **logical backups** with periodic **full backups**.

## Automated Backups

### Docker Compose Backup Script

Create a backup script for automated daily backups:

```bash
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
```

**Key features of this script**:
- Reads credentials from environment variables (`.env` file)
- Uses `set -euo pipefail` for error handling
- Forces IPv4 connection (`-h 127.0.0.1`) to avoid authentication issues
- Uses maximum compression (`gzip -9`)
- Includes database name in backup filename
- Validates password is set before attempting backup

**To use the script**:

1. Make the script executable:
```bash
chmod +x scripts/backup.sh
```

2. Source your `.env` file and run:
```bash
source .env && ./scripts/backup.sh
```

Or export variables manually:
```bash
export POSTGRES_DB=euem_db
export POSTGRES_USER=your_username
export POSTGRES_PASSWORD=your_password
./scripts/backup.sh
```

### Cron Job Setup

Schedule daily backups at 2 AM:

```bash
# Edit crontab
crontab -e

# Add this line (sources .env to get credentials before running backup)
0 2 * * * cd /path/to/project && source .env && ./scripts/backup.sh >> /var/log/postgres-backup.log 2>&1
```

**Alternative**: If you prefer to set environment variables explicitly in cron:

```bash
# Add these lines to crontab
0 2 * * * POSTGRES_DB=euem_db POSTGRES_USER=your_username POSTGRES_PASSWORD=your_password /path/to/scripts/backup.sh >> /var/log/postgres-backup.log 2>&1
```

## Manual Backup Procedures

### Full Database Backup

Create a compressed SQL dump:

```bash
# Using PGPASSWORD environment variable (recommended)
docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" postgres16 \
  pg_dump -h 127.0.0.1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -F p | gzip -9 > euem_db_$(date +%F).sql.gz

# Or using the interactive method (will prompt for password)
docker exec postgres16 pg_dump -U your_username -d euem_db | gzip -9 > euem_db_$(date +%F).sql.gz
```

### Schema-Only Backup

Backup table structures without data:

```bash
docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" postgres16 \
  pg_dump -h 127.0.0.1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" --schema-only | gzip -9 > schema_$(date +%F).sql.gz
```

### Data-Only Backup

Backup only data without schema definitions:

```bash
docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" postgres16 \
  pg_dump -h 127.0.0.1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" --data-only | gzip -9 > data_$(date +%F).sql.gz
```

### Single Table Backup

Backup a specific table:

```bash
docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" postgres16 \
  pg_dump -h 127.0.0.1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t users | gzip -9 > users_$(date +%F).sql.gz
```

## Backup Formats

### Compressed SQL Format (Recommended)

This format is recommended for all backups:

**Advantages**:
- Human-readable
- Portable across PostgreSQL versions
- Can be edited before restore
- Compresses well with gzip
- Simple restore process
- Version-agnostic

**Compression**:
- Typically achieves 70-90% size reduction
- Fast compression and decompression

```bash
# Create compressed backup
docker exec postgres16 pg_dump -U your_username -d euem_db | gzip > backup.sql.gz

# Create uncompressed backup (if needed for editing)
docker exec postgres16 pg_dump -U your_username -d euem_db -F p > backup.sql
```

## Recovery Procedures

### Full Database Restore

**From compressed SQL backup**:

```bash
# Stop the application
docker compose stop

# Restore database from compressed SQL
gunzip < euem_db_2024-01-15.sql.gz | docker exec -i postgres16 psql -U your_username -d euem_db

# Or from uncompressed SQL file
docker exec -i postgres16 psql -U your_username -d euem_db < backup.sql

# Start the application
docker compose start
```

### Restore to New Database

Create a new database and restore:

```bash
# Create new database
docker exec postgres16 psql -U your_username -c "CREATE DATABASE euem_db_restore;"

# Restore to new database
gunzip < backup.sql.gz | docker exec -i postgres16 psql -U your_username -d euem_db_restore
```

### Selective Restore

To restore specific tables from an SQL backup:

**Option 1**: Edit the SQL file before restoring

```bash
# Extract and edit the backup
gunzip < backup.sql.gz > backup_edit.sql
# Edit backup_edit.sql to keep only desired tables
docker exec -i postgres16 psql -U your_username -d euem_db < backup_edit.sql
```

**Option 2**: Restore to temporary database and copy tables

```bash
# Create temporary database
docker exec postgres16 psql -U your_username -c "CREATE DATABASE temp_restore;"

# Restore full backup to temp database
gunzip < backup.sql.gz | docker exec -i postgres16 psql -U your_username -d temp_restore

# Copy specific tables to main database
docker exec postgres16 pg_dump -U your_username -d temp_restore -t users -t roles | \
    docker exec -i postgres16 psql -U your_username -d euem_db

# Clean up
docker exec postgres16 psql -U your_username -c "DROP DATABASE temp_restore;"
```

## Continuous Archiving (WAL)

For high-availability systems, enable Write-Ahead Logging (WAL) archiving:

### Configuration

Edit `docker-compose.yml`:

```yaml
environment:
  - POSTGRES_WAL_LEVEL=replica
command:
  - -c
  - archive_mode=on
  - -c
  - archive_command='test ! -f /backups/archivedir/%f && cp %p /backups/archivedir/%f'
```

Create archive directory:

```bash
mkdir -p /srv/postgres/archivedir
```

### Base Backup with WAL

```bash
# Perform base backup
docker exec postgres16 psql -U postgres -c "SELECT pg_start_backup('backup_label');"
docker cp postgres16:/var/lib/postgresql/data /srv/postgres/base_backup_$(date +%F)
docker exec postgres16 psql -U postgres -c "SELECT pg_stop_backup();"
```

### Point-in-Time Recovery

```bash
# Create recovery.conf in data directory
cat > recovery.conf << EOF
restore_command = 'cp /srv/postgres/archivedir/%f %p'
recovery_target_time = '2024-01-15 14:30:00'
EOF
```

## Backup Verification

### Check Backup Integrity

For SQL format backups, verify the file is valid:

```bash
# Test that the compressed file can be decompressed
gunzip -t backup.sql.gz

# View backup contents without restoring
gunzip -c backup.sql.gz | head -50
```

Test restore to a temporary database:

```bash
docker exec postgres16 psql -U your_username -c "CREATE DATABASE test_restore;"
gunzip < backup.sql.gz | docker exec -i postgres16 psql -U your_username -d test_restore
docker exec postgres16 psql -U your_username -d test_restore -c "SELECT COUNT(*) FROM users;"
docker exec postgres16 psql -U your_username -c "DROP DATABASE test_restore;"
```

### Automated Backup Testing

Create a test script:

```bash
#!/bin/bash
# test_backup.sh

BACKUP_DIR="/srv/postgres/backups"
DB_NAME="${POSTGRES_DB:-euem_db}"

# Find the latest backup for this database
LATEST_BACKUP=$(ls -t "$BACKUP_DIR/backup_${DB_NAME}_"*.sql.gz 2>/dev/null | head -1)

if [ -z "$LATEST_BACKUP" ]; then
    echo "ERROR: No backups found for $DB_NAME" >&2
    exit 1
fi

TEST_DB="test_restore_$(date +%Y%m%d)"

# Extract and restore
gunzip < "$LATEST_BACKUP" | docker exec -i postgres16 psql -U your_username -c "CREATE DATABASE $TEST_DB;"
gunzip < "$LATEST_BACKUP" | docker exec -i postgres16 psql -U your_username -d "$TEST_DB"

# Verify data
ROW_COUNT=$(docker exec postgres16 psql -U your_username -d "$TEST_DB" -t -c "SELECT COUNT(*) FROM users;")
echo "Users count: $ROW_COUNT"

# Cleanup
docker exec postgres16 psql -U your_username -c "DROP DATABASE $TEST_DB;"
echo "Test completed successfully"
```

## Offsite Backup Storage

### S3 Integration

Upload backups to AWS S3:

```bash
#!/bin/bash
# backup_to_s3.sh

BACKUP_DIR="/srv/postgres/backups"
DB_NAME="${POSTGRES_DB:-euem_db}"

# Find the latest backup
LATEST_BACKUP=$(ls -t "$BACKUP_DIR/backup_${DB_NAME}_"*.sql.gz 2>/dev/null | head -1)

if [ -z "$LATEST_BACKUP" ]; then
    echo "ERROR: No backups found" >&2
    exit 1
fi

# Upload to S3
aws s3 cp "$LATEST_BACKUP" s3://your-backup-bucket/postgres/
echo "Uploaded $LATEST_BACKUP to S3"
```

### Remote Server Copy

Copy backups to remote server:

```bash
# Using scp with wildcards
scp /srv/postgres/backups/backup_euem_db_*.sql.gz user@remote-server:/path/to/backups/

# Or copy the latest backup
LATEST=$(ls -t /srv/postgres/backups/backup_euem_db_*.sql.gz | head -1)
scp "$LATEST" user@remote-server:/path/to/backups/
```

Or use rsync:

```bash
rsync -avz /srv/postgres/backups/ user@remote-server:/backups/postgres/
```

## Retention Policy

Recommended retention schedule:

- **Daily backups**: Keep for 7 days
- **Weekly backups**: Keep for 4 weeks
- **Monthly backups**: Keep for 12 months
- **Yearly backups**: Keep indefinitely

Implement with cleanup script:

```bash
#!/bin/bash
# cleanup_old_backups.sh

BACKUP_DIR="/srv/postgres/backups"
DB_NAME="${POSTGRES_DB:-euem_db}"

# Remove daily backups older than 7 days
find "$BACKUP_DIR" -type f -name "backup_${DB_NAME}_*.sql.gz" -mtime +7 -delete

# Keep monthly backup on the 1st
if [ "$(date +%d)" == "01" ]; then
    mkdir -p "$BACKUP_DIR/monthly"
    cp "$BACKUP_DIR/backup_${DB_NAME}_$(date +%Y%m%d)_*.sql.gz" "$BACKUP_DIR/monthly/" 2>/dev/null || true
fi
```

## Monitoring

### Backup Status Monitoring

Track backup success/failure:

```bash
# Add to backup script
if [ $? -eq 0 ]; then
    echo "$(date): Backup successful" >> /var/log/backup_status.log
else
    echo "$(date): Backup FAILED" >> /var/log/backup_status.log
    # Send alert email
    echo "Database backup failed!" | mail -s "Backup Alert" admin@example.com
fi
```

### Disk Space Monitoring

Monitor backup storage:

```bash
df -h /srv/postgres/backups
```

Alert when disk usage exceeds 80%:

```bash
USAGE=$(df /srv/postgres/backups | tail -1 | awk '{print $5}' | sed 's/%//')
if [ "$USAGE" -gt 80 ]; then
    echo "Backup storage at ${USAGE}% capacity!" | mail -s "Storage Alert" admin@example.com
fi
```

## Disaster Recovery Planning

### Recovery Time Objective (RTO)

Define how quickly the system must recover. Based on your RTO:

- **RTO < 1 hour**: Implement continuous archiving and standby replication
- **RTO < 4 hours**: Daily backups with WAL archiving
- **RTO < 24 hours**: Regular daily backups sufficient

### Recovery Point Objective (RPO)

Define maximum acceptable data loss. Based on your RPO:

- **RPO < 1 hour**: Continuous replication or hourly backups
- **RPO < 24 hours**: Daily backups
- **RPO > 24 hours**: Weekly backups may suffice

## Resources

- PostgreSQL Backup Documentation: https://www.postgresql.org/docs/current/backup.html
- pg_dump Documentation: https://www.postgresql.org/docs/current/app-pgdump.html


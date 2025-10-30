# Troubleshooting Guide

Common issues and solutions for the EUEM PostgreSQL database setup.

## Connection Issues

### Cannot Connect to Database

**Symptom**: Connection refused or timeout errors when connecting to the database.

**Diagnosis**:

```bash
# Check if container is running
docker ps | grep postgres16

# Check container logs
docker logs postgres16

# Test connection from host
psql -h localhost -p 5432 -U your_username -d euem_db
```

**Solutions**:

1. **Container not running**: Start the container
   ```bash
   docker compose up -d
   ```

2. **Wrong port**: Verify port mapping in `docker-compose.yml`
   ```bash
   docker port postgres16
   ```

3. **Firewall blocking**: Check firewall rules
   ```bash
   sudo ufw status
   ```

4. **Authentication error**: Verify credentials in `.env` file
   ```bash
   docker exec postgres16 psql -U postgres -c "\du"
   ```

### Authentication Failed

**Symptom**: `password authentication failed for user` error.

**Diagnosis**:

```bash
# Check environment variables
docker exec postgres16 env | grep POSTGRES

# View pg_hba.conf
docker exec postgres16 cat /var/lib/postgresql/data/pg_hba.conf
```

**Solutions**:

1. **Reset password**: Connect as postgres user
   ```bash
   docker exec -it postgres16 psql -U postgres
   ```
   ```sql
   ALTER USER your_username WITH PASSWORD 'new_password';
   ```

2. **Update .env file**: Ensure `.env` has correct password
   ```bash
   # Restart container to pick up changes
   docker compose down && docker compose up -d
   ```

3. **Check pg_hba.conf**: Ensure correct authentication method
   ```
   local   all   all   scram-sha-256
   host    all   all   0.0.0.0/0   scram-sha-256
   ```

## Performance Issues

### Slow Queries

**Symptom**: Queries taking longer than expected to execute.

**Diagnosis**:

```sql
-- Enable query logging
SET log_statement = 'all';
SET log_min_duration_statement = 1000;  -- Log queries > 1 second

-- Check slow queries
SELECT pid, usename, query, query_start, state
FROM pg_stat_activity
WHERE state = 'active' AND query NOT LIKE '%pg_stat_activity%';
```

**Solutions**:

1. **Add indexes**: Check for missing indexes
   ```sql
   EXPLAIN ANALYZE SELECT * FROM users WHERE email = 'test@example.com';
   ```

2. **Update statistics**:
   ```sql
   ANALYZE;
   ```

3. **Vacuum database**: Reclaim space and update statistics
   ```sql
   VACUUM ANALYZE;
   ```

### High Memory Usage

**Symptom**: Container using excessive memory or OOM errors.

**Diagnosis**:

```bash
# Check container resource usage
docker stats postgres16

# Check PostgreSQL memory settings
docker exec postgres16 psql -U postgres -c "SHOW shared_buffers;"
docker exec postgres16 psql -U postgres -c "SHOW work_mem;"
```

**Solutions**:

1. **Adjust shared_buffers**: Modify in `docker-compose.yml`
   ```yaml
   command:
     - -c
     - shared_buffers=256MB  # Increase if server has more RAM
   ```

2. **Reduce work_mem**: For systems with limited RAM
   ```yaml
   command:
     - -c
     - work_mem=4MB
   ```

3. **Add memory limits**: Limit container memory usage
   ```yaml
   deploy:
     resources:
       limits:
         memory: 512M
   ```

### Connection Exhaustion

**Symptom**: `FATAL: remaining connection slots are reserved` error.

**Diagnosis**:

```sql
-- Check current connections
SELECT count(*) FROM pg_stat_activity;

-- Check max connections
SHOW max_connections;
```

**Solutions**:

1. **Kill idle connections**:
   ```sql
   SELECT pg_terminate_backend(pid)
   FROM pg_stat_activity
   WHERE state = 'idle' AND datname = 'euem_db';
   ```

2. **Increase max_connections**: In `docker-compose.yml`
   ```yaml
   command:
     - -c
     - max_connections=100
   ```

3. **Use connection pooling**: Configure pgBouncer or similar

## Data Issues

### Missing Tables

**Symptom**: Tables not found when querying.

**Diagnosis**:

```sql
-- List all tables
\dt

-- Check schema
SELECT table_name FROM information_schema.tables WHERE table_schema = 'public';
```

**Solutions**:

1. **Initialize database**: Run initialization scripts
   ```bash
   docker exec -i postgres16 psql -U your_username -d euem_db < init/01-init.sql
   ```

2. **Check schema**: Ensure connected to correct database
   ```sql
   SELECT current_database();
   ```

### Data Corruption

**Symptom**: Unexpected errors reading data or checksum failures.

**Diagnosis**:

```sql
-- Check for corruption
SELECT * FROM users WHERE false;
VACUUM VERBOSE;
```

**Solutions**:

1. **Restore from backup**: Use latest known-good backup
   ```bash
   # See backup.md for restore procedures
   ```

2. **Recover corrupted table**:
   ```sql
   -- Create table backup
   CREATE TABLE users_backup AS SELECT * FROM users;
   
   -- Drop corrupted table
   DROP TABLE users CASCADE;
   
   -- Restore from backup
   CREATE TABLE users AS SELECT * FROM users_backup;
   ```

3. **Enable data checksums**: Add to initialization
   ```env
   POSTGRES_INITDB_ARGS=--data-checksums
   ```

## Container Issues

### Container Won't Start

**Symptom**: Container exits immediately or fails to start.

**Diagnosis**:

```bash
# Check logs
docker logs postgres16

# Check exit code
docker inspect postgres16 | grep ExitCode

# Try starting manually
docker run --rm postgres:16-alpine psql --version
```

**Solutions**:

1. **Volume permission issues**:
   ```bash
   sudo chown -R 999:999 /srv/postgres/data
   ```

2. **Port already in use**:
   ```bash
   # Find process using port 5432
   sudo lsof -i :5432
   
   # Kill process or change port
   sudo kill -9 <PID>
   ```

3. **Corrupted data directory**: Remove and recreate
   ```bash
   # WARNING: This deletes all data
   sudo rm -rf /srv/postgres/data
   docker compose up -d
   ```

### Container Running Out of Space

**Symptom**: `No space left on device` errors.

**Diagnosis**:

```bash
# Check disk usage
df -h

# Check data directory size
du -sh /srv/postgres/data

# Check PostgreSQL database sizes
docker exec postgres16 psql -U your_username -d euem_db -c "
SELECT pg_database.datname, pg_size_pretty(pg_database_size(pg_database.datname)) AS size
FROM pg_database ORDER BY pg_database_size(pg_database.datname) DESC;
"
```

**Solutions**:

1. **Clean up WAL files**:
   ```bash
   docker exec postgres16 psql -U postgres -c "SELECT pg_switch_wal();"
   ```

2. **Vacuum full**: Reclaim space (requires exclusive lock)
   ```sql
   VACUUM FULL;
   ```

3. **Delete old backups**:
   ```bash
   find /srv/postgres/backups -name "*.gz" -mtime +30 -delete
   ```

4. **Increase disk space**: Add storage or expand volume

### Permission Denied Errors

**Symptom**: `permission denied` when accessing files.

**Diagnosis**:

```bash
# Check directory permissions
ls -la /srv/postgres/data

# Check running user
docker exec postgres16 whoami
```

**Solutions**:

1. **Fix ownership**:
   ```bash
   sudo chown -R 999:999 /srv/postgres/data
   sudo chown -R 999:999 /srv/postgres/pg-init
   ```

2. **Fix permissions**:
   ```bash
   sudo chmod 700 /srv/postgres/data
   sudo chmod 755 /srv/postgres/pg-init
   ```

## Schema Issues

### Extension Not Found

**Symptom**: `extension "pgcrypto" does not exist` error.

**Solutions**:

```sql
-- Create extension manually
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS citext;
```

### Enum Type Already Exists

**Symptom**: `type verification_token_type already exists` error.

**Solutions**:

```sql
-- Drop and recreate
DROP TYPE IF EXISTS verification_token_type CASCADE;
CREATE TYPE verification_token_type AS ENUM (
  'EMAIL_VERIFICATION', 'PASSWORD_RESET', 'EMAIL_CHANGE'
);
```

### Constraint Violations

**Symptom**: Unique constraint or foreign key violations.

**Diagnosis**:

```sql
-- Check for duplicate emails
SELECT email, COUNT(*) FROM users GROUP BY email HAVING COUNT(*) > 1;

-- Check orphaned records
SELECT * FROM verification_tokens vt
WHERE NOT EXISTS (SELECT 1 FROM users u WHERE u.id = vt.user_id);
```

**Solutions**:

1. **Remove duplicates**:
   ```sql
   DELETE FROM users WHERE id NOT IN (
     SELECT MIN(id) FROM users GROUP BY email
   );
   ```

2. **Fix orphaned records**:
   ```sql
   DELETE FROM verification_tokens
   WHERE NOT EXISTS (SELECT 1 FROM users WHERE id = verification_tokens.user_id);
   ```

## Logging and Debugging

### Enable Verbose Logging

```yaml
# In docker-compose.yml
environment:
  - POSTGRES_LOG_STATEMENT=all
  - POSTGRES_LOG_CONNECTIONS=on
```

### View Real-time Logs

```bash
# Follow container logs
docker logs -f postgres16

# Filter for specific errors
docker logs postgres16 2>&1 | grep ERROR

# Export logs to file
docker logs postgres16 > postgres.log 2>&1
```

### Debug Query Performance

```sql
-- Enable query timing
\timing

-- Explain query plan
EXPLAIN ANALYZE SELECT * FROM users WHERE email = 'test@example.com';

-- Check index usage
SELECT schemaname, tablename, indexname, idx_scan
FROM pg_stat_user_indexes
WHERE schemaname = 'public';
```

## Getting Help

### Information to Collect

When reporting issues, include:

1. **Docker version**:
   ```bash
   docker --version
   docker compose version
   ```

2. **Container info**:
   ```bash
   docker inspect postgres16 | cat
   ```

3. **PostgreSQL version**:
   ```bash
   docker exec postgres16 psql --version
   ```

4. **Recent logs**:
   ```bash
   docker logs postgres16 --tail 100
   ```

5. **System information**:
   ```bash
   uname -a
   df -h
   free -h
   ```

### Useful Commands Reference

```bash
# Container management
docker compose ps
docker compose logs db
docker compose restart db
docker compose down && docker compose up -d

# Database access
docker exec -it postgres16 psql -U your_username -d euem_db
docker exec postgres16 psql -U your_username -d euem_db -c "SELECT version();"

# Maintenance
docker exec postgres16 psql -U your_username -d euem_db -c "VACUUM ANALYZE;"
docker exec postgres16 pg_dump -U your_username -d euem_db

# Monitoring
docker stats postgres16
docker exec postgres16 psql -U your_username -d euem_db -c "
SELECT pid, usename, application_name, state, query
FROM pg_stat_activity
WHERE datname = 'euem_db';
"
```

## Resources

- PostgreSQL Troubleshooting: https://www.postgresql.org/docs/current/runtime-config-logging.html
- Docker Troubleshooting: https://docs.docker.com/engine/troubleshooting/
- PostgreSQL Wiki: https://wiki.postgresql.org/wiki/Troubleshooting


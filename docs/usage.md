# Usage Guide

This guide covers how to use the EUEM PostgreSQL database, from initial setup to day-to-day operations.

## Prerequisites

- Docker and Docker Compose installed
- PostgreSQL client tools (optional, for direct database access)
- A `.env` file with required configuration

## Initial Setup

### Environment Configuration

Create a `.env` file in the project root with the following variables:

```env
POSTGRES_DB=euem_db
POSTGRES_USER=your_username
POSTGRES_PASSWORD=your_secure_password
ALLOWED_CLIENT=*
```

**Important**: Replace placeholder values with secure credentials. Never commit the `.env` file to version control.

### Starting the Database

To start the PostgreSQL container:

```bash
docker compose up -d
```

This will:
- Pull the PostgreSQL 16 Alpine image if not already present
- Create and start the `postgres16` container
- Execute initialization scripts from `/srv/postgres/pg-init`
- Make the database available on port 5432

### Verifying Installation

Check that the container is running:

```bash
docker compose ps
```

Or using the Docker CLI:

```bash
docker ps | grep postgres16
```

## Database Access

### Command Line Access

To access the PostgreSQL command line inside the container:

```bash
docker exec -it postgres16 psql -U your_username -d euem_db
```

From the host system (requires PostgreSQL client installed):

```bash
psql -h localhost -p 5432 -U your_username -d euem_db
```

### Common SQL Queries

List all tables:

```sql
\dt
```

View table structure:

```sql
\d users
```

View all users:

```sql
SELECT id, email, first_name, last_name, is_verified, is_enabled, created_at
FROM users;
```

View user roles:

```sql
SELECT u.email, r.name AS role
FROM users u
JOIN user_roles ur ON u.id = ur.user_id
JOIN roles r ON ur.role_id = r.id;
```

Check active verification tokens:

```sql
SELECT id, user_id, type, otp_code, expiry_time
FROM verification_tokens
WHERE expiry_time > now();
```

### Connection Pool Settings

The database is configured with the following limits:

- **max_connections**: 50
- **shared_buffers**: 128MB

These settings are appropriate for small to medium workloads. Adjust them in `docker-compose.yml` if needed.

## Application Integration

### Spring Boot Configuration

Connect your Spring Boot application using these settings:

```yaml
spring:
  datasource:
    url: jdbc:postgresql://localhost:5432/euem_db
    username: your_username
    password: your_secure_password
  jpa:
    hibernate:
      ddl-auto: update  # Use 'validate' in production
    properties:
      hibernate:
        dialect: org.hibernate.dialect.PostgreSQLDialect
```

### Database Schema

The database uses the following schema:

**Tables**:
- `users`: User accounts with authentication credentials
- `roles`: Role definitions (USER, ADMIN)
- `user_roles`: Many-to-many relationship between users and roles
- `verification_tokens`: OTP codes for email verification and password resets

**Features**:
- UUID primary keys generated via `gen_random_uuid()`
- Case-insensitive email fields using `CITEXT`
- Automatic `updated_at` timestamps via triggers
- Referential integrity with CASCADE deletes
- Indexed columns for optimal query performance

## Container Management

### Viewing Logs

View database logs in real-time:

```bash
docker compose logs -f db
```

Or using Docker CLI:

```bash
docker logs -f postgres16
```

### Stopping the Database

Stop the container:

```bash
docker compose down
```

**Warning**: This will stop the container but preserve data stored in volumes.

To stop and remove volumes (deletes all data):

```bash
docker compose down -v
```

### Restarting the Database

Restart the container:

```bash
docker compose restart db
```

### Reloading Configuration

Reload PostgreSQL configuration without restarting:

```bash
docker exec -it postgres16 sh -lc 'psql -U postgres -c "select pg_reload_conf();"'
```

## Maintenance Operations

### Database Health Check

Run a health check query:

```bash
docker exec postgres16 psql -U your_username -d euem_db -c "SELECT version();"
```

### Vacuum and Analyze

Optimize the database (run during low-traffic periods):

```bash
docker exec postgres16 psql -U your_username -d euem_db -c "VACUUM ANALYZE;"
```

### Clean Up Expired Tokens

Manually remove expired verification tokens:

```sql
DELETE FROM verification_tokens WHERE expiry_time < now();
```

Consider setting up a scheduled job for this operation.

## Performance Considerations

### Monitoring Query Performance

Enable query logging in `pg_hba.conf` or via:

```sql
ALTER DATABASE euem_db SET log_statement = 'all';
```

### Index Usage

Check index usage statistics:

```sql
SELECT schemaname, tablename, indexname, idx_scan, idx_tup_read, idx_tup_fetch
FROM pg_stat_user_indexes
ORDER BY idx_scan DESC;
```

### Connection Monitoring

View active connections:

```sql
SELECT pid, usename, application_name, client_addr, state
FROM pg_stat_activity
WHERE datname = 'euem_db';
```

## Troubleshooting

For common issues and solutions, see `troubleshooting.md`.

## Additional Resources

- PostgreSQL Official Documentation: https://www.postgresql.org/docs/
- Docker Compose Documentation: https://docs.docker.com/compose/
- Spring Boot Data JPA Guide: https://spring.io/guides/gs/accessing-data-jpa/


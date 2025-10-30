# Security Guide

This document outlines security best practices and configuration for the EUEM PostgreSQL database.

## Overview

The database stores sensitive user information including authentication credentials, email addresses, and authorization data. Proper security measures are essential to protect this data.

**Security Architecture**: This database is configured for **local-only access** - connections are only accepted from the same host (localhost). This security model eliminates the risk of network-based attacks and simplifies security management by removing the need for SSL/TLS encryption and complex firewall rules.

## Authentication

### Database Authentication

PostgreSQL is configured to use SCRAM-SHA-256 password authentication by default. This provides secure password hashing and prevents transmission of plaintext passwords.

### Password Requirements

Enforce strong passwords for database users:

- Minimum 12 characters
- Mix of uppercase, lowercase, numbers, and special characters
- Avoid dictionary words and common patterns
- Rotate passwords regularly (recommend every 90 days)

### Environment Variables

**Never** store credentials in code or commit them to version control. Always use environment variables:

```env
POSTGRES_USER=secure_username
POSTGRES_PASSWORD=complex_password_here
```

Ensure the `.env` file has restricted permissions:

```bash
chmod 600 .env
```

## Network Security

### Local-Only Access

**Security Model**: The database is configured to accept connections only from the same host (localhost). No remote TCP/IP connections are permitted, which eliminates the need for SSL/TLS encryption for database connections.

**Important**: Ensure your `docker-compose.yml` binds the PostgreSQL port to localhost only (see Container Port Mapping below). The database itself listens on all interfaces within the container, but the Docker port mapping should restrict access to localhost.

### Firewall Configuration

Even though only localhost connections are allowed, it's still good practice to configure a firewall:

**Linux firewall example**:

```bash
# Default: deny all incoming connections except established sessions
sudo ufw default deny incoming
sudo ufw default allow outgoing

# The database port should not be accessible from outside
# No explicit rule needed since we only allow localhost connections
```

**macOS**: System Preferences > Security & Privacy > Firewall

**Windows**: Windows Defender Firewall

### Access Control Lists

The default PostgreSQL configuration already restricts access to local connections. Verify `pg_hba.conf`:

```
# Only allow local (Unix socket) connections
local   all     all     scram-sha-256

# Only allow localhost TCP connections
host    all     all     127.0.0.1/32    scram-sha-256
host    all     all     ::1/128         scram-sha-256
```

To view the current configuration:

```bash
docker exec postgres16 cat /var/lib/postgresql/data/pg_hba.conf
```

If modifications are needed:

```bash
docker exec -it postgres16 vi /var/lib/postgresql/data/pg_hba.conf
docker exec postgres16 sh -lc 'psql -U postgres -c "select pg_reload_conf();"'
```

### Container Port Mapping

The `docker-compose.yml` maps port 5432 to allow host access, but the host should only be accessible locally:

```yaml
ports:
  - "127.0.0.1:5432:5432"  # Only bind to localhost, not all interfaces
```

If your docker-compose.yml currently has `"5432:5432"`, change it to `"127.0.0.1:5432:5432"` to prevent external access.

## Data Protection

### Password Storage

**Critical**: Never store plaintext passwords in the database. The `users.password` field should contain only hashed values.

**Recommended hashing**:
- Use bcrypt with cost factor 12 or higher
- Or Argon2 for modern applications
- Implement salting (most libraries do this automatically)

### Encryption at Rest

For production environments, enable encryption at the volume level:

**Docker volume encryption**:

```bash
# Use encrypted Docker volumes
docker volume create --driver local \
  --opt type=tmpfs \
  --opt device=tmpfs \
  --opt o=encryption=1 \
  postgres_data
```

**Filesystem encryption**:

Encrypt the data directory on the host:

```bash
# Example: encrypt the data mount point
sudo cryptsetup luksFormat /srv/postgres/data
```

**Note**: Since only localhost connections are allowed, encryption in transit (SSL/TLS) is not required for database connections. However, if your application communicates with external services over untrusted networks, ensure those connections use HTTPS/TLS.

## Access Control

### Role-Based Access

The database implements role-based access control (RBAC):

**Standard roles**:
- `USER`: Basic application user privileges
- `ADMIN`: Administrative privileges

Grant roles appropriately:

```sql
-- Grant user role
INSERT INTO user_roles (user_id, role_id)
SELECT u.id, r.id
FROM users u, roles r
WHERE u.email = 'user@example.com' AND r.name = 'USER';

-- Grant admin role
INSERT INTO user_roles (user_id, role_id)
SELECT u.id, r.id
FROM users u, roles r
WHERE u.email = 'admin@example.com' AND r.name = 'ADMIN';
```

### User Permissions

Limit database user permissions:

```sql
-- Create a read-only user for reporting
CREATE USER reporting_user WITH PASSWORD 'secure_password';
GRANT CONNECT ON DATABASE euem_db TO reporting_user;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO reporting_user;

-- Create an application user with limited privileges
CREATE USER app_user WITH PASSWORD 'secure_password';
GRANT CONNECT ON DATABASE euem_db TO app_user;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA public TO app_user;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO app_user;
```

### Principle of Least Privilege

Follow the principle of least privilege: grant only the minimum permissions required for each role.

## Secure Configuration

### Docker Security

Run containers as non-root users:

```yaml
services:
  db:
    user: "999:999"  # postgres user UID/GID
```

Restrict container capabilities:

```yaml
cap_drop:
  - ALL
cap_add:
  - CHOWN
  - DAC_OVERRIDE
  - FOWNER
  - SETGID
  - SETUID
```

### PostgreSQL Configuration

Enable audit logging:

```yaml
command:
  - -c
  - log_statement=all  # Log all statements
  - -c
  - log_connections=on
  - -c
  - log_disconnections=on
  - -c
  - log_line_prefix='%t [%p]: [%l-1] user=%u,db=%d,app=%a,client=%h '
```

Disable unnecessary features:

```sql
-- Remove unused extensions
DROP EXTENSION IF EXISTS plpythonu;
DROP EXTENSION IF EXISTS plperlu;
```

## Monitoring and Auditing

### Connection Logging

Monitor database connections:

```sql
SELECT datname, usename, application_name, client_addr, state, query_start, state_change
FROM pg_stat_activity
WHERE datname = 'euem_db';
```

### Failed Login Attempts

Check for failed authentication attempts:

```bash
docker logs postgres16 | grep "authentication failed"
```

Set up log monitoring and alerting for repeated failures.

### Data Access Auditing

Log sensitive data access:

```sql
-- Create audit log table
CREATE TABLE audit_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id),
    action VARCHAR(50),
    table_name VARCHAR(100),
    record_id UUID,
    timestamp TIMESTAMPTZ DEFAULT now()
);
```

## Incident Response

### Security Breach Checklist

If a security breach is suspected:

1. **Isolate**: Immediately stop the affected containers
2. **Assess**: Determine the scope of the breach
3. **Notify**: Inform security team and stakeholders
4. **Document**: Preserve logs and evidence
5. **Remediate**: Reset passwords, revoke tokens, close vulnerabilities
6. **Restore**: Restore from known-good backup
7. **Monitor**: Increase monitoring for suspicious activity

### Emergency Procedures

**Rotate all passwords**:

```bash
# Generate new password
openssl rand -base64 32

# Update .env file
# Restart container
docker compose restart db
```

**Disable compromised user**:

```sql
UPDATE users SET is_enabled = FALSE WHERE email = 'compromised@example.com';
```

**Revoke all tokens**:

```sql
DELETE FROM verification_tokens WHERE user_id = 'user-uuid-here';
```

## Compliance

### Data Privacy

Ensure compliance with applicable privacy regulations (GDPR, CCPA, etc.):

- Implement data retention policies
- Provide data export capabilities
- Enable data deletion ("right to be forgotten")
- Document data processing activities

### Regular Audits

Conduct regular security audits:

- Quarterly review of user accounts and permissions
- Monthly review of failed login attempts
- Annual penetration testing
- Continuous monitoring of security advisories

## Resources

- PostgreSQL Security: https://www.postgresql.org/docs/current/security.html
- OWASP Database Security: https://owasp.org/www-project-vulnerable-web-applications-directory/
- Docker Security Best Practices: https://docs.docker.com/engine/security/


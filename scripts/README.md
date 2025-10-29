# HAWKI Docker Scripts

This directory contains helper scripts for Docker deployments.

## Available Scripts

### `create-volumes.sh`

Creates external Docker volumes for staging and production environments.

**Usage:**
```bash
./create-volumes.sh [staging|prod]
```

**Volumes Created:**
- **Staging:**
  - `hawki-staging_mysql_data` - MySQL database storage
  - `hawki-staging_redis_data` - Redis cache storage

- **Production:**
  - `hawki-prod_mysql_data` - MySQL database storage
  - `hawki-prod_redis_data` - Redis cache storage

**Note:** This script is automatically called by `deploy-staging.sh` and `deploy-prod.sh` during the first deployment. Subsequent deployments will skip volume creation if they already exist.

## Manual Volume Management

To manually list volumes:
```bash
docker volume ls | grep hawki
```

To manually remove volumes (⚠️ destroys all data):
```bash
docker volume rm hawki-staging_mysql_data
docker volume rm hawki-staging_redis_data
```

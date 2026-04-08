# How to Switch Between Databases

## Current State (as of 2026-04-05)

The production database with all imported data (958 customers, 964 tickets, 854 invoices) has been renamed to a backup. A fresh empty database was created for testing the first-time setup flow.

## File Locations

```
packages/server/data/
  bizarre-crm.db                    ← Current ACTIVE database (fresh/empty)
  bizarre-crm-backup-20260405.db    ← BACKUP with all imported data
```

## To Restore the Old Database (with all data)

```bash
# 1. Stop the server
# (Ctrl+C in terminal, or kill the process)

# 2. Go to the data directory
cd "C:\Users\Pavel\MY OWN CRM\bizarre-crm\packages\server\data"

# 3. Rename the current (fresh) DB out of the way
mv bizarre-crm.db bizarre-crm-fresh.db
mv bizarre-crm.db-wal bizarre-crm-fresh.db-wal 2>/dev/null
mv bizarre-crm.db-shm bizarre-crm-fresh.db-shm 2>/dev/null

# 4. Restore the backup
mv bizarre-crm-backup-20260405.db bizarre-crm.db
mv bizarre-crm-backup-20260405.db-wal bizarre-crm.db-wal 2>/dev/null
mv bizarre-crm-backup-20260405.db-shm bizarre-crm.db-shm 2>/dev/null

# 5. Start the server
cd "C:\Users\Pavel\MY OWN CRM\bizarre-crm\packages\server"
npx tsx src/index.ts
```

## To Switch Back to the Fresh Database

```bash
# 1. Stop the server

# 2. Go to the data directory
cd "C:\Users\Pavel\MY OWN CRM\bizarre-crm\packages\server\data"

# 3. Swap them
mv bizarre-crm.db bizarre-crm-backup-20260405.db
mv bizarre-crm-fresh.db bizarre-crm.db

# 4. Start the server
cd "C:\Users\Pavel\MY OWN CRM\bizarre-crm\packages\server"
npx tsx src/index.ts
```

## To Start Completely Fresh (delete everything)

```bash
# 1. Stop the server

# 2. Delete the active DB (keeps backups)
cd "C:\Users\Pavel\MY OWN CRM\bizarre-crm\packages\server\data"
rm bizarre-crm.db bizarre-crm.db-wal bizarre-crm.db-shm 2>/dev/null

# 3. Start the server — it will auto-create a new DB with:
#    - All 43 migrations applied
#    - Default statuses, tax classes, payment methods
#    - 235 device models seeded
#    - Default admin user (username: admin, password: admin123, password_set: 0)
#    - First login will prompt to set password + setup 2FA
cd "C:\Users\Pavel\MY OWN CRM\bizarre-crm\packages\server"
npx tsx src/index.ts
```

## Default Credentials (Fresh Database)

- **Username:** `admin`
- **Temporary Password:** `admin123`
- **PIN:** `1234`
- On first login: prompted to set a new password, then set up 2FA (Google Authenticator)

## PowerShell Equivalents (if using PowerShell instead of Git Bash)

```powershell
# Restore backup
cd "C:\Users\Pavel\MY OWN CRM\bizarre-crm\packages\server\data"
Rename-Item bizarre-crm.db bizarre-crm-fresh.db
Rename-Item bizarre-crm-backup-20260405.db bizarre-crm.db

# Switch to fresh
Rename-Item bizarre-crm.db bizarre-crm-backup-20260405.db
Rename-Item bizarre-crm-fresh.db bizarre-crm.db
```

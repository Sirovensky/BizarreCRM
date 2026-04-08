# Bizarre CRM Scripts

## Production Setup

### 1. Fresh Start (new server)
```bash
./scripts/reset-database.sh          # Delete everything, start clean
cd packages/server && npx tsx src/index.ts  # Start server (creates fresh DB with seed data)
./scripts/import-repairdesk.sh        # Import all RepairDesk data
```

### 2. Re-import (clear old imports, re-import fresh)
```bash
# Stop the server first!
./scripts/clear-imported-data.sh      # Remove all imported data (keeps manual entries)
# Start server
./scripts/import-repairdesk.sh        # Re-import everything
```

### 3. Import specific entities only
```bash
./scripts/clear-imported-data.sh tickets    # Clear only imported tickets
./scripts/clear-imported-data.sh invoices   # Clear only imported invoices
./scripts/clear-imported-data.sh customers  # Clear only imported customers
```

## Environment Variables (.env)

```env
# RepairDesk API (Bearer token auth)
RD_API_KEY=your-repairdesk-api-key-here

# Server
PORT=3020
JWT_SECRET=your-secure-secret-here

# SMS Provider (console | twilio | telnyx)
SMS_PROVIDER=console
TWILIO_ACCOUNT_SID=
TWILIO_AUTH_TOKEN=
TWILIO_FROM_NUMBER=
TELNYX_API_KEY=
TELNYX_FROM_NUMBER=
```

## Default Login
- Username: `admin`
- Password: `admin123`
- **Change this in production!**

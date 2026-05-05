# Play Store — Data Safety Form (§33.7 / §32.10)

Fill this in the Play Console under "Data safety" before each release.
Update if new data types are collected or shared.

## Does your app collect or share any of the required user data types?
Yes

## Data types collected

| Category         | Data type            | How used                                              | Required? | Encrypted? | User can delete? |
|------------------|----------------------|-------------------------------------------------------|-----------|------------|------------------|
| App activity     | App interactions     | Repair-shop workflow (tickets, invoices, customers)   | Yes       | In transit | Yes              |
| App activity     | In-app search history| Recent customer / ticket search — stored locally only | No        | At rest    | Yes              |
| Device or other  | Crash logs           | Sent to tenant server (user's own chosen URL)         | No        | In transit | Yes              |
| Personal info    | Name                 | Customer records synced to tenant server              | Yes       | In transit | Yes              |
| Personal info    | Email address        | Customer records synced to tenant server              | Yes       | In transit | Yes              |
| Personal info    | Phone number         | Customer records synced to tenant server              | Yes       | In transit | Yes              |
| Financial info   | Payment info         | Processed via BlockChyp terminal — NOT stored in app  | Yes       | In transit | N/A              |

## Is any of the data shared with third parties?
No — all data is sent exclusively to the tenant's own CRM server at the URL
the user configures during setup. No data is shared with Bizarre Electronics
or any other third party.

## Is all of the data encrypted in transit?
Yes — TLS (HTTPS) for all API calls.

## Does your app provide a way for users to request data deletion?
Yes — Settings → Account → Delete account / Export data.

## Notes
- The app does NOT use Firebase Analytics, Crashlytics, or any third-party
  analytics SDK. The only Firebase module is firebase-messaging (FCM push).
- SQLCipher encrypts the local Room database at rest with a per-install key.
- Crash logs are breadcrumbs stored in the app's local filesDir and shared
  to the tenant server only on explicit user action (Settings → Send report).

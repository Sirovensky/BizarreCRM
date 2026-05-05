# Android Field App

The Android app is the mobile and bench companion for BizarreCRM. It is a native Kotlin and Jetpack Compose app, not a web wrapper.

## Current Foundations

The app includes:

- token-based login,
- optional biometric quick-unlock,
- encrypted preferences,
- Room local storage with SQLCipher,
- Retrofit API clients,
- WorkManager sync jobs,
- Firebase Messaging,
- CameraX dependencies,
- ML Kit barcode scanning dependencies,
- Material 3 UI,
- Hilt dependency injection,
- dashboard and route structure for shop workflows.

## Covered Areas

Android routes and screens exist for many core areas:

- dashboard,
- tickets,
- customers,
- inventory,
- invoices,
- SMS,
- reports,
- employees,
- leads,
- appointments,
- estimates,
- expenses,
- settings.

The web CRM is still the most complete surface. Android is strongest as a mobile technician and counter companion.

## Mobile Entry Points

The manifest declares:

- deep link support,
- static launcher shortcuts,
- a Quick Settings tile,
- Firebase notification service,
- foreground repair service,
- home-screen widget provider.

Several of those entry points currently need routing polish before they are reliable for daily use.

## Known Workflow Gaps

Active Android gaps are tracked in [TODO.md](../TODO.md).

Current high-impact areas include:

- deep links and shortcuts resolving intents but not always navigating,
- notification taps not always opening the intended screen,
- ticket checkout route/callback gaps,
- ticket-to-invoice conversion wiring,
- ticket photo upload navigation,
- inventory-create routing,
- profile/PIN route access,
- SMS template routing,
- offline temp-ID reconciliation for chained create flows,
- placeholder actions such as Quick Sale, ticket star, and estimate delete.

## Product Direction

The Android app should focus on work that is naturally mobile:

- quick lookup,
- ticket updates,
- bench notes,
- photos,
- barcode scanning,
- customer communication,
- simple payments or payment recording,
- inventory checks,
- technician queues,
- push notifications.

Dense admin, bulk import/export, and complex reporting should stay primarily in the web CRM unless there is a clear mobile use case.

## Developer Notes

When changing Android-facing API behavior:

1. Update the server route.
2. Update web types if the web uses the same endpoint.
3. Update Retrofit interfaces and DTOs.
4. Update Room mapping if local storage is involved.
5. Update the related contract under `packages/contracts`.
6. Add focused tests or manual verification notes for offline and sync behavior.

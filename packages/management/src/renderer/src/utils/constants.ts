// FIXED-by-Fixer-A26 2026-04-25 (DASH-ELEC-055): single source of truth for the
// renderer-side password-min policy. LoginPage previously hard-coded `10`
// across four sites (handleSetup guard, handleSetPassword guard, setup-form
// submit-disable, set-password-form submit-disable). Drift between any of
// those would silently weaken the gate without any test surfacing it.
//
// Keep this in sync with the IPC `SchemaSetup.password.min(10)` /
// `SchemaSetPassword.password.min(10)` in src/main/ipc/management-api.ts and
// the server's super-admin password policy. The shared constant cannot live
// in @bizarre-crm/shared yet (the renderer doesn't depend on it), but consolidating
// the renderer side is the prerequisite step for future extraction.
export const PASSWORD_MIN_LENGTH = 10;

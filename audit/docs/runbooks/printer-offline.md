# Runbook: Printer Offline

**Severity:** P1 — Staff-impacting (workaround exists)
**Expected MTTR:** 5 min
**Last updated:** 2026-04-20

---

## Symptoms

- Receipt printer shows "Offline" in **Settings → Hardware → Printer**.
- Checkout completes but "Printing receipt..." spinner never resolves.
- Error banner: "Printer unavailable — receipt not printed."

---

## Triage and resolution

### Step 1 — Verify physical connection

- **Network printer (Star TSP100IV-LAN, webPRNT):** confirm the printer's Ethernet or Wi-Fi indicator is lit. Power-cycle the printer (off 10 s, back on).
- **Bluetooth printer:** confirm Bluetooth is enabled on the iPad/iPhone. Toggle the printer off and on. Check **Settings → Bluetooth** for the printer entry; if it shows "Not Connected", tap it to reconnect.

### Step 2 — Retry from BizarreCRM

1. **Settings → Hardware → Printer → Test Print**.
2. If the test page prints: the connection is restored. Return to POS.
3. If the test fails: proceed to Step 3.

### Step 3 — Re-pair the printer

1. **Settings → Hardware → Printer → Remove Printer**.
2. Add the printer again: tap "Add Printer" and follow the pairing wizard.
3. For network printers: confirm the printer and the iOS device are on the same LAN segment (not isolated guest Wi-Fi).
4. For Bluetooth printers: ensure no other device is connected to it simultaneously.

---

## Fallback options (use if hardware cannot be restored quickly)

### Fallback A — AirPrint

1. After checkout finalises, tap "Print Receipt" → "Other Options" → "AirPrint".
2. Any AirPrint-compatible printer on the local network is selectable.
3. Scales the receipt template to standard paper sizes.

### Fallback B — Email or SMS PDF receipt

1. After checkout, tap "Send Receipt" → "Email" or "SMS".
2. Enter the customer's email address or phone number.
3. A PDF receipt is generated and sent immediately.
4. No printer required. Customer receives receipt in < 30 s (dependent on server send).

### Fallback C — Disable print requirement temporarily

1. **Settings → POS → Receipt Options → Require Print Before Finalise** — toggle off.
2. Checkout will complete without waiting for a printer acknowledgement.
3. Remember to re-enable this setting once the printer is back online.

---

## Escalation path

| Tier | Who | When |
|---|---|---|
| 1 | Shop manager | Hardware reset, printer re-pairing |
| 2 | IT / network admin | LAN isolation or DHCP issues causing printer invisibility |
| 3 | BizarreCRM support | `https://bizarrecrm.com/support` — if app-level printer driver issue |

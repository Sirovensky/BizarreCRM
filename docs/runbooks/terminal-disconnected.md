# Runbook: Terminal Disconnected

**Severity:** P1 — Staff-impacting (workaround exists)
**Expected MTTR:** 5 min
**Last updated:** 2026-04-20

---

## Symptoms

- BlockChyp payment terminal shows "Disconnected" or "Unavailable" in **Settings → Hardware → Payment Terminal**.
- Tapping "Charge" in POS shows "Terminal not found" error.
- Card tap / swipe / dip does not respond on the physical terminal.

---

## Triage and resolution

### Step 1 — Check physical terminal state

1. Confirm the terminal is powered on and not in sleep mode (tap the screen to wake it).
2. Confirm the terminal is on the same local network as the iOS device (same Wi-Fi SSID or wired LAN).
3. If using Bluetooth pairing: confirm Bluetooth is enabled on the iOS device.

### Step 2 — Retry pairing from BizarreCRM

1. **Settings → Hardware → Payment Terminal → Reconnect**.
2. Wait 15 seconds for the terminal to respond.
3. If reconnection succeeds: return to POS and retry the charge.
4. If reconnection fails: proceed to Step 3.

### Step 3 — Re-pair the terminal

1. **Settings → Hardware → Payment Terminal → Remove Terminal**.
2. On the BlockChyp terminal, navigate to **Settings → Network → Display Connection Info** and note the IP address and pairing code.
3. In BizarreCRM: **Settings → Hardware → Add Terminal**, enter the terminal IP and pairing code.
4. Test with a $0.01 test transaction (void immediately).

---

## Fallback options (use if terminal cannot be restored quickly)

### Fallback A — Manual card entry (keyed in)

1. At POS checkout, tap "Payment Method" → "Manual Card Entry".
2. Staff types the card number, expiry, and CVV.
3. Processed via BlockChyp HTTP API directly from the iOS device (not via terminal).
4. Higher interchange rate and no EMV liability shift — acceptable for one-off emergencies.

### Fallback B — Cash

1. At POS checkout, tap "Payment Method" → "Cash".
2. Enter the tendered amount. The drawer kick is triggered (if drawer is connected and printer is online).
3. Change calculation is shown on-screen.
4. Offline-safe: cash sales are recorded locally immediately.

### Fallback C — Payment link (remote payment)

1. At POS checkout, tap "Payment Method" → "Send Payment Link".
2. Enter the customer's email or phone number.
3. The customer pays via the payment link URL on their own device.
4. Sale completes when the server confirms payment.

---

## Escalation path

| Tier | Who | When |
|---|---|---|
| 1 | Shop manager | Terminal power cycle, re-pairing |
| 2 | IT / network admin | LAN connectivity to terminal |
| 3 | BlockChyp support | If terminal firmware or account issue |
| 4 | BizarreCRM support | `https://bizarrecrm.com/support` |

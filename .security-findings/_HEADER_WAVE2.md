

---

# SECURITY AUDIT — BACKEND — WAVE 2 (edge cases / second-order) — 2026-05-05

User feedback after Wave 1 (S01–S36): "barely deep — try harder." Wave 2 dispatched 30 additional sonnet agents focused on edge cases, second-order bugs, and dimensions Wave 1 under-covered.

**Methodology:** same `.security-findings/.PROTOCOL.md` (≥25–45 min, ≥60+ tool calls per agent). Each agent attacks one specific class of bug.

**Wave-2 slots:**

| Slot | Aspect |
|------|--------|
| T01 | Race conditions / TOCTOU across all SELECT-then-UPDATE patterns |
| T02 | Idempotency completeness matrix across money/state/email/SMS endpoints |
| T03 | Time/date edge cases — TZ drift, DST, epoch precision, future-dated abuse |
| T04 | Numeric edge cases — NaN/Infinity/MAX_SAFE_INTEGER/float drift on cents |
| T05 | Unicode normalization + homoglyph + zero-width + RTL override attacks |
| T06 | HTTP cache + CDN cache + browser cache poisoning |
| T07 | Open redirect / unsafe redirect targets |
| T08 | HTTP smuggling / proxy / raw-body parser ordering / cluster behind LB |
| T09 | JSON path / json_extract injection in better-sqlite3, FTS5 MATCH |
| T10 | DNS rebinding deeper — TOCTOU on resolution, IP pinning, redirect chain |
| T11 | Webhook precision — replay window, clock skew, dedup retention |
| T12 | ReDoS sweep — every regex against user input |
| T13 | Decompression bombs — zip / gzip / image / PDF / JSON / XML / SVG |
| T14 | Email header injection (CRLF) + attachment filename injection |
| T15 | SMTP relay abuse + from-domain spoofing + provider impersonation |
| T16 | Voice IVR / DTMF / TwiML manipulation |
| T17 | Audit log completeness matrix (every privileged op → audit row?) |
| T18 | Migration drift — schema/code mismatches, missing indexes, FK gaps |
| T19 | Resource exhaustion / DoS surface (conn / mem / DB / FD) |
| T20 | Symlink attack sweep beyond archive extraction |
| T21 | SQLite-specific — PRAGMA, ATTACH, recursive CTE DoS, FTS5 quirks |
| T22 | Tier/plan gate bypass + downgrade race + entitlement integrity |
| T23 | Audit-log tampering / append-only enforcement / log injection |
| T24 | Test fixtures / sample data / seed — real-data + dev creds leak |
| T25 | Dependency CVEs / outdated libs / supply-chain risk |
| T26 | Subresource Integrity / CDN script tampering on admin HTML |
| T27 | Long-running tasks / promise leaks / unhandled rejection |
| T28 | WebSocket per-message-type authz matrix + broadcast scoping |
| T29 | Provider/3rd-party API response trust boundary |
| T30 | Chained-exploit / second-order analysis (combines Wave-1 + Wave-2 findings) |

**Cumulative volume:** Wave 1 (~570 KB / 8608 lines, 36 slots) + Wave 2 (~430 KB / 6291 lines, 30 slots) = 66 specialized agents covering 66 distinct classes.

---


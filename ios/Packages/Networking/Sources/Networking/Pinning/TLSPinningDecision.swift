// §1.2 TLS Pinning — Decision record + per-build-config toggle
//
// Decision (2026-04-26):
//
//   ❶  bizarrecrm.com cloud-hosted tenants — pins EMPTY by default.
//      Let's Encrypt rotates certs every 90 days without warning; pinning
//      an intermediate or leaf cert would produce a hard-reject every
//      rotation requiring an app update to clear. Given Let's Encrypt's
//      well-audited CA chain and short cert lifetimes (already a security
//      benefit), OS chain trust is acceptable.
//      Revisit if we need to defend against nation-state MITM on sensitive
//      tenant data; at that point pin to Let's Encrypt's R3 or E1
//      intermediate SPKI with two backup pins and a 30-day remote rotation
//      window in the Server-delivered pin list.
//
//   ❷  Self-hosted tenants — pins remain EMPTY by default (user supplies
//      their own cert; we can't pre-compile their CA). Tenants can optionally
//      supply an SPKI hash via the server's `/auth/me` response extension field
//      `tls_pin_sha256` (base64). When present, `PinningStore` activates it.
//
//   ❸  Debug builds — `failClosed = false` so engineers can inspect TLS
//      traffic with Charles/Proxyman without breaking the build.
//
//   ❹  Release builds — `failClosed = true` whenever any pin is present.
//      Empty-pin-set releases pass through (see ❶ rationale).
//
// To add a custom pin for a specific tenant:
//   1. Extract the leaf SPKI hash:
//      $ openssl s_client -connect your.server.com:443 | openssl x509 -pubkey -noout |
//        openssl pkey -pubin -outform DER | openssl dgst -sha256 -binary | base64
//   2. POST it to `PinningStore.setTenantPolicy(for:policy:)`.
//   3. It survives a cert rotation as long as the key pair doesn't change.

import Foundation

/// Build-config-aware factory for `PinningPolicy`.
///
/// Feature modules and app entry-point should call `PinningPolicyFactory.make()`
/// rather than constructing `PinningPolicy` directly. This centralises the
/// debug-vs-release toggle documented in the §1.2 decision record above.
public enum PinningPolicyFactory {

    /// Returns a `PinningPolicy` appropriate for the current build configuration.
    ///
    /// - `DEBUG` builds: `failClosed = false` (log mismatch, allow connection).
    /// - `RELEASE` builds: `failClosed = true` when pins are present.
    /// - In both cases: `pins` is empty unless explicitly supplied.
    public static func make(pins: Set<Data> = []) -> PinningPolicy {
        #if DEBUG
        return PinningPolicy(
            pins: pins,
            allowBackupIfPinsEmpty: true,
            failClosed: false  // §1.2: dev/staging — log mismatches, don't block
        )
        #else
        return PinningPolicy(
            pins: pins,
            allowBackupIfPinsEmpty: true,
            failClosed: !pins.isEmpty  // §1.2: only fail-closed when pins present
        )
        #endif
    }

    /// Policy for a cloud-hosted bizarrecrm.com tenant with no custom pins.
    /// Equivalent to "trust OS chain" per the §1.2 decision.
    public static let cloudHostedNoPin: PinningPolicy = make()
}

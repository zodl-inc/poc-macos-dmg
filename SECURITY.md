# Security

## Auto-update security model

Every update goes through 6 independent layers before any code runs on the user's machine.

```
GitHub API request
  │  L1: TLS + SPKI pinning (OCSP fallback for legit rotation)
  ▼
Fetch .sha256 + .sha256.sig.b64
  │  L2: Ed25519 signature on the checksum (key never touches GitHub)
  ▼
Download DMG
  │  L3: SHA-256 checksum of the DMG
  │  L4: codesign TeamIdentifier=RLPRR8CPQG
  ▼
Mount DMG
  │  L5: mounted bundle version must match the release tag
  ▼
Install (atomic mv swap) → external helper relaunches
  │  L6: Apple notarization ticket stapled to DMG (Gatekeeper)
  ▼
New version running
```

---

### Layer 1 — TLS + SPKI Pinning with OCSP Fallback

All requests use a custom `URLSessionDelegate` (`PinningDelegate`) that:

1. Performs standard TLS chain validation (macOS SecTrust)
2. Checks whether any certificate in the chain matches a pinned SPKI SHA-256 hash
3. **On pin mismatch**, queries OCSP to distinguish legitimate rotation from MITM:
   - Cert **revoked/expired** → GitHub rotated legitimately → allow via system trust (log a warning to update pins)
   - Cert **still valid** but different key → possible MITM → **block**

Pinned hashes (as of 2026-08-07, Sectigo chain — computed via `scripts/get-spki-hashes.swift` on a macOS runner because `SecKeyCopyExternalRepresentation` output differs from OpenSSL's SPKI encoding):

```
EfXAzYKYsOsdi115+whKa+Yntz0T55fOk7iirLhX7rc=  *.github.com (leaf)
VqePxH3EcFwZuYK3CCOMz5HKMoeIZpZcEyBf4diPGSA=  Sectigo Public Server Authentication CA DV E36
EdsvlytFf4a/O+hCPwBXFFi46RKXqivCAF+mO7s+5Ng=  Sectigo Public Server Authentication Root E46
```

**Why OCSP fallback instead of hard pinning?** Hard pinning bricks all installed apps the moment GitHub rotates keys. The OCSP fallback lets users keep updating through a legitimate rotation while still blocking an attacker presenting a different key while the pinned cert is alive.

**What this prevents:** MITM with a forged or substitute certificate.

---

### Layer 2 — Ed25519 Signature on the Checksum

Every release publishes `HelloWorld-<version>.sha256.sig.b64` — an Ed25519 signature over the `.sha256` file.

- **Private key**: AWS Secrets Manager `/infra/apple/update-signing-key`, only readable by the CI OIDC role
- **Public key**: hardcoded in `Updater.swift` (protected by code signing + notarization of the app itself)
- Signing happens in CI (`scripts/sign-checksum.py`) **after** notarization, since stapling modifies the DMG
- Verification uses CryptoKit `Curve25519.Signing` (SecKey has no EdDSA support on macOS)

**What this prevents:** An attacker who fully controls GitHub (repo + releases) cannot forge the signature without the key in AWS SM. This closes the "attacker swaps both DMG and checksum" hole that a bare checksum has.

---

### Layer 3 — SHA-256 Checksum

After download, the app computes `SHA256(DMG)` and compares against the (signature-verified) published hash. Mismatch → abort + delete.

The checksum is computed in CI **after notarization stapling** — stapling changes the DMG bytes, so hashing before stapling produces a permanent mismatch.

**What this prevents:** Corrupted or truncated downloads, CDN-level tampering.

---

### Layer 4 — Code Signature Verification

Before mounting, the app verifies:

```
codesign -dv <dmg> | grep TeamIdentifier=RLPRR8CPQG
```

**What this prevents:** A DMG re-signed by any other Apple developer, even with a valid checksum+signature chain (e.g. if the Ed25519 key leaked but the Apple cert didn't).

---

### Layer 5 — Mounted Bundle Version Check

After mounting, the app reads `CFBundleShortVersionString` from the mounted bundle and requires it to equal the release tag version.

This exists because of a real bug: `hdiutil attach -quiet -plist` suppresses the plist output, so the mount point silently fell back to a guessed path — which matched a *stale mounted volume of the old version*, reinstalling the old version. The DMG volume name also embeds the version (`HelloWorld-1.0.x`) so two versions can never collide on the same mount point.

**What this prevents:** Installing from a stale/wrong mounted volume.

---

### Layer 6 — Apple Notarization

Every DMG is submitted to Apple (`notarytool submit --wait`) and the ticket is stapled (`stapler staple`). Gatekeeper verifies on first open, even offline.

**What this prevents:** Gatekeeper warnings; distribution of known malware (Apple scans every submission).

---

## Install/relaunch mechanics (not security, but correctness)

- The running bundle cannot be `rm -rf`'d — install copies to `<app>.new-update`, then does an **atomic `mv` swap** (mv doesn't touch open file handles)
- Relaunch is done by an **external helper script** in `/tmp`, launched with `nohup` (macOS has no `setsid`), which waits for the app PID to die, deletes the `.old-update` bundle, re-registers the path with LaunchServices (`lsregister -f`), and `open -na`'s the new version
- Updates install **in-place** (same directory the app runs from), so `/Applications` installs stay in `/Applications` and `~/Applications` stays there

## Attack surface summary

| Attack | Stopped by |
|--------|-----------|
| MITM with forged cert | L1 TLS + pinning |
| MITM during GitHub key rotation window | L1 OCSP check |
| Tampered DMG on CDN | L3 checksum |
| Compromised GitHub swaps DMG + checksum together | L2 Ed25519 (key in AWS SM) |
| Re-signed DMG by another developer | L4 TeamID check |
| Stale volume / wrong version install | L5 version check |
| Malware / Gatekeeper | L6 notarization |

## What is NOT covered

- **Compromised Apple Developer cert (`RLPRR8CPQG`) + Ed25519 key together**: total compromise of both AWS SM and the Apple account defeats everything except TLS. Protect both with strong auth.
- **Compromised CI (GitHub Actions)**: the CI has OIDC access to both signing secrets. A malicious commit to `main` that alters the workflows could exfiltrate keys. Branch protection on `main` is the control.
- **Pinning drift**: when GitHub rotates keys, updates continue via OCSP fallback, but the pins should be refreshed (run the `Get SPKI Hashes` workflow and update `pinnedSPKIHashes`).

## Updating pinned certificates

Run the `Get SPKI Hashes` GitHub Actions workflow (workflow_dispatch), or on any Mac:

```bash
swift scripts/get-spki-hashes.swift
```

Paste the output into `pinnedSPKIHashes` in `Sources/Updater.swift`. Do NOT use OpenSSL-derived hashes — `SecKeyCopyExternalRepresentation` returns raw key bytes, not the DER SubjectPublicKeyInfo, so the hashes differ from `openssl x509 -pubkey`.

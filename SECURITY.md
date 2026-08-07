# Security

## Auto-update security model

Every update goes through 3 independent layers before any code runs on the user's machine.

### Layer 1 — Standard TLS (macOS system trust store)

All network requests use `URLSession.shared` which validates GitHub's certificate chain against the macOS system trust store (managed by Apple, updated via OS updates).

**Why not cert pinning?** GitHub rotates certs without advance notice. Pinning would silently break updates for all existing installs the moment GitHub renews their cert — users would be stuck on an old version with no way to self-update. The downloaded DMG signature (Layer 3) is the real integrity guarantee, not the transport layer.

**What this prevents:** Standard MITM attacks (forged TLS cert not trusted by Apple's root store).

---

### Layer 2 — SHA-256 Checksum

Every release publishes a `HelloWorld-<version>.sha256` file alongside the DMG.
After download, the app computes `SHA256(DMG)` and compares it to the published hash.
If they don't match, the update is aborted and the file is deleted.

**What this prevents:** Corrupted downloads, CDN tampering, partial downloads being installed.

---

### Layer 3 — Code Signature Verification

Before mounting the DMG, the app runs:
```
codesign -dv <dmg> 2>&1 | grep TeamIdentifier
```
and verifies the result contains `TeamIdentifier=RLPRR8CPQG` (ECC's Apple Developer Team ID).

**What this prevents:** A valid-checksum DMG that was re-signed by a different developer.

---

### Layer 4 — Apple Notarization

Every DMG is notarized by Apple before release (`xcrun notarytool submit --wait`).
The notarization ticket is stapled to the DMG (`xcrun stapler staple`).
macOS Gatekeeper verifies the ticket on first open — even offline.

**What this prevents:** macOS blocking the app as unverified software; distribution of malware (Apple scans the binary).

---

## Attack surface summary

| Attack | Mitigated by |
|--------|-------------|
| MITM on network | TLS + cert pinning (L1) |
| Tampered DMG on CDN | SHA-256 checksum (L2) |
| Rogue re-signed DMG | Code signature check (L3) |
| Unsigned/unverified binary | Notarization (L4) |
| Malware in release | Apple notarization scan (L4) |
| Compromised GitHub account | Code signature + notarization (L3+L4) |

## What is NOT covered

- **Compromised Apple Developer account**: if ECC's `RLPRR8CPQG` cert is stolen, all layers except TLS can be bypassed. Protect the `.p12` and Apple ID with strong 2FA.
- **GitHub itself**: if GitHub's infrastructure is compromised at the storage layer, an attacker could swap the DMG and the `.sha256` together. Mitigation: publish checksums to a second, independent location (e.g. the repo's `releases/` folder in git).
- **Pinning drift**: if GitHub migrates CAs and pinned hashes aren't updated, updates stop working. Monitor GitHub's cert chain and update `pinnedSPKIHashes` accordingly.

## Updating pinned certificates

To get the current SPKI hashes from GitHub's live certificate chain:
```bash
openssl s_client -connect api.github.com:443 -showcerts 2>/dev/null \
  | awk '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/' \
  | csplit -z - '/-----BEGIN CERTIFICATE-----/' '{*}' 2>/dev/null
for f in xx*; do
  echo "=== $f ==="
  openssl x509 -in "$f" -noout -subject 2>/dev/null
  openssl x509 -in "$f" -pubkey -noout 2>/dev/null \
    | openssl pkey -pubin -outform der 2>/dev/null \
    | openssl dgst -sha256 -binary \
    | base64
done
rm -f xx*
```

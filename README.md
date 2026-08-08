# poc-macos-dmg

Minimal macOS app (Apple Silicon) with secure auto-update via GitHub Releases — no IP collection by the developer.

The app shows a Hello World window with a live debug console, checks for updates 3s after launch (and hourly while open), and self-updates with user confirmation.

## Layout

```
Sources/main.swift             — app: window + version label + log console
Sources/Updater.swift          — auto-updater: 6 security layers, atomic swap, helper relaunch
Resources/Info.plist           — bundle config (version patched by CI from the git tag)
scripts/build-signed.sh        — compile, Developer ID sign, versioned DMG with /Applications symlink
scripts/sign-checksum.py       — Ed25519-sign the SHA256 file (CI)
scripts/get-spki-hashes.swift  — print GitHub's SPKI hashes as Swift/Security sees them
.github/workflows/build.yml    — CI build on every push
.github/workflows/release.yml  — tag push → sign → notarize → staple → checksum → Ed25519 → GitHub Release
.github/workflows/get-spki-hashes.yml — manual: refresh pin hashes
```

## Release a new version

```bash
# Bump version in Resources/Info.plist, commit, then:
git tag v1.0.X && git push origin main v1.0.X
```

CI builds, signs (Developer ID `RLPRR8CPQG`), notarizes with Apple, staples, computes SHA-256, signs the checksum with Ed25519, and publishes everything to GitHub Releases. Installed apps detect the new release on next launch and prompt to update.

## Secrets & infrastructure

| What | Where |
|------|-------|
| Developer ID cert (.p12) + notarytool creds | AWS SM `/infra/apple/developer-id-macos` |
| Ed25519 update-signing private key | AWS SM `/infra/apple/update-signing-key` |
| CI access | IAM role `poc-macos-dmg-gha` via GitHub OIDC (repo-scoped, secrets-read-only) |

No static credentials in GitHub. The Ed25519 public key is hardcoded in `Updater.swift`.

## Privacy: does the developer see who downloads/updates?

**No.** GitHub logs requests on their infrastructure but exposes zero per-download data to repo owners — no IPs, no download logs, no update-check logs. The app only ever talks to `api.github.com` and `github.com` (release assets). There is no developer-operated server and no telemetry.

For absolute zero-knowledge (where not even GitHub sees user IPs), alternatives are IPFS or a Tor onion service — out of scope for this POC.

## Update security

Six layers — TLS + SPKI pinning with OCSP fallback, Ed25519-signed checksums, SHA-256, codesign TeamID verification, mounted-bundle version check, and Apple notarization. Full threat model, rationale, and pin-rotation runbook in [SECURITY.md](SECURITY.md).

## Install/relaunch mechanics

- First install: DMG shows app + `/Applications` symlink, user drags (standard macOS pattern)
- Updates install **in-place** (same directory the app runs from)
- The running bundle is never deleted — new version lands as `.new-update`, then an atomic `mv` swap
- A helper script in `/tmp` (launched with `nohup`; macOS has no `setsid`) waits for the app to exit, cleans up the old bundle, re-registers with LaunchServices, and relaunches
- DMG volume name embeds the version (`HelloWorld-1.0.X`) so stale mounted volumes can never be mistaken for the new one

## Hard-won macOS gotchas (for the next person)

1. `hdiutil attach -quiet -plist` — `-quiet` suppresses the plist. You get no mount point.
2. `setsid` does not exist on macOS. Use `nohup ... &`.
3. You cannot `rm -rf` a running app bundle. `mv` works (open file handles survive).
4. `stapler staple` modifies the DMG — compute checksums **after** notarization.
5. `SecKeyCopyExternalRepresentation` ≠ OpenSSL SPKI — compute pin hashes with the same API that verifies them (`scripts/get-spki-hashes.swift`).
6. SecKey has no EdDSA — use CryptoKit `Curve25519.Signing` for Ed25519.
7. New GitHub repos use `repo:org@ID/name@ID:*` OIDC sub claims — old-style `repo:org/name:*` trust policies fail.
8. macos-15 runners: `pip3 install` needs `--break-system-packages`.

# Release process

MacPeek is distributed directly (Developer ID signed, notarized DMG) from GitHub Releases, and the website
(`MACPeek-Web` repo, hosted on Vercel) links to the newest release automatically. Everything after tagging is automated by
`.github/workflows/release.yml`.

- [Quick reference](#quick-reference)
- [One-time setup](#one-time-setup)
- [Sparkle (in-app updates)](#sparkle-in-app-updates)
- [Every release](#every-release)
- [What the workflow does](#what-the-workflow-does)
- [Troubleshooting](#troubleshooting)
- [Rotating credentials](#rotating-credentials)
- [Mac App Store](#mac-app-store)

## Quick reference

```bash
# 1. Update CHANGELOG.md on main (rename [Unreleased] to the new version), merge it.
git checkout main && git pull origin main

# 2. Optional dry run (published as a pre-release; never "latest"; no website rebuild).
git tag v0.1.0-rc1 && git push origin v0.1.0-rc1

# 3. Real release.
git tag v0.1.0 && git push origin v0.1.0
```

- The tag **must** start with `v` (`v0.1.1`, not `macpeek-v0.1.1`); the workflow only triggers on `v*`.
- **Never create the release by hand** in the GitHub UI: a manual release has only the auto-generated source archives, no
  DMG. The workflow creates the release and attaches the files.
- A tag containing a hyphen (`v0.2.0-rc1`, `v1.0.0-beta.1`) is a pre-release. Delete a dry run afterwards:
  delete the release on GitHub, then `git push origin :refs/tags/v0.1.0-rc1 && git tag -d v0.1.0-rc1`.

## One-time setup

Needs a paid Apple Developer Program membership. Do this once; releases afterwards are just a tag.

### 1. Developer ID Application certificate

1. Keychain Access menu (top menu bar, not the window) → **Certificate Assistant → Request a Certificate From a Certificate
   Authority**. Enter your email and a name, choose **Saved to disk**, save the `.certSigningRequest`.
2. developer.apple.com → **Certificates, IDs & Profiles → Certificates → +** → **Developer ID Application** (only the
   Account Holder can create it). Upload the request, download the `.cer`, double-click it so it installs in the
   **login** keychain on the same Mac that made the request (the private key lives there).
3. If Keychain Access says the certificate is "not trusted", install Apple's current intermediate certificates from
   apple.com/certificateauthority (Worldwide Developer Relations G3/G2 and Developer ID G2) and remove expired ones.
4. Confirm it is usable and note the exact name:
   ```bash
   security find-identity -v -p codesigning
   # 1) ABC123... "Developer ID Application: Your Name (TEAMID)"
   ```
   It must be **Developer ID Application**. An "Apple Development" certificate cannot sign for distribution.

### 2. Export the signing identity (`.p12`)

Keychain Access sometimes greys out *Export → .p12*. The command line works regardless:

```bash
security export -k ~/Library/Keychains/login.keychain-db -t identities -f pkcs12 \
  -P "CHOOSE-A-STRONG-PASSWORD" -o ~/Desktop/macpeek.p12
```

- Approve the macOS prompt (login password / Allow). The password you choose becomes `DEVELOPER_ID_CERT_PASSWORD`.
- This exports **every** signing identity in the login keychain, not just Developer ID. Treat the file as a secret
  (anyone with it and the password can sign as you) and delete it once the secrets are saved.
- Verify it (add `-legacy` if OpenSSL complains about an algorithm):
  ```bash
  openssl pkcs12 -in ~/Desktop/macpeek.p12 -nokeys -passin pass:"CHOOSE-A-STRONG-PASSWORD" | grep subject
  ```

### 3. Notarization API key

1. appstoreconnect.apple.com → **Users and Access → Integrations → App Store Connect API → Team Keys → +**.
   Name it "MacPeek CI", role **Developer**. (If the Integrations tab is missing, the Account Holder must request API
   access first.)
2. Download the `.p8` immediately (Apple lets you download it **once**). Note the **Key ID** and the **Issuer ID**
   shown at the top of the page.

### 4. Vercel deploy hook

Vercel → the website project → **Settings → Git → Deploy Hooks** → create one on `main`. Its URL becomes
`VERCEL_DEPLOY_HOOK_URL`. Required for stable tags (see below).

### 5. GitHub repository secrets

Repo → **Settings → Secrets and variables → Actions → New repository secret**. Never commit these or paste them in chat.

| Secret | Value |
|---|---|
| `DEVELOPER_ID_CERT_P12_BASE64` | `base64 -i ~/Desktop/macpeek.p12 \| pbcopy`, paste |
| `DEVELOPER_ID_CERT_PASSWORD` | the `.p12` password from step 2 |
| `DEVELOPER_ID_IDENTITY` | the full name from step 1, e.g. `Developer ID Application: Mohit Kapoor (8FD8P82XPG)` |
| `NOTARY_API_KEY_P8_BASE64` | `base64 -i ~/Downloads/AuthKey_XXXXXXXX.p8 \| pbcopy`, paste |
| `NOTARY_API_KEY_ID` | Key ID from App Store Connect |
| `NOTARY_API_ISSUER_ID` | Issuer ID from App Store Connect |
| `VERCEL_DEPLOY_HOOK_URL` | the Deploy Hook URL from step 4 |
| `SPARKLE_ED_PRIVATE_KEY` | the Sparkle private key (see [Sparkle](#sparkle-in-app-updates)) |

And one repository **variable** (not a secret; Settings → Secrets and variables → Actions → **Variables** tab):
`SPARKLE_PUBLIC_ED_KEY`, the matching public key.

Then delete the loose files: `rm ~/Desktop/macpeek.p12 ~/Downloads/AuthKey_*.p8` (keep a copy in a password manager if
you want a backup).

## Sparkle (in-app updates)

MacPeek checks for updates with [Sparkle](https://sparkle-project.org) (about once a day, switch in Settings; **Check for
Updates…** in Settings checks on demand). The release workflow signs each DMG with an EdDSA key and publishes
`appcast.xml` as a release asset; the app reads `releases/latest/download/appcast.xml`, which always points at the newest
**stable** release (pre-releases are never offered). The first release with Sparkle is the first one users can update
*from*: people on an older build must download it manually once.

### One-time key setup (do this on your Mac)

```bash
curl -fsSL -o Sparkle.tar.xz https://github.com/sparkle-project/Sparkle/releases/download/2.9.6/Sparkle-2.9.6.tar.xz
mkdir sparkle && tar -xJf Sparkle.tar.xz -C sparkle
./sparkle/bin/generate_keys                      # creates the key pair in your login keychain, prints the PUBLIC key
./sparkle/bin/generate_keys -x ~/Desktop/sparkle_private_key   # exports the PRIVATE key to a file
```

1. Copy the printed public key into the repository **variable** `SPARKLE_PUBLIC_ED_KEY`.
2. Copy the *contents* of `sparkle_private_key` into the repository **secret** `SPARKLE_ED_PRIVATE_KEY`.
3. **Back the private key up** (password manager). If it is lost, installed copies can no longer verify updates, and
   every user has to download a new build by hand. Then delete the file from the Desktop.
4. Releases fail early with a clear message if either is missing. Local builds without the key run with updates off.

### Notes
- The Sparkle version is pinned in `Package.swift` and `SPARKLE_VERSION` in `release.yml`; change both together.
- Do not rename the DMG asset: the appcast points at `MacPeek-X.Y.Z.dmg` in the release.
- The version number must keep increasing (the app compares it with the installed one).
- Never re-sign or modify a published DMG: the signature in `appcast.xml` would no longer match.

## Every release

1. Update `CHANGELOG.md` (rename `[Unreleased]` to the version and date) and merge to `main`.
2. Optionally dry-run with a `-rc` tag (see Quick reference). On another Mac or a fresh user account, download the DMG,
   open it (Gatekeeper must not warn), and check:
   ```bash
   spctl --assess --type open --context context:primary-signature -v MacPeek-0.1.0-rc1.dmg   # accepted, Notarized Developer ID
   ```
3. Push the real tag. Watch **Actions → Release**. Expect 10 to 30 minutes, mostly notarization.
4. Check the GitHub release has `MacPeek-X.Y.Z.dmg`, `MacPeek.dmg` and `SHA256SUMS`, and that the website shows the new
   version (it rebuilds through the deploy hook).
5. Release notes are auto-generated by GitHub. To use hand-written notes, edit the release on GitHub after publishing.

Local, unsigned build for testing: `scripts/build-app.sh 0.1.0 && scripts/make-dmg.sh 0.1.0`.

## What the workflow does

On a `v*` tag: (stable tags only) require `VERCEL_DEPLOY_HOOK_URL` → require the Sparkle keys → test → import certificate into a temporary keychain →
build a universal app and sign it (Developer ID, hardened runtime) → DMG → notarize with `notarytool --wait --timeout 30m`
→ staple + validate + `spctl` check → sign the DMG with the Sparkle key and write `appcast.xml` → add a versionless `MacPeek.dmg` and write `SHA256SUMS` for both → publish the GitHub
release (hyphenated tags as a pre-release) → (stable tags only) call the Vercel deploy hook. Any failed step aborts the
release; an unsigned or un-notarized build is never published.

Assets: `MacPeek-X.Y.Z.dmg`, `appcast.xml`, `MacPeek.dmg` (a never-changing link,
`https://github.com/mohitkap12-a11y/MACPeek/releases/latest/download/MacPeek.dmg`) and `SHA256SUMS`.

**Website.** At build time the site (`MACPeek-Web`) reads the latest release from the GitHub API and links its Download
buttons to the `MacPeek-X.Y.Z.dmg` asset, so do not rename the assets. A GitHub error other than "no release yet" fails
the site build on Vercel instead of deploying a false "no release" page, so the previous deployment stays live. If the
deploy-hook call fails after publishing, the job only warns: redeploy the site from the Vercel dashboard.

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| Release has only source code, no DMG | The workflow did not run. The tag was not `v*` or the release was created by hand. Delete the release and tag, push a correctly named tag. |
| Stable tag fails immediately: `VERCEL_DEPLOY_HOOK_URL is not set` | Add the secret (setup step 4/5). Pre-release tags do not need it. |
| *Export → .p12* is greyed out in Keychain Access | Use the `security export` command above. If `security find-identity` shows no Developer ID identity, the certificate has no private key on this Mac: create a new request and certificate on the Mac that will hold the key. |
| Certificate shows "not trusted" | Install Apple's current intermediate certificates (setup step 1.3). |
| Notarization runs a long time, then the workflow step times out | Normal for a **new developer account's first submissions** (can take hours, occasionally up to about a day). Do not resubmit: the submission continues on Apple's side. Check it (below). Once accepted, re-run the failed job or push a fresh tag; later submissions are usually minutes. |
| Notarization result is **Invalid** | The step fails with the reason in its log (`notarytool log <id>`). Fix what it names (usually signing or hardened runtime) and re-tag. |

Check a notarization submission (use the ID printed in the workflow log):

```bash
xcrun notarytool info <submission-id> --key AuthKey_XXXXXXXX.p8 --key-id <KEY_ID> --issuer <ISSUER_ID>
xcrun notarytool history --key AuthKey_XXXXXXXX.p8 --key-id <KEY_ID> --issuer <ISSUER_ID>
xcrun notarytool log <submission-id> --key AuthKey_XXXXXXXX.p8 --key-id <KEY_ID> --issuer <ISSUER_ID>
```

If a submission stays "In Progress" for more than about 24 hours, check Apple's System Status page and contact Apple
Developer Support with the submission ID.

## Rotating credentials

- **Developer ID certificate** expires after about five years (the date is in Keychain Access). Create a new one (setup
  steps 1 to 2) and update `DEVELOPER_ID_CERT_P12_BASE64`, `DEVELOPER_ID_CERT_PASSWORD` and, if the name changed,
  `DEVELOPER_ID_IDENTITY`. Already-published, notarized releases keep working.
- **API key**: revoke it in App Store Connect if leaked, create a new one, update the three `NOTARY_*` secrets.
- **Deploy hook**: delete and recreate it in Vercel if the URL leaks, then update `VERCEL_DEPLOY_HOOK_URL`.

## Mac App Store

Not planned. The App Store requires the App Sandbox, and several utilities (ending processes, `lsof`, reading other
processes' details and command lines) rely on things the sandbox restricts, so MacPeek is intentionally not sandboxed
(`Resources/MacPeek.entitlements` is empty). Distribution stays direct. A reduced sandboxed edition would be a separate
project.

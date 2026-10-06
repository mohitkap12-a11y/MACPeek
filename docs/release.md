# Release process

1. Update `CHANGELOG.md`; tag `vX.Y.Z` on `main`.
2. `.github/workflows/release.yml` runs on the tag: test → import certificate → build + sign (Developer ID, hardened
   runtime) → DMG → notarize + staple + validate → publish `MacPeek-X.Y.Z.dmg` and `SHA256SUMS`. Any failed step
   aborts the release; an unsigned build is never published.
3. Required repository secrets (never commit these): `DEVELOPER_ID_CERT_P12_BASE64`, `DEVELOPER_ID_CERT_PASSWORD`,
   `DEVELOPER_ID_IDENTITY`, `NOTARY_API_KEY_P8_BASE64`, `NOTARY_API_KEY_ID`, `NOTARY_API_ISSUER_ID`.

Local, unsigned build for testing: `scripts/build-app.sh 0.1.0 && scripts/make-dmg.sh 0.1.0`.

Distribution is direct DMG (Developer ID). Mac App Store distribution needs separate investigation because the App
Sandbox restricts the process termination and system queries several utilities rely on.

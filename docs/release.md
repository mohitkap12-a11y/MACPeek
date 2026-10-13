# Release process

1. Update `CHANGELOG.md`; tag `vX.Y.Z` on `main`.
2. `.github/workflows/release.yml` runs on the tag: test → import certificate → build + sign (Developer ID, hardened
   runtime) → DMG → notarize + staple + validate → publish `MacPeek-X.Y.Z.dmg` and `SHA256SUMS`. Any failed step
   aborts the release; an unsigned build is never published.
3. Required repository secrets (never commit these): `DEVELOPER_ID_CERT_P12_BASE64`, `DEVELOPER_ID_CERT_PASSWORD`,
   `DEVELOPER_ID_IDENTITY`, `NOTARY_API_KEY_P8_BASE64`, `NOTARY_API_KEY_ID`, `NOTARY_API_ISSUER_ID`.

4. Each release publishes `MacPeek-X.Y.Z.dmg`, a versionless `MacPeek.dmg` (a never-changing link:
   `https://github.com/mohitkap12-a11y/MACPeek/releases/latest/download/MacPeek.dmg`) and `SHA256SUMS`. The website lives
   in the separate `MACPeek-Web` repo; at build time it reads the latest release from the GitHub API and links its
   Download buttons to the `MacPeek-X.Y.Z.dmg` asset. The final workflow step calls the Vercel Deploy Hook so the site
   rebuilds and shows the new version. The secret `VERCEL_DEPLOY_HOOK_URL` (Vercel → Project → Settings → Git → Deploy
   Hooks) is **required for stable tags**: the workflow fails before building anything if it is missing. If the hook call
   itself fails after publishing, the job warns and you redeploy the site from the Vercel dashboard. The site expects
   the exact asset names above, so do not rename them.
5. Dry run: tag `v0.1.0-rc1`. A tag containing a hyphen is published as a pre-release (never "latest") and does not
   rebuild the website. Delete the release and tag afterwards.

Local, unsigned build for testing: `scripts/build-app.sh 0.1.0 && scripts/make-dmg.sh 0.1.0`.

Distribution is direct DMG (Developer ID). Mac App Store distribution needs separate investigation because the App
Sandbox restricts the process termination and system queries several utilities rely on.

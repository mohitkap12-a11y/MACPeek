# Testing the PortPeek website

The site is a static [Astro](https://astro.build) project in `Website/`. Requires **Node 22** (what CI uses).

```bash
cd Website
npm ci            # install exact dependencies from the lockfile
```

## Automated checks
Run in this order (it is exactly what CI does):

```bash
npm run check     # content lint: unique titles/descriptions, sane lengths, an h1 on every markdown page
npm run build     # build the static site into Website/dist
npm test          # tests against dist/ — build first
```

`npm test` verifies that:
- all expected pages exist (home, utilities index + one page per utility, download, privacy, security, docs, guides) and `/docs/privacy/` redirects to `/privacy/`;
- every page has exactly one `<h1>`, a title, description, canonical URL, Open Graph and Twitter tags, and `lang="en"`;
- **every page is dark by default and has the theme switch** and restores the saved choice;
- no external `<script src>` is loaded (no trackers);
- all JSON-LD blocks parse;
- `sitemap-index.xml`, `sitemap-0.xml` and `robots.txt` are generated;
- every internal link resolves;
- titles and descriptions are unique and a sensible length across all pages;
- the brand is MacPeek everywhere (no stale `PortPeek-x.y.z` download names);
- every utility page has the required sections (problem, solution, how it works, installation, privacy, open source);
- **honesty checks**: unreleased utilities say *Coming soon* and never claim availability, and guides for them don't pitch a download;
- `tests/catalog.test.mjs`: the site's utility list matches the Swift catalog (ids, names, categories, availability).

## Look at it yourself
```bash
npm run dev                          # http://localhost:4321, hot reload
npm run build && npm run preview     # the real built output
```
Manual checklist:
- **Dark is the default** on first visit (clear site data / use a private window to confirm).
- Click the sun/moon button in the header: the page switches, and the choice survives a reload
  (stored in `localStorage` under `portpeek-theme`; nothing is sent anywhere).
- Narrow the window to phone width: no horizontal scroll, header stays tidy, bento cards stack.
- Tab through the page with the keyboard: focus rings are visible; "Skip to content" appears first.
- The Download and GitHub buttons point to the repository's latest release and source.

## Screenshots
Screens on the site are illustrations until real captures exist; see [SCREENSHOTS.md](SCREENSHOTS.md) for the drop-in workflow.

## Before the first release
- `SITE.hasRelease` in `src/site.ts` is `false`: every Download button goes to `/download/`, which explains that no signed release exists yet and shows how to build from source. **Flip it to `true` when the first release is published**; buttons then go to GitHub's latest release.

## Before launch
- Build with your real domain so canonical URLs and the sitemap are right (it defaults to `portpeek.app`):
  `SITE_URL=https://example.com npm run build`
- Replace illustrations with real captures (see SCREENSHOTS.md).
- Run Lighthouse (Chrome DevTools) against `npm run preview` for performance/accessibility/SEO scores.
- Social image: `public/og-image.png` (1200×630), generated from `scripts/og.html`.

## Theming notes
Design tokens live at the top of `src/styles/global.css` (`:root` = dark, `:root[data-theme='light']` = light).
The theme is applied by a tiny inline script in `src/layouts/Base.astro` before first paint, so there is no flash.

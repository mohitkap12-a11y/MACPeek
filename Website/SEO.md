# SEO, GEO and AI search checklist

Everything below is generated from the site's data, so it stays in step with the pages. `tests/seo.test.mjs` fails the
build when any of it regresses.

## 1. Set the canonical domain (one value)
Canonical URLs, `og:url`, the sitemap, `robots.txt`, `llms.txt` and the feed all use one origin, chosen in this order:

1. `SITE_URL` (set it in the Vercel project: **Settings → Environment Variables**, Production),
2. `VERCEL_PROJECT_PRODUCTION_URL` (Vercel sets it to the production domain; enable "Automatically expose System
   Environment Variables"),
3. `https://portpeek.app`, a local-build placeholder that is **not** a real choice.

Attach the custom domain in Vercel (**Settings → Domains**) and make it the primary one, then confirm
`view-source:<domain>/` shows `<link rel="canonical" href="https://<domain>/">`. Redirect `www` ↔ apex and the
`*.vercel.app` production URL to the primary domain in the same screen so there is one copy of the site.

## 2. Tell Google and Bing
- **Google Search Console** → add a *Domain* property (DNS TXT) or a *URL-prefix* property. For URL-prefix, put the HTML tag
  token in the build environment as `GOOGLE_SITE_VERIFICATION` and redeploy; the tag is emitted automatically.
- Submit `https://<domain>/sitemap-index.xml`. Use **URL inspection → Request indexing** for the home page, `/utilities/`,
  `/docs/` and `/blog/`; the sitemap and internal links cover the rest.
- **Bing Webmaster Tools** → import from Google Search Console, or set `BING_SITE_VERIFICATION`. Bing powers ChatGPT search
  and Copilot citations, so this matters for AI answers too.

## 3. What is indexable
Every page in the sitemap: home, utilities (index + one per utility), docs, guides, download, privacy, security.
Excluded on purpose: `/404/` (noindex), the `/docs/privacy/` redirect stub (301 in `vercel.json`), and preview deployments
(`noindex` meta, `Disallow: /` in robots.txt and Vercel's own header).

## 4. What is in place
- Unique `<title>` (≤ 60 characters) and meta description per page; one `<h1>`; canonical; robots meta with
  `max-image-preview:large,max-snippet:-1` so Google and AI features may use full snippets and images.
- Open Graph and Twitter cards with a 1200×630 image and alt text; favicon (SVG, 48 and 192 px PNG) and Apple touch icon.
- JSON-LD: `Organization`, `WebSite`, `SoftwareApplication` and `FAQPage` (home); `SoftwareApplication` + visible
  `FAQPage` + breadcrumbs (every utility); `TechArticle`/`Article` + breadcrumbs (docs, guides); `CollectionPage`/`ItemList`
  (indexes). Structured data only states what the page shows. Nothing is fabricated (no ratings, no download URL before a release).
- `sitemap-index.xml` with `lastmod` only where a page carries a real date; `robots.txt` that explicitly welcomes AI
  crawlers (GPTBot, OAI-SearchBot, ClaudeBot, PerplexityBot, Google-Extended, …); `llms.txt` and `llms-full.txt` (a
  plain-text map and the full text of every utility); an RSS feed of the guides.
- Answer-first copy for AI search: each utility page opens with the question it answers, states what it reads and needs, and
  ends with a visible FAQ. Dates are real `<time>` elements.
- Security and caching headers in `vercel.json` (immutable caching for `/_astro/*`).

## 5. After launch
- Flip `SITE.hasRelease` in `src/site.ts` once the first release exists; `SoftwareApplication` then gains `downloadUrl`.
- Replace the illustrated screens with real screenshots (`public/screenshots/<id>.png`); add `screenshot` to the schema then.
- Watch Search Console → Pages for "Crawled, currently not indexed" and fix thin pages rather than resubmitting.

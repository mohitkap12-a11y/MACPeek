import { defineConfig } from 'astro/config';
import sitemap from '@astrojs/sitemap';
import { readFileSync, existsSync } from 'node:fs';

// Canonical origin, in order of preference:
//   1. SITE_URL (set it in the Vercel project once the custom domain is attached),
//   2. Vercel's own production URL (VERCEL_PROJECT_PRODUCTION_URL, the custom domain if there is one),
//   3. a placeholder for local builds.
// Canonicals, the sitemap, robots.txt, llms.txt and the feed all derive from this one value.
const vercelProd = process.env.VERCEL_PROJECT_PRODUCTION_URL;
const site = process.env.SITE_URL || (vercelProd ? `https://${vercelProd}` : 'https://portpeek.app');

// lastmod only where it is true: Markdown pages carry their own date in frontmatter. Other pages omit it.
function lastmodFor(pathname) {
  const rel = pathname.replace(/^\/|\/$/g, '');
  const file = new URL(`./src/pages/${rel}.md`, import.meta.url);
  if (!rel || !existsSync(file)) return undefined;
  const m = readFileSync(file, 'utf8').match(/^date: "(\d{4}-\d{2}-\d{2})"/m);
  return m ? new Date(m[1]).toISOString() : undefined;
}

export default defineConfig({
  site,
  trailingSlash: 'always',
  // Privacy moved from /docs/privacy/ to the top-level /privacy/ (vercel.json adds the real 301).
  redirects: { '/docs/privacy/': '/privacy/' },
  build: { format: 'directory' },
  integrations: [
    sitemap({
      // Keep redirect stubs and the 404 page out of the index.
      filter: (page) => !/\/(404|docs\/privacy)\/?$/.test(new URL(page).pathname),
      serialize(item) {
        const lastmod = lastmodFor(new URL(item.url).pathname);
        return lastmod ? { ...item, lastmod } : item;
      },
    }),
  ],
});

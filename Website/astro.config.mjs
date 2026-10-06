import { defineConfig } from 'astro/config';
import sitemap from '@astrojs/sitemap';
import { readFileSync, existsSync } from 'node:fs';

// Canonical origin: the production domain, www.macpeekapp.com (www is the primary host). Canonicals, og:url, the sitemap,
// robots.txt, llms.txt and the feed all derive from this one value, on previews too, so a preview can never become
// a competing copy. SITE_URL overrides it (for a staging domain or a local build).
const site = process.env.SITE_URL || 'https://www.macpeekapp.com';

// lastmod only where it is true: Markdown pages carry their own date in frontmatter. Other pages omit it.
function lastmodFor(pathname) {
  const rel = pathname.replace(/^\/|\/$/g, '');
  if (!rel) return undefined;
  // A page is either <rel>.md or <rel>/index.md.
  const file = [`./src/pages/${rel}.md`, `./src/pages/${rel}/index.md`].map((p) => new URL(p, import.meta.url)).find((f) => existsSync(f));
  if (!file) return undefined;
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

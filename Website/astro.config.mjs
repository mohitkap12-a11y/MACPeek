import { defineConfig } from 'astro/config';
import sitemap from '@astrojs/sitemap';

// The production domain is not purchased/verified yet: override with SITE_URL at build time.
const site = process.env.SITE_URL || 'https://portpeek.app';

export default defineConfig({
  site,
  trailingSlash: 'always',
  // Privacy moved from /docs/privacy/ to the top-level /privacy/.
  redirects: { '/docs/privacy/': '/privacy/' },
  build: { format: 'directory' },
  integrations: [sitemap()],
});

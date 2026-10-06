import type { APIRoute } from 'astro';
import { SITE, blogPosts } from '../site';

// A feed of the guides: gives crawlers and aggregators a cheap way to find new pages.
const esc = (s: string) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
const modules = import.meta.glob('./blog/*.md', { eager: true }) as Record<string, { frontmatter: { title: string; description: string; date?: string } }>;

export const GET: APIRoute = ({ site }) => {
  const items = blogPosts
    .map((p) => {
      const fm = modules[`./blog/${p.slug}.md`]?.frontmatter;
      return fm && { url: new URL(`/blog/${p.slug}/`, site).toString(), title: fm.title, description: fm.description, date: fm.date ?? '2026-10-06' };
    })
    .filter(Boolean) as { url: string; title: string; description: string; date: string }[];
  const xml = `<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom"><channel>
<title>${esc(SITE.name)} guides</title>
<link>${new URL('/blog/', site)}</link>
<description>Practical guides for finding and understanding what is happening on your Mac.</description>
<language>en</language>
<atom:link href="${new URL('/rss.xml', site)}" rel="self" type="application/rss+xml"/>
${items.map((i) => `<item><title>${esc(i.title)}</title><link>${i.url}</link><guid isPermaLink="true">${i.url}</guid><pubDate>${new Date(i.date).toUTCString()}</pubDate><description>${esc(i.description)}</description></item>`).join('\n')}
</channel></rss>
`;
  return new Response(xml, { headers: { 'Content-Type': 'application/rss+xml; charset=utf-8' } });
};

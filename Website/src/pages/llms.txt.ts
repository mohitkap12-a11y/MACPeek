import type { APIRoute } from 'astro';
import { SITE, docsGroups, blogPosts } from '../site';
import { utilities, available } from '../data/utilities';

// llms.txt: a plain-text map of the site for AI assistants (see llmstxt.org). Generated from the same data as the
// pages, so it cannot drift from them.
export const GET: APIRoute = ({ site }) => {
  const abs = (p: string) => new URL(p, site).toString();
  const lines = [
    `# ${SITE.name}`,
    '',
    `> ${SITE.description}`,
    '',
    `MacPeek is free and open source (MIT). No account, no telemetry. It runs as your macOS user (macOS 13 or later, Apple silicon and Intel) and never asks for administrator rights. ${available.length} utilities are built into the app today; the first signed release ${SITE.hasRelease ? 'is published' : 'is not published yet'}. Source: ${SITE.github}`,
    '',
    '## Utilities',
    ...utilities.map((u) => `- [${u.name}](${abs(`/utilities/${u.id}/`)}): ${u.question} ${u.tagline}${u.status === 'available' ? '' : ' (coming soon, not released)'}`),
    '',
    '## Documentation',
    ...docsGroups.flatMap((g) => g.links.map((l) => `- [${l.label}](${abs(l.href)}): ${l.blurb}`)),
    '',
    '## Guides',
    ...blogPosts.map((p) => `- [${p.label}](${abs(`/blog/${p.slug}/`)})`),
    '',
    '## Optional',
    `- [Full text of every utility page](${abs('/llms-full.txt')})`,
    `- [Privacy](${abs('/privacy/')})`,
    `- [Security](${abs('/security/')})`,
    `- [Download](${abs('/download/')})`,
    '',
  ];
  return new Response(lines.join('\n'), { headers: { 'Content-Type': 'text/plain; charset=utf-8' } });
};

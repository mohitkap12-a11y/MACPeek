// SEO / GEO regression tests: every indexable page must be discoverable, canonical, uniquely described and
// machine-readable. Runs against the built site (npm run build first, as for the other tests).
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync, existsSync } from 'node:fs';
import { join, relative } from 'node:path';

const dist = new URL('../dist/', import.meta.url).pathname;
const html = (p) => readFileSync(p, 'utf8');
const pages = [];
(function walk(d) {
  for (const f of readdirSync(d)) {
    const p = join(d, f);
    statSync(p).isDirectory() ? walk(p) : f.endsWith('.html') && pages.push(p);
  }
})(dist);
const route = (p) => '/' + relative(dist, p).replace(/index\.html$/, '').replace(/404\.html$/, '404/');
const isRedirectStub = (h) => /http-equiv="refresh"/i.test(h);
const isNoindex = (h) => /<meta name="robots" content="noindex/i.test(h);
const indexable = pages.filter((p) => !isRedirectStub(html(p)) && !isNoindex(html(p)));
const origin = new URL(html(join(dist, 'index.html')).match(/<link rel="canonical" href="([^"]+)"/)[1]).origin;

test('canonical origin is the production domain', () => {
  assert.equal(origin, 'https://www.macpeekapp.com');
});

test('indexable pages: one h1, unique title ≤ 60 chars, unique description, canonical to themselves', () => {
  const titles = new Map(), descs = new Map();
  for (const p of indexable) {
    const h = html(p), r = route(p);
    assert.equal((h.match(/<h1[ >]/g) || []).length, 1, `${r}: needs exactly one h1`);
    const title = h.match(/<title>(.*?)<\/title>/)[1];
    assert.ok(title.length <= 60, `${r}: title is ${title.length} chars (>60 gets truncated in results): ${title}`);
    assert.ok(!titles.has(title), `${r}: duplicate title with ${titles.get(title)}`); titles.set(title, r);
    const d = (h.match(/<meta name="description" content="(.*?)"/) || [])[1];
    assert.ok(d && d.length >= 70 && d.length <= 175, `${r}: description length ${d?.length}`);
    assert.ok(!descs.has(d), `${r}: duplicate description with ${descs.get(d)}`); descs.set(d, r);
    assert.match(h, new RegExp(`<link rel="canonical" href="${origin.replace(/[.]/g, '\\.')}${r.replace(/[/]/g, '\\/')}"`), `${r}: canonical must be its own absolute URL`);
    assert.match(h, /<meta name="robots" content="index,follow,max-image-preview:large/, `${r}: robots meta`);
    assert.match(h, /<html lang="en"/, `${r}: lang`);
  }
});

test('open graph and twitter cards are complete, with absolute URLs', () => {
  for (const p of indexable) {
    const h = html(p), r = route(p);
    for (const tag of ['og:title', 'og:description', 'og:url', 'og:image', 'og:image:alt', 'og:image:width', 'twitter:card', 'twitter:image']) {
      assert.match(h, new RegExp(`(property|name)="${tag}"`), `${r}: missing ${tag}`);
    }
    assert.match(h, /property="og:image" content="https?:\/\//, `${r}: og:image must be absolute`);
  }
});

test('structured data parses and every indexable page has some', () => {
  for (const p of indexable) {
    const blocks = [...html(p).matchAll(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/g)].map((m) => JSON.parse(m[1]));
    assert.ok(blocks.length > 0, `${route(p)}: no JSON-LD`);
    for (const b of blocks) assert.equal(b['@context'], 'https://schema.org');
  }
  const home = [...html(join(dist, 'index.html')).matchAll(/ld\+json">([\s\S]*?)<\/script>/g)].map((m) => JSON.parse(m[1])['@type']);
  for (const t of ['Organization', 'WebSite', 'SoftwareApplication', 'FAQPage']) assert.ok(home.includes(t), `home needs ${t}`);
});

test('FAQ JSON-LD on utility pages matches visible text', () => {
  for (const p of indexable.filter((x) => /^\/utilities\/[a-z]+\/$/.test(route(x)))) {
    const h = html(p);
    const faq = [...h.matchAll(/ld\+json">([\s\S]*?)<\/script>/g)].map((m) => JSON.parse(m[1])).find((b) => b['@type'] === 'FAQPage');
    assert.ok(faq, `${route(p)}: FAQPage missing`);
    for (const q of faq.mainEntity) assert.ok(h.includes(q.name.replace(/'/g, '&#39;')) || h.includes(q.name), `${route(p)}: FAQ question not visible: ${q.name}`);
  }
});

test('sitemap lists every indexable page and nothing else', () => {
  const index = html(join(dist, 'sitemap-index.xml'));
  assert.match(index, new RegExp(`${origin.replace(/[.]/g, '\\.')}/sitemap-0\\.xml`));
  const urls = [...html(join(dist, 'sitemap-0.xml')).matchAll(/<loc>([^<]+)<\/loc>/g)].map((m) => new URL(m[1]).pathname);
  const expected = indexable.map(route).sort();
  assert.deepEqual([...urls].sort(), expected, 'sitemap and indexable pages differ');
  assert.ok(!urls.includes('/404/') && !urls.includes('/docs/privacy/'));
});

test('robots.txt allows crawling, welcomes AI crawlers and points at the sitemap', () => {
  const r = html(join(dist, 'robots.txt'));
  assert.match(r, /User-agent: \*\nAllow: \//);
  for (const bot of ['GPTBot', 'OAI-SearchBot', 'ClaudeBot', 'PerplexityBot', 'Google-Extended']) assert.match(r, new RegExp(`User-agent: ${bot}\\nAllow: /`));
  assert.doesNotMatch(r, /Disallow: \/\s*$/m, 'production robots.txt must not block the site');
  assert.match(r, /Sitemap: https?:\/\/.+\/sitemap-index\.xml/);
});

test('llms.txt covers every utility, doc and guide with absolute links', () => {
  const t = html(join(dist, 'llms.txt'));
  assert.match(t, /^# MacPeek/);
  for (const p of indexable.filter((x) => /^\/(utilities|docs|blog)\/.+\/$/.test(route(x)))) {
    assert.ok(t.includes(route(p)), `llms.txt missing ${route(p)}`);
  }
  assert.ok(existsSync(join(dist, 'llms-full.txt')));
});

test('feed, icons and og image exist', () => {
  assert.match(html(join(dist, 'rss.xml')), /<rss version="2.0"/);
  for (const f of ['favicon.svg', 'favicon-48.png', 'favicon-192.png', 'apple-touch-icon.png', 'og-image.png']) assert.ok(existsSync(join(dist, f)), f);
});

test('every internal link resolves to a built page', () => {
  const known = new Set(pages.map(route));
  for (const p of indexable) {
    for (const m of html(p).matchAll(/<a [^>]*href="(\/[^"#?]*)/g)) {
      const target = m[1];
      if (/\.[a-z0-9]+$/i.test(target)) continue; // files (rss.xml, llms.txt, images)
      assert.ok(known.has(target), `${route(p)}: broken link ${target}`);
    }
  }
});

test('the 404 page is noindex and not in the sitemap', () => {
  assert.match(html(join(dist, '404.html')), /<meta name="robots" content="noindex/);
});

test('vercel.json 301s the old privacy URL and keeps trailing slashes', () => {
  const v = JSON.parse(readFileSync(new URL('../vercel.json', import.meta.url), 'utf8'));
  assert.equal(v.trailingSlash, true);
  assert.ok(v.redirects.some((r) => r.source.startsWith('/docs/privacy') && r.destination === '/privacy/' && r.permanent === true));
});

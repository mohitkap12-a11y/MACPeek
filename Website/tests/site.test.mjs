import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync, existsSync } from 'node:fs';
import { join } from 'node:path';

const dist = new URL('../dist/', import.meta.url).pathname;
assert.ok(existsSync(dist), 'run `npm run build` first');

const pages = [];
(function walk(d) {
  for (const f of readdirSync(d)) {
    const p = join(d, f);
    statSync(p).isDirectory() ? walk(p) : f === 'index.html' && pages.push(p);
  }
})(dist);

const html = (p) => readFileSync(p, 'utf8');

test('has expected pages', () => {
  for (const r of ['', 'docs/installation', 'docs/usage', 'docs/ports', 'docs/killing-processes', 'docs/permissions', 'docs/privacy', 'docs/troubleshooting',
    'blog/how-to-find-what-is-using-a-port-on-mac', 'blog/how-to-kill-a-process-on-a-port-on-mac', 'blog/how-to-free-port-3000-on-mac',
    'blog/lsof-mac-find-process-by-port', 'blog/mac-port-manager', 'blog/mac-port-monitor']) {
    assert.ok(existsSync(join(dist, r, 'index.html')), `missing /${r}`);
  }
});

test('every page: one h1, title, description, canonical, og tags, lang', () => {
  for (const p of pages.filter((p) => !p.includes('/404/'))) {
    const h = html(p);
    assert.equal((h.match(/<h1[\s>]/g) || []).length, 1, `${p}: h1 count`);
    assert.match(h, /<title>[^<]{10,}<\/title>/, `${p}: title`);
    assert.match(h, /<meta name="description" content="[^"]{50,}"/, `${p}: description`);
    assert.match(h, /<link rel="canonical" href="https?:\/\/[^"]+\/"/, `${p}: canonical`);
    assert.match(h, /property="og:title"/, `${p}: og:title`);
    assert.match(h, /name="twitter:card"/, `${p}: twitter`);
    assert.match(h, /<html lang="en"/, `${p}: lang`);
  }
});

test('no third-party scripts or trackers', () => {
  for (const p of pages) assert.doesNotMatch(html(p), /<script[^>]+src=/i, `${p}: external script`);
});

test('homepage has download + GitHub CTAs and JSON-LD', () => {
  const h = html(join(dist, 'index.html'));
  assert.match(h, /Download for macOS/);
  assert.match(h, /View on GitHub/);
  assert.match(h, /SoftwareApplication/);
  assert.match(h, /Kill it in one click/);
});

test('JSON-LD parses', () => {
  for (const p of pages) {
    for (const m of html(p).matchAll(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/g)) JSON.parse(m[1]);
  }
});

test('sitemap and robots', () => {
  assert.ok(existsSync(join(dist, 'sitemap-index.xml')));
  const sm = readFileSync(join(dist, 'sitemap-0.xml'), 'utf8');
  assert.match(sm, /\/docs\/privacy\//);
  assert.match(sm, /how-to-free-port-3000-on-mac/);
  assert.match(readFileSync(join(dist, 'robots.txt'), 'utf8'), /Sitemap: .*sitemap-index\.xml/);
});

test('internal links resolve', () => {
  for (const p of pages) {
    for (const m of html(p).matchAll(/href="(\/[^"#]*)(#[^"]*)?"/g)) {
      const target = m[1];
      if (/\.[a-z0-9]+$/i.test(target)) continue; // static assets
      assert.ok(existsSync(join(dist, target, 'index.html')), `${p}: broken link ${target}`);
    }
  }
});

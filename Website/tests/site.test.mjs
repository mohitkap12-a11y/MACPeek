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

const isRedirect = (p) => /http-equiv="refresh"/i.test(html(p));
const content = () => pages.filter((p) => !p.includes('/404/') && !isRedirect(p));

const UTILS = ['portpeek', 'displaypeek', 'usbpeek', 'netpeek', 'batterypeek', 'sleeppeek', 'filelockpeek', 'processpeek', 'diskpeek', 'envpeek', 'dnspeek'];
const COMING_SOON = UTILS.filter((u) => u !== 'portpeek');

test('has expected pages', () => {
  const routes = ['', 'utilities', 'download', 'privacy', 'security',
    ...UTILS.map((u) => `utilities/${u}`),
    ...['installation', 'usage', 'managing-utilities', 'ports', 'killing-processes', 'permissions', 'troubleshooting'].map((d) => `docs/${d}`),
    ...['how-to-find-what-is-using-a-port-on-mac', 'how-to-kill-a-process-on-a-port-on-mac', 'how-to-free-port-3000-on-mac', 'lsof-mac-find-process-by-port',
      'mac-port-manager', 'mac-port-monitor', 'how-to-check-monitor-refresh-rate-on-mac', 'how-to-see-usb-devices-on-mac', 'why-wont-my-mac-go-to-sleep',
      'how-to-check-macbook-battery-health', 'how-to-check-wifi-signal-strength-on-mac'].map((b) => `blog/${b}`)];
  for (const r of routes) assert.ok(existsSync(join(dist, r, 'index.html')), `missing /${r}`);
  assert.ok(isRedirect(join(dist, 'docs/privacy/index.html')), '/docs/privacy/ should redirect to /privacy/');
});

test('every page: one h1, title, description, canonical, og tags, lang', () => {
  for (const p of content()) {
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

test('titles and descriptions are unique and a sensible length', () => {
  const titles = new Map(), descs = new Map();
  for (const p of content()) {
    const h = html(p);
    const t = h.match(/<title>([^<]*)<\/title>/)[1];
    const d = h.match(/<meta name="description" content="([^"]*)"/)[1];
    assert.ok(t.length <= 80, `${p}: title too long (${t.length}): ${t}`);
    assert.ok(d.length >= 70 && d.length <= 180, `${p}: description length ${d.length}`);
    assert.ok(!titles.has(t), `${p}: duplicate title with ${titles.get(t)}`); titles.set(t, p);
    assert.ok(!descs.has(d), `${p}: duplicate description with ${descs.get(d)}`); descs.set(d, p);
  }
});

test('brand: MacPeek everywhere, no stale PortPeek-as-the-product wording', () => {
  for (const p of content()) {
    const h = html(p);
    assert.match(h, /<a class="brand"[^>]*>[\s\S]*?MacPeek/, `${p}: brand`);
    assert.doesNotMatch(h, /PortPeek-\d|PortPeek-x\.y\.z|PortPeek\.dmg|app\.portpeek|mohitkap12-a11y\/PortPeek\b/, `${p}: stale PortPeek artifact name`);
  }
});

test('404 page is on-brand', () => {
  const h = html(join(dist, '404.html'));
  assert.match(h, /<title>Page not found \| MacPeek<\/title>/);
  assert.match(h, /Back to MacPeek/);
  assert.doesNotMatch(h, /PortPeek/, '404 must not use the old brand');
});

test('no page links to the GitHub latest-release URL while no release exists', () => {
  const site = readFileSync(new URL('../src/site.ts', import.meta.url), 'utf8');
  const hasRelease = /hasRelease: true/.test(site);
  if (hasRelease) return;
  for (const p of content()) assert.doesNotMatch(html(p), /releases\/latest/, `${p}: links to a release that does not exist yet`);
});

test('network wording: utilities that make network requests never claim "no network access"', () => {
  for (const u of ['netpeek', 'dnspeek']) {
    const h = html(join(dist, 'utilities', u, 'index.html'));
    assert.doesNotMatch(h, /no network access/i, `${u}: contradicts its own description`);
    assert.match(h, /only when you ask/i, `${u}: must say checks run only on request`);
  }
});

test('every utility page has the sections the guide requires', () => {
  for (const u of UTILS) {
    const h = html(join(dist, 'utilities', u, 'index.html'));
    for (const s of ['The problem', 'The solution', 'How it works', 'Installation', 'Privacy', 'Open source']) assert.match(h, new RegExp(`<h2[^>]*>${s}`), `${u}: missing "${s}"`);
    assert.match(h, /class="(mock|shot)/, `${u}: missing screen/preview`);
    assert.match(h, /BreadcrumbList/, `${u}: breadcrumbs`);
  }
});

test('honesty: unreleased utilities say Coming soon; only PortPeek claims Available', () => {
  for (const u of COMING_SOON) {
    const h = html(join(dist, 'utilities', u, 'index.html'));
    assert.match(h, /Coming soon/, `${u}: must say Coming soon`);
    assert.doesNotMatch(h, /Available now|Ready · first release/, `${u}: must not claim availability`);
    assert.match(h, /not (part of|released|available)/i, `${u}: must say it is not released yet`);
  }
  const pp = html(join(dist, 'utilities', 'portpeek', 'index.html'));
  assert.match(pp, /Available now|Ready · first release pending/);
  assert.doesNotMatch(pp, /Coming soon/);
});

test('guides for unreleased utilities do not pitch a download', () => {
  for (const g of ['how-to-check-monitor-refresh-rate-on-mac', 'how-to-see-usb-devices-on-mac', 'why-wont-my-mac-go-to-sleep', 'how-to-check-macbook-battery-health', 'how-to-check-wifi-signal-strength-on-mac']) {
    const h = html(join(dist, 'blog', g, 'index.html'));
    assert.match(h, /is coming to MacPeek/, `${g}: must say the utility is coming`);
    assert.doesNotMatch(h, /Download MacPeek/, `${g}: must not pitch a download for an unreleased utility`);
  }
});

test('download buttons never point at a missing release', () => {
  // While no release exists, the buttons go to /download/ (which explains), not to releases/latest (a 404).
  const home = html(join(dist, 'index.html'));
  const noRelease = /first signed release has not been published/.test(html(join(dist, 'download', 'index.html')));
  if (noRelease) assert.match(home, /class="btn primary" href="\/download\/"/);
});

test('no third-party scripts or trackers', () => {
  for (const p of pages) assert.doesNotMatch(html(p), /<script[^>]+src=/i, `${p}: external script`);
});

test('homepage has download + GitHub CTAs and JSON-LD', () => {
  const h = html(join(dist, 'index.html'));
  assert.match(h, /Download MacPeek/);
  assert.match(h, /View on GitHub/);
  assert.match(h, /SoftwareApplication/);
  assert.match(h, /tiny utilities/);
  for (const u of UTILS) assert.match(h, new RegExp(`href="/utilities/${u}/"`), `home must link to ${u}`);
});

test('JSON-LD parses', () => {
  for (const p of pages) {
    for (const m of html(p).matchAll(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/g)) JSON.parse(m[1]);
  }
});

test('sitemap and robots', () => {
  assert.ok(existsSync(join(dist, 'sitemap-index.xml')));
  const sm = readFileSync(join(dist, 'sitemap-0.xml'), 'utf8');
  assert.match(sm, /\/privacy\//);
  assert.match(sm, /\/utilities\/displaypeek\//);
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

test('dark by default with a light/dark switch on every page', () => {
  for (const p of content()) {
    const h = html(p);
    assert.match(h, /<html lang="en" data-theme="dark"/, `${p}: must default to dark`);
    assert.match(h, /id="theme-toggle"/, `${p}: theme switch missing`);
    assert.match(h, /localStorage\.getItem\('portpeek-theme'\)/, `${p}: persisted theme not restored`);
  }
});

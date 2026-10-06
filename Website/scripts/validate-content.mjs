// Fails the build when SEO basics regress: every markdown page needs a unique, well-sized
// title and description, and the shared layout.
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';

const root = new URL('../src/pages/', import.meta.url).pathname;
const files = [];
(function walk(d) {
  for (const f of readdirSync(d)) {
    const p = join(d, f);
    statSync(p).isDirectory() ? walk(p) : p.endsWith('.md') && files.push(p);
  }
})(root);

const titles = new Map(), descs = new Map();
const errors = [];
for (const f of files) {
  const m = readFileSync(f, 'utf8').match(/^---\n([\s\S]*?)\n---/);
  if (!m) { errors.push(`${f}: no frontmatter`); continue; }
  const get = (k) => (m[1].match(new RegExp(`^${k}: "(.*)"$`, 'm')) || [])[1];
  const [title, description, h1] = [get('title'), get('description'), get('h1')];
  if (!title || title.length > 70) errors.push(`${f}: title missing or >70 chars (${title?.length})`);
  if (!description || description.length < 70 || description.length > 175) errors.push(`${f}: description length ${description?.length} not in 70–175`);
  if (!h1) errors.push(`${f}: missing h1`);
  if (titles.has(title)) errors.push(`${f}: duplicate title with ${titles.get(title)}`); titles.set(title, f);
  if (descs.has(description)) errors.push(`${f}: duplicate description with ${descs.get(description)}`); descs.set(description, f);
}
if (errors.length) { console.error(errors.join('\n')); process.exit(1); }
console.log(`content OK (${files.length} markdown pages)`);

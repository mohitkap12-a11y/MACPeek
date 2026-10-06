import type { APIRoute } from 'astro';
import { SITE } from '../site';
import { utilities } from '../data/utilities';

// The full text of every utility page in one file, for assistants that prefer a single fetch.
export const GET: APIRoute = ({ site }) => {
  const out = [`# ${SITE.name}: utilities`, '', `> ${SITE.description}`, ''];
  for (const u of utilities) {
    const live = u.status === 'available';
    out.push(
      `## ${u.name}${live ? '' : ' (coming soon, not released)'}`,
      `URL: ${new URL(`/utilities/${u.id}/`, site)}`,
      `Question it answers: ${u.question}`,
      '',
      `The problem: ${u.problem}`,
      '',
      `The solution: ${u.solution}`,
      '',
      `${live ? 'Features' : 'Planned features'}:`,
      ...u.features.map((f) => `- ${f}`),
      '',
      'How it works:',
      ...u.how.map((h, i) => `${i + 1}. ${h}`),
      '',
      `${live ? 'Reads' : 'Will read'} (locally):`,
      ...u.reads.map((r) => `- ${r}`),
      `Access needed: ${u.access}`,
      '',
    );
  }
  return new Response(out.join('\n'), { headers: { 'Content-Type': 'text/plain; charset=utf-8' } });
};

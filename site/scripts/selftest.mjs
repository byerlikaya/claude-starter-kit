// The generator's own tests, on a scratch copy of the repository: nothing here touches the real tree. Each case is
// a must-change or must-fail twin for a promise the site makes (5S §4.2):
//   1 a new agent and a new skill appear on their pages, and every count the pages quote moves with them
//   2 a skill with no Turkish line turns the build red (the site never falls back to English)
//   3 a page with no Turkish file turns the build red
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { generate } from './generate.mjs';
import { BuildError } from './lib.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const REPO = path.resolve(here, '../..');
const INPUTS = ['kit/agents', 'kit/skills', 'kit/hooks', 'kit/eval', 'kit/CLAUDE.md', 'packaging', 'site/content', 'assets',
  'evals/README.md', 'CHANGELOG.md', 'README.md', 'README.tr.md'];

function scratch() {
  const d = fs.mkdtempSync(path.join(os.tmpdir(), 'crew-site-selftest-'));
  for (const p of INPUTS) fs.cpSync(path.join(REPO, p), path.join(d, 'repo', p), { recursive: true });
  fs.mkdirSync(path.join(d, 'site'));
  return { root: path.join(d, 'repo'), site: path.join(d, 'site'), done: () => fs.rmSync(d, { recursive: true, force: true }) };
}
const page = (s, rel) => fs.readFileSync(path.join(s.site, 'src/content/docs', rel), 'utf8');
const results = [];
const check = (name, ok, detail) => { results.push({ name, ok, detail }); };
function expectFail(name, s, pattern) {
  try { generate(s.root, s.site); check(name, false, 'the build passed'); }
  catch (e) { check(name, e instanceof BuildError && pattern.test(e.message), e.message.split('\n')[0]); }
}

// 1 · add one agent and one skill (with their Turkish lines), bump the diagram subtitles as the generator would ask.
{
  const s = scratch();
  try {
    const base = generate(s.root, s.site);
    fs.writeFileSync(path.join(s.root, 'kit/agents/crew-zz-probe.md'), '---\nname: crew-zz-probe\ndescription: |\n  Probe agent added by the site self-test. Owns nothing.\n---\n\nBody.\n');
    fs.mkdirSync(path.join(s.root, 'kit/skills/zz-probe'));
    fs.writeFileSync(path.join(s.root, 'kit/skills/zz-probe/SKILL.md'), '---\nname: zz-probe\ndescription: |\n  Probe skill added by the site self-test. Does nothing.\n---\n\nBody.\n');
    fs.appendFileSync(path.join(s.root, 'packaging/agent-summaries.tr.tsv'), 'crew-zz-probe\tSelf-test ajanı.\n');
    fs.appendFileSync(path.join(s.root, 'packaging/skill-summaries.tr.tsv'), 'zz-probe\tSelf-test skill.\n');
    for (const n of ['network-en', 'network-tr']) {
      const f = path.join(s.root, 'assets', `${n}.svg`);
      fs.writeFileSync(f, fs.readFileSync(f, 'utf8').replace(/(\d+)( AGENTS| AJAN)/, (m, a, b) => `${Number(a) + 1}${b}`).replace(/(\d+)( SKILLS?)/, (m, a, b) => `${Number(a) + 1}${b}`));
    }
    const after = generate(s.root, s.site);
    const skillsEn = page(s, 'skills.md'); const gatesTr = page(s, 'tr/gates.md');
    check('a new agent and skill show up, and the counts move',
      after.agents === base.agents + 1 && after.skills === base.skills + 1
        && page(s, 'agents.md').includes('`crew-zz-probe`') && page(s, 'tr/agents.md').includes('Self-test ajanı.')
        && skillsEn.includes('`zz-probe`') && skillsEn.includes(`All ${base.skills + 1} skills`)
        && skillsEn.includes(`${base.agents + 1} specialist agents`) && gatesTr.includes(`| **Skill** | ${base.skills + 1} |`),
      `agents ${base.agents} → ${after.agents}, skills ${base.skills} → ${after.skills}`);
  } finally { s.done(); }
}
// 2 · a skill whose Turkish line is gone.
{
  const s = scratch();
  try {
    const f = path.join(s.root, 'packaging/skill-summaries.tr.tsv');
    fs.writeFileSync(f, fs.readFileSync(f, 'utf8').split('\n').filter((l) => !l.startsWith('adr\t')).join('\n'));
    expectFail('a skill with no Turkish line fails the build', s, /skill-summaries\.tr\.tsv: adr/);
  } finally { s.done(); }
}
// 3 · a page whose Turkish file is gone.
{
  const s = scratch();
  try {
    fs.rmSync(path.join(s.root, 'site/content/tr/studio.md'));
    expectFail('a page with no Turkish file fails the build', s, /site\/content\/tr\/studio\.md is missing/);
  } finally { s.done(); }
}

for (const r of results) console.log(`${r.ok ? 'PASS' : 'FAIL'}  ${r.name} — ${r.detail}`);
if (results.some((r) => !r.ok)) process.exit(1);
console.log(`site selftest: ${results.length}/${results.length} generator twins behaved`);

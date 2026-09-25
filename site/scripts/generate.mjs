// Builds the site's pages from the repository, once per build. Nothing it writes is edited by hand: the output
// (src/content/docs, src/assets, public) is gitignored and rebuilt every time.
//
// Sources, and why each is read rather than copied:
//   site/content/{en,tr}/*.md   the documentation pages (moved out of the READMEs in 5R); text is used as written
//   kit/agents, kit/skills      the agents, the skill catalogue and the commands — a view of the payload
//   packaging/*.tr.tsv          the Turkish summaries; a missing line FAILS the build instead of showing English
//   kit/eval/gate-report.sh     the rule inventory, which it derives from the hooks
//   kit/hooks/session-guard.sh  the context-fill thresholds the pages quote
//   evals/README.md, CHANGELOG.md, README*.md   the measuring page, the changelog and the home page
//
// Usage: node scripts/generate.mjs [--root <repo>] [--out <site dir>]   (the self-test points both at copies)
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  LOCALES, BuildError, fail, read, cell, tsv, agents, skillsAndCommands, fillThresholds, gateRules, checkNetworkSvgs, alwaysOn,
} from './lib.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const arg = (k, d) => { const i = process.argv.indexOf(k); return i > 0 ? path.resolve(process.argv[i + 1]) : d; };
const ROOT = arg('--root', path.resolve(here, '../..'));
const SITE = arg('--out', path.resolve(here, '..'));
const REPO_URL = 'https://github.com/Crewforth/crewforth';

// The documentation pages that come from site/content. Every one must exist in every locale.
const CONTENT = ['install', 'gates', 'skills', 'studio', 'sessions-and-cost', 'verification', 'extending'];

const UI = {
  en: {
    agents: { title: 'Agents', lead: 'The {n} specialist agents, each read from its own definition when the site is built, so this list is always the one that installs.', col: ['Agent', 'What it owns'] },
    commands: { title: 'Commands', lead: 'The {n} slash commands, each read from its own definition when the site is built.', col: ['Command', 'What it does', 'Who runs it'], user: 'you', both: 'you or Claude' },
    catalogue: ['Skill', 'What it does'],
    rules: { heading: 'Enforced rules ({n})', lead: 'Read from the hooks when the site is built — the same inventory `gate-report.sh` derives — so a rule added to a hook appears here without anyone editing this page.', col: 'Rule' },
    measuring: { title: 'How we measure', note: '' },
    changelog: { title: 'Changelog', note: '' },
    homeQuick: '## Quick start',
  },
  tr: {
    agents: { title: 'Ajanlar', lead: '{n} uzman ajan; her biri site derlenirken kendi tanım dosyasından okunur, yani bu liste her zaman kurulan listedir.', col: ['Ajan', 'Sahip olduğu alan'] },
    commands: { title: 'Komutlar', lead: '{n} slash komutu; her biri site derlenirken kendi tanım dosyasından okunur.', col: ['Komut', 'Ne yapar', 'Kim çalıştırır'], user: 'siz', both: 'siz ya da Claude' },
    catalogue: ['Skill', 'Ne yapar'],
    rules: { heading: 'Uygulanan kurallar ({n})', lead: "Site derlenirken hook'lardan okunur (`gate-report.sh`'in türettiği envanterin aynısı); bir hook'a eklenen kural, bu sayfayı kimse düzenlemeden burada görünür.", col: 'Kural' },
    measuring: { title: 'Nasıl ölçüyoruz', note: "> Bu sayfa İngilizce kaynağından, `evals/README.md`'den derlenir. Ölçüm kayıtları tek bir yerde tutulur; ikinci bir kopyası yoktur.\n\n" },
    changelog: { title: 'Değişiklik günlüğü', note: "> Bu sayfa İngilizce kaynağından, `CHANGELOG.md`'den derlenir. Günlük bir tarih kaydıdır; her sürüm yayımlandığı adla anılır.\n\n" },
    homeQuick: '## Hızlı başlangıç',
  },
};

// Bytes → tokens at the one measured ratio: a real `claude -p` turn in which 21,804 bytes of the same always-on
// material cost 9,198 tokens (quoted on the page itself). Formatted the way each language writes numbers.
const RATIO = 9198 / 21804;
function costFacts(loc, c) {
  const n = (x) => x.toLocaleString(loc === 'en' ? 'en-US' : 'tr-TR');
  const k = (b) => { const v = (b * RATIO / 1000).toFixed(1); return loc === 'en' ? `${v}k` : `${v.replace('.', ',')} bin`; };
  return {
    ALWAYS_ON_BYTES: n(c.total), ALWAYS_ON_TOKENS: k(c.total),
    DESC_BYTES: n(c.descriptions), DESC_TOKENS: k(c.descriptions),
    UI_BYTES: n(c.ui), UI_TOKENS: String(Math.round(c.ui * RATIO / 10) * 10),
  };
}

const prefix = (loc) => (loc === 'en' ? '' : `/${loc}`);
const yaml = (s) => JSON.stringify(String(s));

function descriptionOf(body) {
  for (const para of body.split(/\n\s*\n/)) {
    const p = para.trim();
    if (!p || /^[<|#`!>\-*\d]/.test(p) || p.startsWith('[')) continue;
    const plain = p.replace(/\[([^\]]+)\]\([^)]+\)/g, '$1').replace(/[`*]/g, '').replace(/\s+/g, ' ').trim();
    if (plain.length <= 160) return plain;
    const cut = plain.slice(0, 157); return cut.slice(0, cut.lastIndexOf(' ')) + '…';
  }
  fail('no prose paragraph to describe the page');
}

// Rewrites the GitHub-relative paths the site/content pages carry (they are written to render on GitHub too).
function relink(text, loc, base) {
  return text
    .replace(/(\]\(|src=")\.\.\/\.\.\/\.\.\/assets\//g, '$1/assets/')
    .replace(/\]\(\.\.\/\.\.\/\.\.\/evals\/README\.md\)/g, `](${prefix(loc)}/measuring/)`)
    .replace(/\]\(\.\.\/\.\.\/\.\.\/([^)]+)\)/g, `](${REPO_URL}/blob/main/$1)`)
    .replace(/\]\((?!https?:|mailto:|#|\/)([^)]+)\)/g, (m, p) => `](${REPO_URL}/blob/main/${path.posix.join(base, p)})`);
}

function page(file, fm, body) {
  const head = Object.entries(fm).map(([k, v]) => (typeof v === 'object' ? `${k}:\n${Object.entries(v).map(([a, b]) => `  ${a}: ${yaml(b)}`).join('\n')}` : `${k}: ${typeof v === 'string' ? yaml(v) : v}`)).join('\n');
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, `---\n${head}\n---\n\n${body.trim()}\n`);
}

export function generate(root = ROOT, site = SITE) {
  const docs = path.join(site, 'src/content/docs');
  for (const d of [docs, path.join(site, 'src/assets'), path.join(site, 'public')]) fs.rmSync(d, { recursive: true, force: true });

  const ag = agents(root);
  const { skills, commands } = skillsAndCommands(root);
  const fill = fillThresholds(root);
  const rules = gateRules(root);
  const cost = alwaysOn(root);
  checkNetworkSvgs(root, ag.length, skills.length);

  const tr = {
    agents: tsv(path.join(root, 'packaging/agent-summaries.tr.tsv')),
    commands: tsv(path.join(root, 'packaging/command-summaries.tr.tsv')),
    skills: tsv(path.join(root, 'packaging/skill-summaries.tr.tsv')),
    rules: tsv(path.join(root, 'packaging/gate-rules.tr.tsv')),
  };
  const missing = [
    ...ag.filter((a) => !tr.agents.has(a.name)).map((a) => `agent-summaries.tr.tsv: ${a.name}`),
    ...commands.filter((c) => !tr.commands.has(c.name)).map((c) => `command-summaries.tr.tsv: ${c.name}`),
    ...skills.filter((s) => !tr.skills.has(s.name)).map((s) => `skill-summaries.tr.tsv: ${s.name}`),
    ...rules.filter((r) => !tr.rules.has(r)).map((r) => `gate-rules.tr.tsv: ${r}`),
  ];
  if (missing.length) fail(`no Turkish line for ${missing.length} item(s) — add them, the site never falls back to English:\n  ${missing.join('\n  ')}`);

  const summary = (loc, kind, item) => (loc === 'en' ? item.summary : tr[kind].get(item.name));

  for (const loc of LOCALES) {
    const out = loc === 'en' ? docs : path.join(docs, loc);
    const u = UI[loc];

    // Documentation pages from site/content.
    for (const slug of CONTENT) {
      const src = path.join(root, 'site/content', loc, `${slug}.md`);
      if (!fs.existsSync(src)) fail(`site/content/${loc}/${slug}.md is missing — every page exists in every language`);
      let text = read(src);
      const h1 = text.match(/^# (.+)\n/);
      if (!h1) fail(`site/content/${loc}/${slug}.md has no H1 to take the title from`);
      text = text.slice(h1[0].length);
      text = text.replaceAll('{{FILL_WARN}}', String(fill.warn)).replaceAll('{{FILL_ALERT}}', String(fill.alert));
      for (const [k, v] of Object.entries(costFacts(loc, cost))) text = text.replaceAll(`{{${k}}}`, v);
      const counts = { AGENT_COUNT: ag.length, SKILL_COUNT: skills.length, COMMAND_COUNT: commands.length };
      for (const [k, v] of Object.entries(counts)) text = text.replaceAll(`{{${k}}}`, String(v));
      if (/\{\{[A-Z_]+\}\}/.test(text)) fail(`site/content/${loc}/${slug}.md: an unknown placeholder ${text.match(/\{\{[A-Z_]+\}\}/)[0]}`);
      if (slug === 'skills') {
        if (!text.includes('<!-- CATALOGUE -->')) fail(`site/content/${loc}/skills.md: the <!-- CATALOGUE --> marker is gone`);
        const rows = skills.map((s) => `| \`${s.name}\` | ${cell(summary(loc, 'skills', s))} |`).join('\n');
        text = text.replace('<!-- CATALOGUE -->', `| ${u.catalogue[0]} | ${u.catalogue[1]} |\n|:--|:--|\n${rows}`);
      }
      if (slug === 'gates') {
        const rows = rules.map((r) => `| ${cell(loc === 'en' ? r : tr.rules.get(r))} |`).join('\n');
        text += `\n\n## ${u.rules.heading.replace('{n}', rules.length)}\n\n${u.rules.lead}\n\n| ${u.rules.col} |\n|:--|\n${rows}\n`;
      }
      text = relink(text, loc, 'site/content/' + loc);
      page(path.join(out, `${slug}.md`), { title: h1[1].trim(), description: descriptionOf(text) }, text);
    }

    // Generated pages: agents and commands.
    const agentRows = ag.map((a) => `| \`${a.name}\` | ${cell(summary(loc, 'agents', a))} |`).join('\n');
    const agentLead = u.agents.lead.replace('{n}', ag.length);
    page(path.join(out, 'agents.md'), { title: u.agents.title, description: agentLead },
      `${agentLead}\n\n| ${u.agents.col[0]} | ${u.agents.col[1]} |\n|:--|:--|\n${agentRows}`);
    const cmdRows = commands.map((c) => `| \`/${c.name}\` | ${cell(summary(loc, 'commands', c))} | ${c.userOnly ? u.commands.user : u.commands.both} |`).join('\n');
    const cmdLead = u.commands.lead.replace('{n}', commands.length);
    page(path.join(out, 'commands.md'), { title: u.commands.title, description: cmdLead },
      `${cmdLead}\n\n| ${u.commands.col[0]} | ${u.commands.col[1]} | ${u.commands.col[2]} |\n|:--|:--|:--|\n${cmdRows}`);

    // The measuring page and the changelog, compiled from their one source each.
    for (const [slug, file, base] of [['measuring', 'evals/README.md', 'evals'], ['changelog', 'CHANGELOG.md', '']]) {
      let text = read(path.join(root, file)).replace(/^# .+\n/, '');
      text = relink(text, loc, base);
      page(path.join(out, `${slug}.md`), { title: u[slug].title, description: descriptionOf(text) }, u[slug].note + text);
    }

    // Home: the README's own opening, nothing added — the definition, the search terms, the panel GIF, the quick start.
    const readme = read(path.join(root, loc === 'en' ? 'README.md' : `README.${loc}.md`));
    const def = (readme.match(/^\*\*(Crewforth[^*]+)\*\*$/m) || [])[1];
    const keys = (readme.match(new RegExp(`^\\*\\*${def?.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\*\\*\\n\\n([\\s\\S]+?)\\n\\n`, 'm')) || [])[1];
    const gif = (readme.match(/<img src="assets\/studio-flow\.gif" alt="([^"]+)"/) || [])[1];
    const qs = readme.split(u.homeQuick)[1]?.match(/```bash\n[\s\S]+?\n```/)?.[0];
    if (!def || !keys || !gif || !qs) fail(`README${loc === 'en' ? '' : '.' + loc}.md: the opening this home page is built from changed shape`);
    page(path.join(out, 'index.md'), { title: 'Crewforth', description: def, template: 'splash', hero: { tagline: def } },
      `${keys.replace(/<br>\s*/g, ' ')}\n\n<img src="/assets/studio-flow.gif" alt="${gif}" class="cf-hero-gif">\n\n${qs}`);
  }

  // Static files: the repository's assets, the logo pair, the favicon, the social card, robots.txt.
  fs.cpSync(path.join(root, 'assets'), path.join(site, 'public/assets'), { recursive: true });
  fs.mkdirSync(path.join(site, 'src/assets'), { recursive: true });
  for (const f of ['logo.svg', 'logo-light.svg']) fs.copyFileSync(path.join(root, 'assets', f), path.join(site, 'src/assets', f));
  fs.copyFileSync(path.join(root, 'assets/icon.svg'), path.join(site, 'public/favicon.svg'));
  fs.copyFileSync(path.join(root, 'assets/social-preview.png'), path.join(site, 'public/social-preview.png'));
  fs.writeFileSync(path.join(site, 'public/robots.txt'), 'User-agent: *\nAllow: /\n\nSitemap: https://crewforth.com/sitemap-index.xml\n');

  return { agents: ag.length, skills: skills.length, commands: commands.length, rules: rules.length, fill, cost };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const r = generate();
    console.log(`site: generated ${CONTENT.length + 5} pages × ${LOCALES.length} languages · ${r.agents} agents · ${r.skills} skills · ${r.commands} commands · ${r.rules} rules · fill ${r.fill.warn}/${r.fill.alert} · always-on ${r.cost.total} B (discipline ${r.cost.discipline}, agents ${r.cost.agents}, skills ${r.cost.skills})`);
  } catch (e) {
    if (e instanceof BuildError) { console.error(`site: ${e.message}`); process.exit(1); }
    throw e;
  }
}

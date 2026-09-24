// A small Markdown renderer for agent reports.
//
// Agents write Markdown — headings, tables, fenced code — and reading it raw
// wastes the structure they took the trouble to produce. This covers what they
// actually use rather than the whole spec.
//
// Everything is HTML-escaped first and only known constructs are re-introduced,
// so report text can never inject markup into the panel.

const ESC = { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' };
const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ESC[c]);

function inline(s) {
  return esc(s)
    .replace(/`([^`]+)`/g, '<code>$1</code>')
    .replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>')
    .replace(/(^|[\s(])\*([^*\s][^*]*)\*/g, '$1<em>$2</em>')
    .replace(/\[([^\]]+)\]\(([^)]+)\)/g, '<span class="md-link">$1</span>');
}

function tableRow(line) {
  return line.replace(/^\||\|$/g, '').split('|').map((c) => c.trim());
}

export function renderMarkdown(src) {
  if (!src) return '';
  const lines = String(src).split('\n');
  const out = [];
  let i = 0;
  let list = null; // 'ul' | 'ol'

  const closeList = () => { if (list) { out.push(`</${list}>`); list = null; } };

  while (i < lines.length) {
    const line = lines[i];

    // fenced code — taken verbatim, never re-parsed
    const fence = line.match(/^\s*```(\w*)\s*$/);
    if (fence) {
      closeList();
      const body = [];
      i += 1;
      while (i < lines.length && !/^\s*```\s*$/.test(lines[i])) { body.push(lines[i]); i += 1; }
      i += 1;
      out.push(`<pre class="md-code"><code>${esc(body.join('\n'))}</code></pre>`);
      continue;
    }

    // table: a header row followed by a separator of dashes
    if (/^\s*\|/.test(line) && i + 1 < lines.length && /^\s*\|[\s:|-]+\|?\s*$/.test(lines[i + 1])) {
      closeList();
      const head = tableRow(line);
      i += 2;
      const rows = [];
      while (i < lines.length && /^\s*\|/.test(lines[i])) { rows.push(tableRow(lines[i])); i += 1; }
      out.push(
        '<div class="md-tablewrap"><table class="md-table"><thead><tr>' +
        head.map((h) => `<th>${inline(h)}</th>`).join('') +
        '</tr></thead><tbody>' +
        rows.map((r) => `<tr>${r.map((c) => `<td>${inline(c)}</td>`).join('')}</tr>`).join('') +
        '</tbody></table></div>',
      );
      continue;
    }

    const h = line.match(/^(#{1,6})\s+(.*)$/);
    if (h) {
      closeList();
      const lvl = Math.min(6, h[1].length + 2); // report h1 is a section, not a page title
      out.push(`<h${lvl} class="md-h">${inline(h[2])}</h${lvl}>`);
      i += 1;
      continue;
    }

    if (/^\s*([-*_])\1{2,}\s*$/.test(line)) { closeList(); out.push('<hr class="md-hr">'); i += 1; continue; }

    const quote = line.match(/^\s*>\s?(.*)$/);
    if (quote) {
      closeList();
      const body = [quote[1]];
      i += 1;
      while (i < lines.length && /^\s*>\s?/.test(lines[i])) { body.push(lines[i].replace(/^\s*>\s?/, '')); i += 1; }
      out.push(`<blockquote class="md-quote">${inline(body.join(' '))}</blockquote>`);
      continue;
    }

    const ul = line.match(/^\s*[-*+]\s+(.*)$/);
    const ol = line.match(/^\s*\d+[.)]\s+(.*)$/);
    if (ul || ol) {
      const want = ul ? 'ul' : 'ol';
      if (list !== want) { closeList(); out.push(`<${want} class="md-list">`); list = want; }
      out.push(`<li>${inline((ul ?? ol)[1])}</li>`);
      i += 1;
      continue;
    }

    if (!line.trim()) { closeList(); i += 1; continue; }

    closeList();
    const para = [line];
    i += 1;
    while (i < lines.length && lines[i].trim() && !/^\s*(#{1,6}\s|[-*+]\s|\d+[.)]\s|>|\||```)/.test(lines[i])) {
      para.push(lines[i]); i += 1;
    }
    out.push(`<p class="md-p">${inline(para.join(' '))}</p>`);
  }

  closeList();
  return out.join('');
}

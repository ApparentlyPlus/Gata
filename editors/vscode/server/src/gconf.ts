import { Diagnostic, DiagnosticSeverity } from 'vscode-languageserver/node';
import { TextDocument } from 'vscode-languageserver-textdocument';

const SCHEMA: ReadonlyMap<string, readonly string[]> = new Map([
  ['ProjectName', []],
  ['TargetBackend', ['GatOS', 'Hosted']],
  ['BuildMode', ['Debug', 'Release']],
  ['OutputType', ['Framebuffer', 'Serial']],
  ['KeyboardSupport', ['Default', 'External', 'Hotplug']],
  ['CapabilityDiscovery', ['On', 'Off']],
]);

function distance(a: string, b: string): number {
  const prev = new Array<number>(b.length + 1);
  const cur = new Array<number>(b.length + 1);
  for (let j = 0; j <= b.length; j++) prev[j] = j;
  for (let i = 1; i <= a.length; i++) {
    cur[0] = i;
    for (let j = 1; j <= b.length; j++) {
      const cost = a[i - 1].toLowerCase() === b[j - 1].toLowerCase() ? 0 : 1;
      cur[j] = Math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost);
    }
    for (let j = 0; j <= b.length; j++) prev[j] = cur[j];
  }
  return prev[b.length];
}

function closest(typed: string, candidates: readonly string[]): string | undefined {
  let best: string | undefined;
  let bestDist = Number.MAX_SAFE_INTEGER;
  const maxAllowed = Math.max(1, Math.floor(typed.length / 2));
  for (const c of candidates) {
    if (Math.abs(c.length - typed.length) > maxAllowed) continue;
    const d = distance(typed, c);
    if (d < bestDist) { bestDist = d; best = c; }
  }
  return bestDist <= maxAllowed ? best : undefined;
}

function mask(text: string): string {
  const blank = (m: string) => m.replace(/[^\n]/g, ' ');
  return text
    .replace(/<!--[\s\S]*?-->/g, blank)
    .replace(/<!\[CDATA\[[\s\S]*?\]\]>/g, blank);
}

function diag(
  doc: TextDocument,
  start: number,
  length: number,
  message: string,
  severity: DiagnosticSeverity,
  hint?: string,
): Diagnostic {
  return {
    severity,
    range: { start: doc.positionAt(start), end: doc.positionAt(start + Math.max(1, length)) },
    message: hint ? `${message}\nhelp: ${hint}` : message,
    source: 'gconf',
  };
}

export function validateGconf(doc: TextDocument): Diagnostic[] {
  const raw = doc.getText();
  const text = mask(raw);
  const out: Diagnostic[] = [];

  if (text.trim().length === 0) {
    return [diag(doc, 0, 1, 'this manifest is empty', DiagnosticSeverity.Error,
      'a .gconf needs at least an <appa> root element')];
  }

  // Root element: the first non-declaration, non-comment tag in the document.
  const rootMatch = /<\s*([A-Za-z_][\w.-]*)/.exec(text.replace(/<\?[\s\S]*?\?>/g, (m) => m.replace(/[^\n]/g, ' ')));
  if (!rootMatch) {
    return [diag(doc, 0, 1, 'no XML elements found', DiagnosticSeverity.Error,
      'a .gconf needs an <appa> root element')];
  }
  if (rootMatch[1] !== 'appa') {
    out.push(diag(doc, rootMatch.index, rootMatch[0].length,
      `a manifest must have an <appa> root, got <${rootMatch[1]}>`, DiagnosticSeverity.Error));
  }

  const seen = new Map<string, number>();
  const leaf = /<\s*([A-Za-z_][\w.-]*)\s*>([^<]*)<\s*\/\s*\1\s*>/g;
  let m: RegExpExecArray | null;
  while ((m = leaf.exec(text)) !== null) {
    const [full, name, rawValue] = m;
    if (name === 'appa') continue;

    const nameStart = m.index + full.indexOf(name);
    const allowed = SCHEMA.get(name);

    if (allowed === undefined) {
      const near = closest(name, [...SCHEMA.keys()]);
      out.push(diag(doc, nameStart, name.length,
        `unknown manifest element <${name}>`, DiagnosticSeverity.Warning,
        near ? `did you mean <${near}>?` : `appa reads: ${[...SCHEMA.keys()].join(', ')}`));
      continue;
    }

    const prev = seen.get(name);
    if (prev !== undefined) {
      out.push(diag(doc, nameStart, name.length,
        `<${name}> is set more than once`, DiagnosticSeverity.Warning,
        'appa reads the first occurrence; remove the duplicate'));
    }
    seen.set(name, nameStart);

    const value = rawValue.trim();
    if (allowed.length === 0) {
      if (value.length === 0) {
        out.push(diag(doc, nameStart, name.length,
          `<${name}> is empty`, DiagnosticSeverity.Warning,
          'appa falls back to the directory name'));
      }
      continue;
    }

    const match = allowed.find((a) => a.toLowerCase() === value.toLowerCase());
    if (match === undefined) {
      const valueStart = m.index + full.indexOf('>') + 1 + rawValue.indexOf(value.length ? value : rawValue);
      const near = closest(value, allowed);
      out.push(diag(doc, value.length ? valueStart : nameStart, Math.max(1, value.length),
        `'${value}' is not a valid <${name}> value`, DiagnosticSeverity.Error,
        near ? `did you mean '${near}'?` : `accepted: ${allowed.join(', ')}`));
    } else if (match !== value) {
      out.push(diag(doc, m.index + full.indexOf('>') + 1 + rawValue.indexOf(value), value.length,
        `'${value}' works but is spelled unusually`, DiagnosticSeverity.Hint,
        `appa's own spelling is '${match}'`));
    }
  }

  return out;
}

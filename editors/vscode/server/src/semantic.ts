import { execFile } from 'child_process';
import * as fs from 'fs';
import * as path from 'path';
import { Diagnostic, DiagnosticSeverity } from 'vscode-languageserver/node';

export interface GataSettings {
  appaPath?: string;
  libgataPath?: string;
  enableSemanticChecks: boolean;
}

export const defaultSettings: GataSettings = { enableSemanticChecks: true };

const ANSI = /\x1b\[[0-9;]*m/g;
const HEADER_WITH_SPAN = /^(.*?):(\d+):(\d+): (error|warning)\[(G\d+)\]: (.*)$/;
const HEADER_NO_SPAN = /^(.*?): (error|warning)\[(G\d+)\]: (.*)$/;
const HELP_LINE = /^\s*=\s*help:\s*(.*)$/;

function findGconf(startDir: string): string | undefined {
  let dir = startDir;
  for (let i = 0; i < 64; i++) {
    let entries: string[];
    try { entries = fs.readdirSync(dir); } catch { return undefined; }
    const gconf = entries.find((f) => f.toLowerCase().endsWith('.gconf'));
    if (gconf) return path.join(dir, gconf);
    const parent = path.dirname(dir);
    if (parent === dir) return undefined;
    dir = parent;
  }
  return undefined;
}

function findUpward(startDir: string, predicate: (dir: string) => string | undefined): string | undefined {
  let dir = startDir;
  for (let i = 0; i < 12; i++) {
    const found = predicate(dir);
    if (found) return found;
    const parent = path.dirname(dir);
    if (parent === dir) return undefined;
    dir = parent;
  }
  return undefined;
}

function detectAppaDll(startDir: string): string | undefined {
  return findUpward(startDir, (dir) => {
    for (const config of ['Debug', 'Release']) {
      const candidate = path.join(dir, 'Appa', 'bin', config, 'net10.0', 'Appa.dll');
      if (fs.existsSync(candidate)) return candidate;
    }
    return undefined;
  });
}

function detectLibgata(startDir: string): string | undefined {
  return findUpward(startDir, (dir) => {
    const candidate = path.join(dir, 'Gata', 'libgata');
    return fs.existsSync(candidate) ? candidate : undefined;
  });
}

function resolveAppaInvocation(settings: GataSettings, projectDir: string): { cmd: string; prefixArgs: string[] } | undefined {
  const configured = settings.appaPath;
  if (configured) {
    return configured.toLowerCase().endsWith('.dll')
      ? { cmd: 'dotnet', prefixArgs: [configured] }
      : { cmd: configured, prefixArgs: [] };
  }
  const dll = detectAppaDll(projectDir);
  if (dll) return { cmd: 'dotnet', prefixArgs: [dll] };
  return { cmd: 'appa', prefixArgs: [] };
}

function collectGataFiles(projectDir: string): Map<string, string> {
  const map = new Map<string, string>();
  const walk = (dir: string) => {
    let entries: fs.Dirent[];
    try { entries = fs.readdirSync(dir, { withFileTypes: true }); } catch { return; }
    for (const e of entries) {
      const full = path.join(dir, e.name);
      if (e.isDirectory()) {
        if (e.name === 'transpilation' || e.name === 'build' || e.name === 'artifacts') continue;
        walk(full);
      } else if (e.name.toLowerCase().endsWith('.g')) {
        map.set(e.name, full);
      }
    }
  };
  walk(projectDir);
  return map;
}

function pathToUri(p: string): string {
  let normalized = p.replace(/\\/g, '/');
  if (!normalized.startsWith('/')) normalized = '/' + normalized;
  return 'file://' + normalized.split('/').map(encodeURIComponent).join('/');
}

export async function checkProject(filePath: string, settings: GataSettings): Promise<Map<string, Diagnostic[]> | undefined> {
  const gconf = findGconf(path.dirname(filePath));
  if (!gconf) return undefined;
  const projectDir = path.dirname(gconf);

  const invocation = resolveAppaInvocation(settings, projectDir);
  if (!invocation) return undefined;

  const libgata = settings.libgataPath || detectLibgata(projectDir);
  const args = [...invocation.prefixArgs, 'check', gconf];
  if (libgata) args.push('--stdlib', libgata);

  const output = await new Promise<string>((resolve) => {
    execFile(invocation.cmd, args, { cwd: projectDir, timeout: 30_000 }, (_err, stdout, stderr) => {
      resolve(`${stdout}\n${stderr}`);
    });
  });

  const files = collectGataFiles(projectDir);
  const byUri = new Map<string, Diagnostic[]>();

  const resolveTarget = (name: string): string | undefined => {
    if (name === '' || name === '<environment>') return undefined;
    const base = path.basename(name);
    return files.get(base);
  };

  let openDiag: Diagnostic | undefined;

  for (const rawLine of output.split(/\r?\n/)) {
    const line = rawLine.replace(ANSI, '');
    const help = HELP_LINE.exec(line);
    if (help && openDiag) {
      openDiag.message += `\nhelp: ${help[1]}`;
      continue;
    }
    let m = HEADER_WITH_SPAN.exec(line);
    if (m) {
      const [, name, lineStr, colStr, sev, code, message] = m;
      const target = resolveTarget(name) ?? filePath;
      const uri = pathToUri(target);
      const ln = Math.max(0, parseInt(lineStr, 10) - 1);
      const col = Math.max(0, parseInt(colStr, 10) - 1);
      const diag: Diagnostic = {
        severity: sev === 'error' ? DiagnosticSeverity.Error : DiagnosticSeverity.Warning,
        range: { start: { line: ln, character: col }, end: { line: ln, character: col + 1 } },
        message,
        code,
        source: 'appa',
      };
      if (!byUri.has(uri)) byUri.set(uri, []);
      byUri.get(uri)!.push(diag);
      openDiag = diag;
      continue;
    }
    m = HEADER_NO_SPAN.exec(line);
    if (m) {
      const [, name, sev, code, message] = m;
      const target = resolveTarget(name) ?? filePath;
      const uri = pathToUri(target);
      const diag: Diagnostic = {
        severity: sev === 'error' ? DiagnosticSeverity.Error : DiagnosticSeverity.Warning,
        range: { start: { line: 0, character: 0 }, end: { line: 0, character: 1 } },
        message,
        code,
        source: 'appa',
      };
      if (!byUri.has(uri)) byUri.set(uri, []);
      byUri.get(uri)!.push(diag);
      openDiag = diag;
    }
  }

  return byUri;
}

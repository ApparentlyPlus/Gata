import {
  createConnection,
  TextDocuments,
  ProposedFeatures,
  InitializeParams,
  TextDocumentSyncKind,
  Diagnostic,
  DiagnosticSeverity,
  DidChangeConfigurationNotification,
} from 'vscode-languageserver/node';
import { TextDocument } from 'vscode-languageserver-textdocument';

import { Lexer } from './lexer';
import { Parser } from './parser';
import { ParseError, Span } from './codes';
import { checkProject, GataSettings, defaultSettings } from './semantic';

const connection = createConnection(ProposedFeatures.all);
const documents = new TextDocuments(TextDocument);

let settings: GataSettings = defaultSettings;
let hasConfigurationCapability = false;

connection.onInitialize((params: InitializeParams) => {
  hasConfigurationCapability = !!params.capabilities.workspace?.configuration;
  return {
    capabilities: {
      textDocumentSync: TextDocumentSyncKind.Incremental,
    },
  };
});

connection.onInitialized(() => {
  if (hasConfigurationCapability) {
    connection.client.register(DidChangeConfigurationNotification.type, undefined);
  }
});

connection.onDidChangeConfiguration(async () => {
  await refreshSettings();
  documents.all().forEach(validateSyntax);
});

async function refreshSettings(): Promise<void> {
  if (!hasConfigurationCapability) return;
  const config = await connection.workspace.getConfiguration('gata');
  settings = {
    appaPath: config?.appaPath || undefined,
    libgataPath: config?.libgataPath || undefined,
    enableSemanticChecks: config?.enableSemanticChecks ?? true,
  };
}

// Every diagnostic this server publishes for a file is grouped by source ('gata-syntax'
// vs 'appa') so the two layers (Part 2's instant in-process parse, Part 3's on-save real
// compiler run) never clobber each other; each keeps its own last-known set per URI.
const syntaxDiagnostics = new Map<string, Diagnostic[]>();
const semanticDiagnostics = new Map<string, Diagnostic[]>();

function publish(uri: string): void {
  const all = [...(syntaxDiagnostics.get(uri) ?? []), ...(semanticDiagnostics.get(uri) ?? [])];
  connection.sendDiagnostics({ uri, diagnostics: all });
}

function spanToRange(doc: TextDocument, span: Span) {
  const start = doc.positionAt(Math.max(0, span.start));
  const end = doc.positionAt(Math.max(span.start, span.start + Math.max(1, span.length)));
  return { start, end };
}

/// Lexes and parses the document in-process (a faithful port of Appa's own Lexer/Parser)
/// and publishes every syntax error it throws. This never shells out to anything, so it
/// runs on every keystroke regardless of whether the file belongs to a real project.
function validateSyntax(doc: TextDocument): void {
  const text = doc.getText();
  const diags: Diagnostic[] = [];
  try {
    const tokens = new Lexer(text).tokenize();
    new Parser(tokens).parseProgram();
  } catch (e) {
    if (e instanceof ParseError) {
      diags.push({
        severity: DiagnosticSeverity.Error,
        range: spanToRange(doc, e.span),
        message: e.hints.length > 0 ? `${e.message}\nhelp: ${e.hints.join('\nhelp: ')}` : e.message,
        code: e.code,
        source: 'gata-syntax',
      });
    } else {
      // A bug in the ported parser itself (e.g. an unhandled token shape) shouldn't take
      // the whole extension down - surface it as a diagnostic instead of throwing.
      diags.push({
        severity: DiagnosticSeverity.Warning,
        range: { start: { line: 0, character: 0 }, end: { line: 0, character: 1 } },
        message: `gata-syntax: internal parser error: ${e instanceof Error ? e.message : String(e)}`,
        source: 'gata-syntax',
      });
    }
  }
  syntaxDiagnostics.set(doc.uri, diags);
  publish(doc.uri);
}

let debounceTimer: ReturnType<typeof setTimeout> | undefined;
documents.onDidChangeContent((change) => {
  if (debounceTimer) clearTimeout(debounceTimer);
  debounceTimer = setTimeout(() => validateSyntax(change.document), 150);
});

documents.onDidOpen((change) => {
  validateSyntax(change.document);
  void runSemanticCheck(change.document);
});

documents.onDidSave((change) => {
  void runSemanticCheck(change.document);
});

async function runSemanticCheck(doc: TextDocument): Promise<void> {
  if (!settings.enableSemanticChecks) return;
  const filePath = uriToPath(doc.uri);
  if (!filePath) return;
  try {
    const byFile = await checkProject(filePath, settings);
    if (!byFile) return; // no project found - nothing to merge in
    // Clear stale semantic diagnostics for every previously-known file before applying
    // the fresh batch, so a fixed error doesn't linger forever in an unsaved sibling file.
    for (const uri of [...semanticDiagnostics.keys()]) {
      if (!byFile.has(uri)) { semanticDiagnostics.delete(uri); publish(uri); }
    }
    for (const [uri, diags] of byFile) {
      semanticDiagnostics.set(uri, diags);
      publish(uri);
    }
  } catch (e) {
    connection.console.warn(`gata: semantic check failed: ${e instanceof Error ? e.message : String(e)}`);
  }
}

function uriToPath(uri: string): string | undefined {
  try {
    const u = new URL(uri);
    if (u.protocol !== 'file:') return undefined;
    let p = decodeURIComponent(u.pathname);
    // file:///C:/foo -> pathname is /C:/foo on Windows; strip the leading slash.
    if (/^\/[a-zA-Z]:\//.test(p)) p = p.slice(1);
    return p;
  } catch {
    return undefined;
  }
}

documents.listen(connection);
connection.listen();

void refreshSettings();

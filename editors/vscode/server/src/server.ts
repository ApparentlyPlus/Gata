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
import { validateGconf } from './gconf';

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
  try {
    await refreshSettings();
  } catch (e) {
    connection.console.warn(`gata: could not refresh settings: ${e instanceof Error ? e.message : String(e)}`);
  }
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
  // A .gconf is XML, not Gata. Running the Gata parser over one would report a wall of
  // nonsense, so each language gets its own validator and they never cross.
  if (doc.languageId === 'gconf') {
    let diags: Diagnostic[];
    try {
      diags = validateGconf(doc);
    } catch (e) {
      diags = [{
        severity: DiagnosticSeverity.Warning,
        range: { start: { line: 0, character: 0 }, end: { line: 0, character: 1 } },
        message: `gconf: internal validator error: ${e instanceof Error ? e.message : String(e)}`,
        source: 'gconf',
      }];
    }
    syntaxDiagnostics.set(doc.uri, diags);
    publish(doc.uri);
    return;
  }

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

// Keyed by URI: one shared timer meant that editing file A and then file B within the
// debounce window cancelled A's pending validation and never rescheduled it, leaving A
// showing stale diagnostics until it was touched again.
const debounceTimers = new Map<string, ReturnType<typeof setTimeout>>();
documents.onDidChangeContent((change) => {
  const uri = change.document.uri;
  const pending = debounceTimers.get(uri);
  if (pending) clearTimeout(pending);
  debounceTimers.set(uri, setTimeout(() => {
    debounceTimers.delete(uri);
    validateSyntax(change.document);
  }, 150));
});

// Closing a file must retract its diagnostics, and drop the state we were holding for it.
documents.onDidClose((change) => {
  const uri = change.document.uri;
  const pending = debounceTimers.get(uri);
  if (pending) { clearTimeout(pending); debounceTimers.delete(uri); }
  syntaxDiagnostics.delete(uri);
  semanticDiagnostics.delete(uri);
  connection.sendDiagnostics({ uri, diagnostics: [] });
});

documents.onDidOpen((change) => {
  validateSyntax(change.document);
  void runSemanticCheck(change.document);
});

// A crash in a handler must not take the server process down with it and silently kill
// diagnostics for the whole session; log and keep serving.
process.on('uncaughtException', (e) => {
  connection.console.error(`gata: uncaught server error: ${e instanceof Error ? e.stack ?? e.message : String(e)}`);
});
process.on('unhandledRejection', (e) => {
  connection.console.error(`gata: unhandled rejection: ${e instanceof Error ? e.stack ?? e.message : String(e)}`);
});

documents.onDidSave((change) => {
  void runSemanticCheck(change.document);
});

async function runSemanticCheck(doc: TextDocument): Promise<void> {
  if (!settings.enableSemanticChecks) return;
  if (doc.languageId !== 'gata') return;   // 'appa check' takes Gata sources, not manifests
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

void refreshSettings().catch((e) =>
  connection.console.warn(`gata: initial settings load failed: ${e instanceof Error ? e.message : String(e)}`));

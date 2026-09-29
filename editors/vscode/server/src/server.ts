import {
  createConnection,
  TextDocuments,
  ProposedFeatures,
  TextDocumentSyncKind,
  Diagnostic,
  DiagnosticSeverity,
  DidChangeConfigurationNotification,
  SemanticTokens,
  DocumentSymbol,
  SymbolKind,
  CompletionItem,
  CompletionItemKind,
  MarkupKind,
  Hover,
} from 'vscode-languageserver/node';
import { TextDocument } from 'vscode-languageserver-textdocument';

import { Lexer } from './lexer';
import { Parser } from './parser';
import { CODE_SUMMARIES, ParseError, Span } from './codes';
import { checkProject, GataSettings, defaultSettings } from './semantic';
import { ImportIndex, emptyIndex, forgetFile, indexFor } from './imports';
import { validateGconf } from './gconf';
import { classify, TOKEN_TYPES, TOKEN_MODIFIERS } from './semtokens';
import { symbolsOf, GataSymbol } from './symbols';
import { completionsFor, hoverFor, CompletionEntry } from './language';

const connection = createConnection(ProposedFeatures.all);
const documents = new TextDocuments(TextDocument);

let settings: GataSettings = defaultSettings;
let canConfigure = false;

const why = (e: unknown) => (e instanceof Error ? e.message : String(e));

connection.onInitialize((params) => {
  canConfigure = !!params.capabilities.workspace?.configuration;
  return {
    capabilities: {
      textDocumentSync: TextDocumentSyncKind.Incremental,
      hoverProvider: true,
      documentSymbolProvider: true,
      completionProvider: { resolveProvider: false, triggerCharacters: ['@', '.'] },
      semanticTokensProvider: {
        legend: { tokenTypes: [...TOKEN_TYPES], tokenModifiers: [...TOKEN_MODIFIERS] },
        full: true,
      },
    },
  };
});

connection.onInitialized(() => {
  if (canConfigure) connection.client.register(DidChangeConfigurationNotification.type, undefined);
});

connection.onDidChangeConfiguration(async () => {
  try {
    await refreshSettings();
  } catch (e) {
    connection.console.warn(`gata: could not refresh settings: ${why(e)}`);
  }
  documents.all().forEach(validateSyntax);
});

async function refreshSettings(): Promise<void> {
  if (!canConfigure) return;
  const config = await connection.workspace.getConfiguration('gata');
  settings = {
    appaPath: config?.appaPath || undefined,
    libgataPath: config?.libgataPath || undefined,
    enableSemanticChecks: config?.enableSemanticChecks ?? true,
  };
}

// syntax comes from our own parser on every keystroke, semantic from 'appa check' on save
const syntaxDiags = new Map<string, Diagnostic[]>();
const semanticDiags = new Map<string, Diagnostic[]>();

function publish(uri: string): void {
  const all = [...(syntaxDiags.get(uri) ?? []), ...(semanticDiags.get(uri) ?? [])];
  connection.sendDiagnostics({ uri, diagnostics: all });
}

function spanToRange(doc: TextDocument, span: Span) {
  const start = doc.positionAt(Math.max(0, span.start));
  const end = doc.positionAt(Math.max(span.start, span.start + Math.max(1, span.length)));
  return { start, end };
}

// a crash in our own checker shows up as a warning on the first character, not a dead server
function internalError(source: string, what: string, e: unknown): Diagnostic {
  return {
    severity: DiagnosticSeverity.Warning,
    range: { start: { line: 0, character: 0 }, end: { line: 0, character: 1 } },
    message: `${source}: internal ${what} error: ${why(e)}`,
    source,
  };
}

function validateSyntax(doc: TextDocument): void {
  let diags: Diagnostic[] = [];
  if (doc.languageId === 'gconf') {
    try {
      diags = validateGconf(doc);
    } catch (e) {
      diags = [internalError('gconf', 'validator', e)];
    }
  } else {
    try {
      new Parser(new Lexer(doc.getText()).tokenize()).parseProgram();
    } catch (e) {
      if (e instanceof ParseError) diags.push(parseErrorDiag(doc, e));
      else diags.push(internalError('gata-syntax', 'parser', e));
    }
  }
  syntaxDiags.set(doc.uri, diags);
  publish(doc.uri);
}

function parseErrorDiag(doc: TextDocument, e: ParseError): Diagnostic {
  const summary = CODE_SUMMARIES[e.code];
  const lines = [e.message];
  for (const hint of e.hints) lines.push(`help: ${hint}`);
  if (summary) lines.push(`${e.code}: ${summary}`);
  return {
    severity: DiagnosticSeverity.Error,
    range: spanToRange(doc, e.span),
    message: lines.join('\n'),
    code: e.code,
    source: 'gata-syntax',
  };
}

// reparse at most every 150ms while typing
const timers = new Map<string, ReturnType<typeof setTimeout>>();

documents.onDidChangeContent((change) => {
  const uri = change.document.uri;
  clearTimeout(timers.get(uri));
  timers.set(uri, setTimeout(() => {
    timers.delete(uri);
    validateSyntax(change.document);
  }, 150));
});

documents.onDidClose((change) => {
  const uri = change.document.uri;
  clearTimeout(timers.get(uri));
  timers.delete(uri);
  syntaxDiags.delete(uri);
  semanticDiags.delete(uri);
  connection.sendDiagnostics({ uri, diagnostics: [] });
});

documents.onDidOpen((change) => {
  validateSyntax(change.document);
  void runSemanticCheck(change.document);
});

documents.onDidSave((change) => {
  const filePath = uriToPath(change.document.uri);
  if (filePath) forgetFile(filePath);
  void runSemanticCheck(change.document);
});

process.on('uncaughtException', (e) => {
  connection.console.error(`gata: uncaught server error: ${e instanceof Error ? e.stack ?? e.message : String(e)}`);
});
process.on('unhandledRejection', (e) => {
  connection.console.error(`gata: unhandled rejection: ${e instanceof Error ? e.stack ?? e.message : String(e)}`);
});

async function runSemanticCheck(doc: TextDocument): Promise<void> {
  if (!settings.enableSemanticChecks) return;
  if (doc.languageId !== 'gata') return;   // 'appa check' takes Gata sources, not manifests
  const filePath = uriToPath(doc.uri);
  if (!filePath) return;
  try {
    const byFile = await checkProject(filePath, settings);
    if (!byFile) return;
    // files that were reported last time and are clean now need their old squiggles cleared
    for (const uri of [...semanticDiags.keys()]) {
      if (byFile.has(uri)) continue;
      semanticDiags.delete(uri);
      publish(uri);
    }
    for (const [uri, diags] of byFile) {
      semanticDiags.set(uri, diags);
      publish(uri);
    }
  } catch (e) {
    connection.console.warn(`gata: semantic check failed: ${why(e)}`);
  }
}

function importIndex(doc: TextDocument): ImportIndex {
  const filePath = uriToPath(doc.uri);
  if (!filePath) return emptyIndex();
  try {
    return indexFor(filePath, doc.getText(), settings);
  } catch (e) {
    connection.console.warn(`gata: could not resolve imports: ${why(e)}`);
    return emptyIndex();
  }
}

function uriToPath(uri: string): string | undefined {
  try {
    const u = new URL(uri);
    if (u.protocol !== 'file:') return undefined;
    let p = decodeURIComponent(u.pathname);
    if (/^\/[a-zA-Z]:\//.test(p)) p = p.slice(1);
    return p;
  } catch {
    return undefined;
  }
}

function gataDoc(uri: string): TextDocument | undefined {
  const doc = documents.get(uri);
  return doc?.languageId === 'gata' ? doc : undefined;
}

connection.languages.semanticTokens.on((params): SemanticTokens => {
  const doc = gataDoc(params.textDocument.uri);
  if (!doc) return { data: [] };
  try {
    return { data: encode(doc, classify(doc.getText(), importIndex(doc).external)) };
  } catch (e) {
    connection.console.warn(`gata: semantic tokens failed: ${why(e)}`);
    return { data: [] };
  }
});

// LSP wants each token relative to the one before it
function encode(doc: TextDocument, tokens: ReturnType<typeof classify>): number[] {
  const out: number[] = [];
  let line = 0;
  let char = 0;
  for (const t of tokens) {
    const pos = doc.positionAt(t.start);
    if (doc.positionAt(t.start + t.length).line !== pos.line) continue;   // a multi-line token cannot be encoded this way
    const dl = pos.line - line;
    out.push(dl, dl === 0 ? pos.character - char : pos.character, t.length, t.type, t.modifiers);
    line = pos.line;
    char = pos.character;
  }
  return out;
}

connection.onHover((params): Hover | null => {
  const doc = gataDoc(params.textDocument.uri);
  if (!doc) return null;
  const md = hoverFor(doc.getText(), doc.offsetAt(params.position), importIndex(doc).symbols);
  return md ? { contents: { kind: MarkupKind.Markdown, value: md } } : null;
});

const SYMBOL_KINDS: Readonly<Record<GataSymbol['kind'], SymbolKind>> = {
  class: SymbolKind.Class,
  module: SymbolKind.Module,
  enum: SymbolKind.Enum,
  union: SymbolKind.Struct,
  variant: SymbolKind.EnumMember,
  enumMember: SymbolKind.EnumMember,
  function: SymbolKind.Function,
  method: SymbolKind.Method,
  operator: SymbolKind.Operator,
  realm: SymbolKind.Namespace,
  process: SymbolKind.Namespace,
  thread: SymbolKind.Namespace,
  nativeType: SymbolKind.Struct,
};

connection.onDocumentSymbol((params): DocumentSymbol[] => {
  const doc = gataDoc(params.textDocument.uri);
  if (!doc) return [];
  return symbolsOf(doc.getText()).map((sym) => {
    const range = spanToRange(doc, { start: sym.start, length: sym.length });
    return { name: sym.name, detail: sym.detail, kind: SYMBOL_KINDS[sym.kind], range, selectionRange: range };
  });
});

const COMPLETION_KINDS: Readonly<Record<CompletionEntry['kind'], CompletionItemKind>> = {
  keyword: CompletionItemKind.Keyword,
  type: CompletionItemKind.Keyword,
  class: CompletionItemKind.Class,
  enum: CompletionItemKind.Enum,
  union: CompletionItemKind.Struct,
  function: CompletionItemKind.Function,
  variable: CompletionItemKind.Variable,
  annotation: CompletionItemKind.Property,
  namespace: CompletionItemKind.Module,
};

connection.onCompletion((params): CompletionItem[] => {
  const doc = gataDoc(params.textDocument.uri);
  if (!doc) return [];
  return completionsFor(doc.getText(), importIndex(doc).symbols).map((entry) => ({
    label: entry.label,
    kind: COMPLETION_KINDS[entry.kind],
    detail: entry.detail,
    documentation: entry.documentation
      ? { kind: MarkupKind.Markdown, value: entry.documentation }
      : undefined,
  }));
});

documents.listen(connection);
connection.listen();

void refreshSettings().catch((e) =>
  connection.console.warn(`gata: initial settings load failed: ${why(e)}`));

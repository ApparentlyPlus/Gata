import {
  createConnection,
  TextDocuments,
  ProposedFeatures,
  InitializeParams,
  TextDocumentSyncKind,
  Diagnostic,
  DiagnosticSeverity,
  DidChangeConfigurationNotification,
  SemanticTokens,
  SemanticTokensParams,
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
import { validateGconf } from './gconf';
import { classify, TOKEN_TYPES, TOKEN_MODIFIERS } from './semtokens';
import { symbolsOf, GataSymbol } from './symbols';
import { completionsFor, hoverFor, CompletionEntry } from './language';

const connection = createConnection(ProposedFeatures.all);
const documents = new TextDocuments(TextDocument);

let settings: GataSettings = defaultSettings;
let hasConfigurationCapability = false;

connection.onInitialize((params: InitializeParams) => {
  hasConfigurationCapability = !!params.capabilities.workspace?.configuration;
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

function validateSyntax(doc: TextDocument): void {
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
      const summary = CODE_SUMMARIES[e.code];
      const lines = [e.message];
      for (const hint of e.hints) lines.push(`help: ${hint}`);
      if (summary) lines.push(`${e.code}: ${summary}`);
      diags.push({
        severity: DiagnosticSeverity.Error,
        range: spanToRange(doc, e.span),
        message: lines.join('\n'),
        code: e.code,
        source: 'gata-syntax',
      });
    } else {
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

documents.onDidSave((change) => {
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
    if (/^\/[a-zA-Z]:\//.test(p)) p = p.slice(1);
    return p;
  } catch {
    return undefined;
  }
}

connection.languages.semanticTokens.on((params: SemanticTokensParams): SemanticTokens => {
  const doc = documents.get(params.textDocument.uri);
  if (!doc || doc.languageId !== 'gata') return { data: [] };
  try {
    return { data: encode(doc, classify(doc.getText())) };
  } catch (e) {
    connection.console.warn(`gata: semantic tokens failed: ${e instanceof Error ? e.message : String(e)}`);
    return { data: [] };
  }
});

function encode(doc: TextDocument, tokens: ReturnType<typeof classify>): number[] {
  const data: number[] = [];
  let lastLine = 0;
  let lastChar = 0;
  for (const t of tokens) {
    const pos = doc.positionAt(t.start);
    const end = doc.positionAt(t.start + t.length);
    if (end.line !== pos.line) continue;   // a multi-line token cannot be encoded this way
    const deltaLine = pos.line - lastLine;
    const deltaChar = deltaLine === 0 ? pos.character - lastChar : pos.character;
    data.push(deltaLine, deltaChar, t.length, t.type, t.modifiers);
    lastLine = pos.line;
    lastChar = pos.character;
  }
  return data;
}

connection.onHover((params): Hover | null => {
  const doc = documents.get(params.textDocument.uri);
  if (!doc || doc.languageId !== 'gata') return null;
  const markdown = hoverFor(doc.getText(), doc.offsetAt(params.position));
  if (!markdown) return null;
  return { contents: { kind: MarkupKind.Markdown, value: markdown } };
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
  const doc = documents.get(params.textDocument.uri);
  if (!doc || doc.languageId !== 'gata') return [];
  return symbolsOf(doc.getText()).map((sym) => {
    const range = spanToRange(doc, { start: sym.start, length: sym.length });
    return {
      name: sym.name,
      detail: sym.detail,
      kind: SYMBOL_KINDS[sym.kind],
      range,
      selectionRange: range,
    };
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
  const doc = documents.get(params.textDocument.uri);
  if (!doc || doc.languageId !== 'gata') return [];
  return completionsFor(doc.getText()).map((entry) => ({
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
  connection.console.warn(`gata: initial settings load failed: ${e instanceof Error ? e.message : String(e)}`));

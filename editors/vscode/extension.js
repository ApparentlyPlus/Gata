const vscode = require('vscode');
const path = require('path');
const { LanguageClient, TransportKind } = require('vscode-languageclient/node');

// Every scope below ends in '.gata' — a suffix unique to this grammar — so
// these rules can never match tokens from any other language's grammar.
// That's what makes it safe to merge them into the *global* settings: they
// overlay on top of whatever color theme is already active instead of
// replacing it, so non-Gata files keep looking exactly as they did before.
const GATA_RULES = [
  { scope: 'comment.line.double-slash.gata', settings: { foreground: '#6b7280', fontStyle: 'italic' } },
  { scope: 'comment.block.gata', settings: { foreground: '#6b7280', fontStyle: 'italic' } },
  { scope: 'comment.block.native.gata', settings: { foreground: '#6f7178' } },
  { scope: 'keyword.control.risk.gata', settings: { foreground: '#9c2b2b' } },
  { scope: 'keyword.other.meta.native.gata', settings: { foreground: '#8f87b0' } },
  { scope: 'keyword.other.meta.annotation.gata', settings: { foreground: '#8f87b0' } },
  { scope: 'variable.parameter.annotation.gata', settings: { foreground: '#b6aed4' } },
  { scope: 'keyword.control.gata', settings: { foreground: '#5b84c4' } },
  { scope: 'keyword.control.flow.gata', settings: { foreground: '#8caa6e' } },
  { scope: 'variable.language.self.gata', settings: { foreground: '#5b84c4', fontStyle: 'italic' } },
  { scope: 'entity.name.function.gata', settings: { foreground: '#7fc4b8' } },
  { scope: 'variable.other.gata', settings: { foreground: '#cfcbc1' } },
  { scope: 'constant.language.boolean.gata', settings: { foreground: '#e6cf94', fontStyle: 'bold' } },
  { scope: 'constant.language.null.gata', settings: { foreground: '#e6cf94', fontStyle: 'bold' } },
  { scope: 'storage.type.primitive.gata', settings: { foreground: '#c9a227' } },
  { scope: 'entity.name.type.class.gata', settings: { foreground: '#e0b34d' } },
  { scope: 'entity.name.type.parameter.gata', settings: { foreground: '#a9854f', fontStyle: 'italic' } },
  { scope: 'string.quoted.double.gata', settings: { foreground: '#d98a4f' } },
  { scope: 'string.interpolated.gata', settings: { foreground: '#e0a468' } },
  { scope: 'constant.character.escape.gata', settings: { foreground: '#f0c08a' } },
  { scope: 'constant.character.gata', settings: { foreground: '#d98a4f' } },
  { scope: 'constant.numeric.integer.gata', settings: { foreground: '#cf8c4a' } },
  { scope: 'constant.numeric.integer.hex.gata', settings: { foreground: '#cf8c4a' } },
  { scope: 'constant.numeric.float.gata', settings: { foreground: '#cf8c4a' } },
  { scope: 'keyword.operator.gata', settings: { foreground: '#c5cad1' } },
  { scope: 'punctuation.terminator.gata', settings: { foreground: '#cfcbc1' } },
  { scope: 'punctuation.brackets.gata', settings: { foreground: '#c9c34f' } },
  { scope: 'punctuation.brackets.empty.gata', settings: { foreground: '#8a8f98' } },
  { scope: 'punctuation.gata', settings: { foreground: '#8a8f98' } },
];

const GATA_SCOPES = new Set(GATA_RULES.map((rule) => rule.scope));

/** @type {import('vscode-languageclient/node').LanguageClient | undefined} */
let client;

function activate(context) {
  applyOverlay();
  client = startLanguageServer(context);
}

/**
 * Starts the Gata language server (a ported Appa Lexer/Parser for instant syntax
 * diagnostics, plus an on-save shell-out to the real 'appa check' for semantic
 * diagnostics — see server/src/server.ts). Runs as a separate Node process, same as
 * any other VS Code LSP extension; this function only wires the client side.
 */
function startLanguageServer(context) {
  const serverModule = context.asAbsolutePath(path.join('server', 'dist', 'server.js'));
  const serverOptions = {
    run: { module: serverModule, transport: TransportKind.ipc },
    debug: { module: serverModule, transport: TransportKind.ipc },
  };
  const clientOptions = {
    documentSelector: [{ scheme: 'file', language: 'gata' }],
    synchronize: {
      configurationSection: 'gata',
    },
  };
  const languageClient = new LanguageClient('gata', 'Gata Language Server', serverOptions, clientOptions);
  languageClient.start();
  return languageClient;
}

function applyOverlay() {
  const config = vscode.workspace.getConfiguration();
  const current = config.get('editor.tokenColorCustomizations') || {};
  const existingRules = Array.isArray(current.textMateRules) ? current.textMateRules : [];

  // Drop any rules we previously wrote for these scopes, then re-add the
  // current set — keeps this idempotent and self-healing across updates,
  // without touching any non-Gata rules the user added themselves.
  const keptRules = existingRules.filter((rule) => {
    const scope = Array.isArray(rule.scope) ? rule.scope[0] : rule.scope;
    return !GATA_SCOPES.has(scope);
  });

  const nextRules = [...keptRules, ...GATA_RULES];
  if (JSON.stringify(existingRules) === JSON.stringify(nextRules)) {
    return;
  }

  config.update(
    'editor.tokenColorCustomizations',
    { ...current, textMateRules: nextRules },
    vscode.ConfigurationTarget.Global
  );
}

function deactivate() {
  return client?.stop();
}

module.exports = { activate, deactivate };

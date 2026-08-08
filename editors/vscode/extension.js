const vscode = require('vscode');
const path = require('path');
const { LanguageClient, TransportKind } = require('vscode-languageclient/node');

const TEXTMATE_RULES = [
  { scope: 'comment.line.double-slash.gata', settings: { foreground: '#6b7280', fontStyle: 'italic' } },
  { scope: 'comment.block.gata', settings: { foreground: '#6b7280', fontStyle: 'italic' } },
  { scope: 'comment.block.native.gata', settings: { foreground: '#6f7178' } },
  { scope: 'keyword.control.risk.gata', settings: { foreground: '#c2504a' } },
  { scope: 'keyword.control.topology.gata', settings: { foreground: '#8f87b0' } },
  { scope: 'entity.name.namespace.gata', settings: { foreground: '#b6aed4' } },
  { scope: 'keyword.other.annotation.gata', settings: { foreground: '#8f87b0' } },
  { scope: 'variable.parameter.annotation.gata', settings: { foreground: '#b6aed4' } },
  { scope: 'keyword.declaration.gata', settings: { foreground: '#5b84c4' } },
  { scope: 'storage.modifier.gata', settings: { foreground: '#6f9fd8' } },
  { scope: 'keyword.control.flow.gata', settings: { foreground: '#8caa6e' } },
  { scope: 'keyword.operator.word.gata', settings: { foreground: '#7fa8c9' } },
  { scope: 'variable.language.self.gata', settings: { foreground: '#5b84c4', fontStyle: 'italic' } },
  { scope: 'entity.name.function.gata', settings: { foreground: '#7fc4b8' } },
  { scope: 'entity.name.function.operator.gata', settings: { foreground: '#7fc4b8' } },
  { scope: 'variable.other.gata', settings: { foreground: '#cfcbc1' } },
  { scope: 'variable.other.property.gata', settings: { foreground: '#cfcbc1' } },
  { scope: 'variable.other.binding.gata', settings: { foreground: '#cfcbc1' } },
  { scope: 'variable.parameter.gata', settings: { foreground: '#cfcbc1', fontStyle: 'italic' } },
  { scope: 'variable.other.enummember.gata', settings: { foreground: '#e6cf94' } },
  { scope: 'constant.language.boolean.gata', settings: { foreground: '#e6cf94', fontStyle: 'bold' } },
  { scope: 'constant.language.null.gata', settings: { foreground: '#e6cf94', fontStyle: 'bold' } },
  { scope: 'storage.type.primitive.gata', settings: { foreground: '#c9a227' } },
  { scope: 'entity.name.type.class.gata', settings: { foreground: '#f0c66a' } },
  { scope: 'entity.name.type.enum.gata', settings: { foreground: '#f0c66a' } },
  { scope: 'entity.name.type.union.gata', settings: { foreground: '#f0c66a' } },
  { scope: 'entity.name.type.gata', settings: { foreground: '#e0b34d' } },
  { scope: 'entity.name.type.variant.gata', settings: { foreground: '#d9a05b' } },
  { scope: 'entity.name.type.parameter.gata', settings: { foreground: '#a9854f', fontStyle: 'italic' } },
  { scope: 'string.quoted.double.gata', settings: { foreground: '#d98a4f' } },
  { scope: 'string.interpolated.gata', settings: { foreground: '#e0a468' } },
  { scope: 'constant.character.gata', settings: { foreground: '#d98a4f' } },
  { scope: 'punctuation.definition.string.begin.gata', settings: { foreground: '#b0713f' } },
  { scope: 'punctuation.definition.string.end.gata', settings: { foreground: '#b0713f' } },
  { scope: 'punctuation.section.interpolation.gata', settings: { foreground: '#b0713f' } },
  { scope: 'constant.character.escape.gata', settings: { foreground: '#f0c08a' } },
  { scope: 'constant.numeric.integer.gata', settings: { foreground: '#cf8c4a' } },
  { scope: 'constant.numeric.integer.hexadecimal.gata', settings: { foreground: '#cf8c4a' } },
  { scope: 'constant.numeric.float.gata', settings: { foreground: '#cf8c4a' } },
  { scope: 'keyword.operator.gata', settings: { foreground: '#c5cad1' } },
  { scope: 'keyword.operator.scope.gata', settings: { foreground: '#b6aed4' } },
  { scope: 'punctuation.terminator.gata', settings: { foreground: '#c5cad1' } },
  { scope: 'punctuation.brackets.gata', settings: { foreground: '#c9c34f' } },
  { scope: 'punctuation.braces.gata', settings: { foreground: '#8a8f98' } },
  { scope: 'punctuation.separator.gata', settings: { foreground: '#8a8f98' } },
  { scope: 'punctuation.accessor.gata', settings: { foreground: '#8a8f98' } },
  { scope: 'invalid.illegal.gata', settings: { foreground: '#ef5350' } },
];

const SEMANTIC_RULES = {
  'namespace:gata': '#b6aed4',
  'class:gata': '#e0b34d',
  'class.declaration:gata': { foreground: '#f0c66a' },
  'enum:gata': '#e0b34d',
  'enum.declaration:gata': { foreground: '#f0c66a' },
  'struct:gata': '#e0b34d',
  'struct.declaration:gata': { foreground: '#f0c66a' },
  'enumMember:gata': '#e6cf94',
  'type:gata': '#e0b34d',
  'typeParameter:gata': { foreground: '#a9854f', fontStyle: 'italic' },
  'function:gata': '#7fc4b8',
  'method:gata': '#7fc4b8',
  'parameter:gata': { foreground: '#cfcbc1', fontStyle: 'italic' },
  'variable:gata': '#cfcbc1',
  'property:gata': '#cfcbc1',
  'macro:gata': '#8f87b0',
};

const OWNED_TEXTMATE_SCOPES = new Set(TEXTMATE_RULES.map((rule) => rule.scope));
const OWNED_SEMANTIC_SELECTORS = new Set(Object.keys(SEMANTIC_RULES));

/** @type {import('vscode-languageclient/node').LanguageClient | undefined} */
let client;

function activate(context) {
  try {
    applyOverlay();
  } catch (err) {
    console.error('gata: could not apply the color overlay:', err);
  }
  try {
    client = startLanguageServer(context);
  } catch (err) {
    console.error('gata: could not start the language server:', err);
    vscode.window.showWarningMessage(
      'Gata: the language server failed to start, so diagnostics, hovers and semantic colors are unavailable. Syntax highlighting still works.'
    );
  }
}

function startLanguageServer(context) {
  const serverModule = context.asAbsolutePath(path.join('server', 'dist', 'server.js'));
  const serverOptions = {
    run: { module: serverModule, transport: TransportKind.ipc },
    debug: { module: serverModule, transport: TransportKind.ipc },
  };
  const clientOptions = {
    documentSelector: [
      { scheme: 'file', language: 'gata' },
      { scheme: 'file', language: 'gconf' },
    ],
    synchronize: {
      configurationSection: 'gata',
    },
  };
  const languageClient = new LanguageClient('gata', 'Gata Language Server', serverOptions, clientOptions);
  languageClient.start().catch((err) => {
    console.error('gata: language server exited:', err);
    vscode.window.showWarningMessage(
      `Gata: the language server stopped (${err && err.message ? err.message : err}). Syntax highlighting still works.`
    );
  });
  return languageClient;
}

function applyOverlay() {
  const config = vscode.workspace.getConfiguration();
  writeTextMateOverlay(config);
  writeSemanticOverlay(config);
}

function writeTextMateOverlay(config) {
  const current = config.get('editor.tokenColorCustomizations') || {};
  const existing = Array.isArray(current.textMateRules) ? current.textMateRules : [];
  const kept = existing.filter((rule) => {
    const scope = Array.isArray(rule.scope) ? rule.scope[0] : rule.scope;
    return !OWNED_TEXTMATE_SCOPES.has(scope);
  });

  const next = [...kept, ...TEXTMATE_RULES];
  if (JSON.stringify(existing) === JSON.stringify(next)) return;

  update(config, 'editor.tokenColorCustomizations', { ...current, textMateRules: next });
}

function writeSemanticOverlay(config) {
  const current = config.get('editor.semanticTokenColorCustomizations') || {};
  const existing = current.rules && typeof current.rules === 'object' ? current.rules : {};

  const kept = {};
  for (const [selector, value] of Object.entries(existing))
    if (!OWNED_SEMANTIC_SELECTORS.has(selector)) kept[selector] = value;

  const next = { ...kept, ...SEMANTIC_RULES };
  if (JSON.stringify(existing) === JSON.stringify(next)) return;

  update(config, 'editor.semanticTokenColorCustomizations', { ...current, rules: next });
}

function update(config, key, value) {
  Promise.resolve(config.update(key, value, vscode.ConfigurationTarget.Global)).then(
    undefined,
    (err) => console.error(`gata: could not write ${key}:`, err)
  );
}

function deactivate() {
  if (!client) return undefined;
  return client.stop().catch((err) => console.error('gata: error stopping the language server:', err));
}

module.exports = { activate, deactivate };

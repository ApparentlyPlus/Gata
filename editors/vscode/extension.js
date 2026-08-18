const vscode = require('vscode');
const path = require('path');
const { LanguageClient, TransportKind } = require('vscode-languageclient/node');

const LEGACY_TEXTMATE_SCOPES = new Set([
  'comment.line.double-slash.gata',
  'comment.block.gata',
  'comment.block.native.gata',
  'keyword.control.risk.gata',
  'keyword.control.topology.gata',
  'entity.name.namespace.gata',
  'keyword.other.annotation.gata',
  'variable.parameter.annotation.gata',
  'keyword.declaration.gata',
  'storage.modifier.gata',
  'keyword.control.flow.gata',
  'keyword.operator.word.gata',
  'variable.language.self.gata',
  'entity.name.function.gata',
  'entity.name.function.operator.gata',
  'variable.other.gata',
  'variable.other.property.gata',
  'variable.other.binding.gata',
  'variable.parameter.gata',
  'variable.other.enummember.gata',
  'constant.language.boolean.gata',
  'constant.language.null.gata',
  'storage.type.primitive.gata',
  'entity.name.type.class.gata',
  'entity.name.type.enum.gata',
  'entity.name.type.union.gata',
  'entity.name.type.gata',
  'entity.name.type.variant.gata',
  'entity.name.type.parameter.gata',
  'string.quoted.double.gata',
  'string.interpolated.gata',
  'constant.character.gata',
  'punctuation.definition.string.begin.gata',
  'punctuation.definition.string.end.gata',
  'punctuation.section.interpolation.gata',
  'constant.character.escape.gata',
  'constant.numeric.integer.gata',
  'constant.numeric.integer.hexadecimal.gata',
  'constant.numeric.float.gata',
  'keyword.operator.gata',
  'keyword.operator.scope.gata',
  'punctuation.terminator.gata',
  'punctuation.brackets.gata',
  'punctuation.braces.gata',
  'punctuation.separator.gata',
  'punctuation.accessor.gata',
  'invalid.illegal.gata',
]);

const LEGACY_SEMANTIC_SELECTORS = new Set([
  'namespace:gata',
  'class:gata',
  'class.declaration:gata',
  'enum:gata',
  'enum.declaration:gata',
  'struct:gata',
  'struct.declaration:gata',
  'enumMember:gata',
  'type:gata',
  'typeParameter:gata',
  'function:gata',
  'method:gata',
  'parameter:gata',
  'variable:gata',
  'property:gata',
  'macro:gata',
]);

const OVERLAY_REMOVED_KEY = 'gata.legacyOverlayRemoved';

/** @type {import('vscode-languageclient/node').LanguageClient | undefined} */
let client;

function activate(context) {
  try {
    removeLegacyOverlay(context);
  } catch (err) {
    console.error('gata: could not clean up the legacy color overlay:', err);
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

function removeLegacyOverlay(context) {
  if (context.globalState.get(OVERLAY_REMOVED_KEY)) return;
  const config = vscode.workspace.getConfiguration();

  const pruned = [
    pruneTextMate(config),
    pruneSemantic(config),
  ];

  Promise.all(pruned).then(
    () => context.globalState.update(OVERLAY_REMOVED_KEY, true),
    (err) => console.error('gata: could not remove the legacy color overlay:', err)
  );
}

function pruneTextMate(config) {
  const inspected = config.inspect('editor.tokenColorCustomizations');
  const current = inspected && inspected.globalValue;
  if (!current || !Array.isArray(current.textMateRules)) return Promise.resolve();

  const kept = current.textMateRules.filter((rule) => {
    const scope = Array.isArray(rule.scope) ? rule.scope[0] : rule.scope;
    return !LEGACY_TEXTMATE_SCOPES.has(scope);
  });
  if (kept.length === current.textMateRules.length) return Promise.resolve();

  const next = { ...current };
  if (kept.length) next.textMateRules = kept;
  else delete next.textMateRules;
  return write(config, 'editor.tokenColorCustomizations', next);
}

function pruneSemantic(config) {
  const inspected = config.inspect('editor.semanticTokenColorCustomizations');
  const current = inspected && inspected.globalValue;
  if (!current || !current.rules || typeof current.rules !== 'object') return Promise.resolve();

  const kept = {};
  for (const [selector, value] of Object.entries(current.rules))
    if (!LEGACY_SEMANTIC_SELECTORS.has(selector)) kept[selector] = value;
  if (Object.keys(kept).length === Object.keys(current.rules).length) return Promise.resolve();

  const next = { ...current };
  if (Object.keys(kept).length) next.rules = kept;
  else delete next.rules;
  if (Object.keys(next).length === 1 && next.enabled === true) delete next.enabled;

  return write(config, 'editor.semanticTokenColorCustomizations', next);
}

function write(config, key, value) {
  const empty = Object.keys(value).length === 0;
  return Promise.resolve(config.update(key, empty ? undefined : value, vscode.ConfigurationTarget.Global));
}

function deactivate() {
  if (!client) return undefined;
  return client.stop().catch((err) => console.error('gata: error stopping the language server:', err));
}

module.exports = { activate, deactivate };

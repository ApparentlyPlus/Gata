# Gata Language (VS Code)

Language support for `.g` files: syntax highlighting, plus a real language
server for real-time syntax diagnostics and on-save semantic diagnostics
from the actual `appa` compiler.

## Syntax highlighting

A TextMate grammar (`syntaxes/gata.tmLanguage.json`) covering every token
the lexer produces (`Appa/src/Syntax/Lexer.cs`/`Token.cs`), including the
`@intrinsic`/`@preamble`/`@builtin`/`@extern`/`@environment`/`@keep`
annotation family.

This is a language extension, not a theme you have to go find and pick, and
it does **not** touch your editor theme. `extension.js` activates the first
time you open a `.g` file and merges a fixed set of color rules into
`editor.tokenColorCustomizations.textMateRules` (global settings). Every one
of those rules is scoped to a `*.gata`-suffixed TextMate scope, which only
ever exists inside `.g` files — so it overlays on top of whatever theme
you're already using and never touches any other language's coloring.
(`themes/gata-gold-color-theme.json` still ships as an optional full theme
if you ever want to switch to it manually via `Preferences: Color Theme`,
but nothing auto-applies it.)

It also disables VS Code's built-in bracket-pair-colorization for `.g`
files only (`"[gata]": { "editor.bracketPairColorization.enabled": false }`)
so parens/brackets follow the grammar's own coloring instead of cycling
through unrelated colors by nesting depth.

## Language server

`server/` is a small LSP server (TypeScript, bundled with esbuild) with two
layers of diagnostics:

- **Syntax, real-time, every file.** `server/src/lexer.ts` and
  `server/src/parser.ts` are direct ports of Appa's actual
  `Lexer.cs`/`Parser.cs` — same token rules, same recursive-descent grammar,
  same error codes and messages (`missing 'let'?`, a `process` with no
  `foreground`/`background`, a trailing comma, an unterminated string, ...).
  They run in-process on every keystroke (debounced ~150ms), so this works
  on any `.g` file whether or not it belongs to a project, with zero
  external dependencies.
- **Semantic, on save, project files only.** `server/src/semantic.ts` walks
  upward from the saved file looking for a `*.gconf`. If it finds one, it
  shells out to the real compiler — `appa check <project>` (see
  `Appa/src/CLI/Program.cs`'s `RunCheck`), a command that runs the full
  front end (imports, symbol collection, type resolution) and stops before
  emission — and parses its diagnostic output back into squiggles, tagged
  `source: "appa"`. This is never approximated in TypeScript: type errors,
  undefined symbols, and every other semantic `Gxxx` code come straight from
  the real compiler.

Settings (`gata.appaPath`, `gata.libgataPath`, `gata.enableSemanticChecks`)
control the second layer — see their descriptions in VS Code's Settings UI,
or `package.json`'s `contributes.configuration`. With nothing configured,
the extension auto-detects a debug build of `Appa.csproj` and a `Gata/libgata`
checkout next to wherever this extension itself lives, which is exactly the
layout of the Pawstack monorepo this extension ships from.

## Install (development)

```sh
cp -r editors/vscode ~/.vscode/extensions/gata-lang
cd ~/.vscode/extensions/gata-lang
npm run compile   # builds server/dist/server.js
```
Restart VS Code and open a `.g` file — the colors apply on top of whatever
theme you're currently using, and the language server starts automatically.

## Design

Gold is Gata's signature color, reserved for data types; everything else is
built around it so types always stand out:

| Color | Meaning |
|---|---|
| Off-white | Default — variables, parameters |
| Off-white, barely cooler | Operators — deliberately *almost* the same as plain identifiers, just enough to tell them apart up close |
| Teal | Method/function names |
| Cobalt blue | Declaration keywords — `let`, `class`, `func`, `as`, `static`, ... — and `self` |
| Sage green | Branching/looping/control-transfer — `if`, `else`, `while`, `for`, `switch`, `case`, `try`, `catch`, `match`, `break`, `continue`, `return`, `default`, ... `return` lives here (it transfers control, like `break`/`continue`, rather than declaring something); `default` lives here too since it's overwhelmingly a switch/match case label, pairing visually with `case` |
| Muted violet | The structural/meta layer: `kernel`/`user`/`process`/`thread`/`entry` and `@intrinsic`/`@preamble`/`@extern`/`@environment` — compiler-contract surface, not logic |
| Gold | Primitive value types (`int`, `bool`, `float`, ...) |
| Bright gold | Class/module reference types (`String`, `List`, a user class) |
| Citrine (cooler, more green-leaning yellow) | Parens/brackets `() []` in ordinary Gata code — including inside `unsafe { }` (only the block's own outer `{ }` go risk maroon, not these). Deliberately a different yellow than the two golds above, so `List[String]()` doesn't blur into one indistinguishable smear — `[`, `String`, `]`, `(`, `)` each stay tellable apart. Raw C inside `native { }` is the one exception — see the flat-grey row below |
| Bronze, italic | Generic parameters — Gata's own convention of a bare single letter (`T`, `K`, `V`, `U1`) |
| Champagne, bold | `true` / `false` / `null` — literal values, part of the gold/type family |
| Amber | Strings, chars, numbers |
| Grey | Comma/dot/braces. Also a literal empty parens pair `()` — a no-arg call/ctor — which renders grey instead of the gold parens/brackets otherwise use, since there's nothing inside to draw attention to |
| Maroon, bold | The risk surface: `unsafe`, `defer`, `throw`/`throws`, `panic`, `native`/`native type`, and ONLY the outermost delimiting braces of `unsafe{}`/`native{}` — nested braces inside (from an `if`/`while`/etc. body) and all parens/brackets stay their normal color, not maroon |
| Grey, no highlighting | Raw C inside `native { }` / `native type X { }` / `fields { }` — deliberately flat, marking "you've left Gata syntax," with NO sub-highlighting at all, including parens/brackets. Scoped as `comment.block` so it stays grey even under a non-Gata theme |

Only `foreground` (and `fontStyle`) are ever set — no scope sets a `background`.

### How the risk-region recoloring stays robust under nesting

`unsafe { ... }` bodies are ordinary parsed Gata code (a real `Block`, confirmed
in `Parser.cs`'s `ParseUnsafeBlock`), not raw C — so naively scoping it as a
`begin`/`end` TextMate rule with `end: "\\}"` breaks the moment the body
contains *any* nested brace (an `if`/`while`/function body), because that
inner closing `}` would match the outer rule's bare `end` pattern and close
the whole `unsafe{}` region right there — well before the real end.

The fix (`#riskBraceBlock` in the grammar) is the standard TextMate technique
for this: every `{` encountered while inside a risk region is intercepted by
its own nested `begin`/`end` rule before it can ever fall through to a flat
brace match, and that nested rule recurses into the same risk-coloring token
set (`#riskBody`) for its contents. Each level of nesting gets its own
properly paired region, so a `}` only ever closes the *innermost* currently
open one — exactly like balanced-bracket matching, just expressed as nested
grammar scopes instead of an explicit counter. `native { ... }`'s raw-C body
already used this same self-recursive pattern (`#nativeInner`) for its own
nested braces; `#riskBraceBlock` is the same idea applied to real Gata code
instead of a flattened blob.

## Known heuristic limits

This is a regex-based grammar, not the real type checker, so a few shapes are
genuinely ambiguous without semantic info:

- A bare PascalCase identifier with **no** trailing `(` is always treated as a
  type reference (gold) — this is also how it would classify a free function
  referenced *as a value* (`let cb = AddOne;`, `[AddOne, Double]`), since that
  looks identical to a type reference with no other context to go on.
- A union variant declared with a payload (`Circle(float radius)`) renders as a
  plain identifier (off-white), not gold, because it has the same "identifier
  immediately followed by `(`" shape as a method declaration/call — which is
  exactly the shape excluded from the class-name rule so that `Main()` and
  `Console.PrintLine(...)` don't get colored as types. A no-payload variant
  (`Point`) isn't affected and still renders gold.

Both are cosmetic-only; nothing here affects the compiler.

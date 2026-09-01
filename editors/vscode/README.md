<p align="center">
  <img src="assets/gata-full.png" alt="Gata" width="700">
</p>

<h1 align="center">Gata for VS Code</h1>

<p align="center">
  <img src="https://img.shields.io/badge/extension-v2.3.0-00e676" alt="Extension v2.3.0">
  <img src="https://img.shields.io/badge/vscode-%5E1.75.0-1263cf" alt="VS Code ^1.75.0">
  <img src="https://img.shields.io/badge/languages-.g%20%7C%20.gconf-e0b34d" alt="Languages">
</p>

Editor support for [The Gata Programming Language](https://github.com/ApparentlyPlus/Gata) and its project manifests. It colors a file from what the code actually declares rather than from what the identifiers look like, reports syntax errors as you type using a port of [Appa](https://github.com/ApparentlyPlus/Appa)'s own lexer and parser, and hands the file to the real compiler on save for everything a parser cannot know.

There is no build step to run before using it and nothing to configure. Open a `.g` file and it starts.

## Table of Contents

- [What You Get](#what-you-get)
- [Installing](#installing)
- [Building a VSIX](#building-a-vsix)
- [How the Coloring Works](#how-the-coloring-works)
- [The Palette](#the-palette)
- [Diagnostics](#diagnostics)
- [Settings](#settings)
- [Project Manifests](#project-manifests)
- [Repository Layout](#repository-layout)
- [Known Limits](#known-limits)
- [What Changed in v2.3.0](#what-changed-in-v230)
- [What Changed in v2.2.0](#what-changed-in-v220)

## What You Get

| Feature | What it does |
|---|---|
| **Semantic highlighting** | The language server classifies every identifier from its declaration: a generic parameter is colored as one because it was declared as one, a variant because its union declares it, a method because of what sits left of the dot. |
| **Syntax highlighting** | A TextMate grammar covering every token the lexer produces, including realms, processes, threads, scope qualifiers, generics, operator declarations, interpolation holes, and raw C bodies. It is the layer that paints before the server answers. |
| **Illegal shapes, marked** | An unknown annotation, a role outside the closed `@intrinsic` vocabulary, a malformed numeric literal, a bad escape, a name starting with two underscores, a prefix `++`: all of them are colored as errors by the grammar alone. |
| **Live syntax diagnostics** | The ported lexer and parser run in process on every keystroke, with the compiler's own codes, messages and help lines. |
| **Real semantic diagnostics** | On open and on save, `appa check` runs over the project the file belongs to and its output becomes squiggles, help lines included. |
| **Imports, followed** | An `import` names a file, so the server reads it. `import Span;` resolves to `<stdlib>/Span.g` and `import "src/Syntax/Ast.g";` to that path under the project root, transitively, exactly as `appa` resolves them. Every name those files declare is colored for what it is, and the standard library is marked as such. |
| **Hovers** | Every keyword, annotation and primitive carries an explanation of the rule behind it. Hovering a name declared in the file, or in anything it imports, shows the declaration as written. |
| **Outline and breadcrumbs** | Types, methods, operators, enum members, union variants, realms, processes and threads, each under what contains it. |
| **Completion** | Keywords, primitives, annotations, everything the current file declares and everything it imports, each with the same documentation the hover shows. |
| **Themes** | `Gata Canopy` (dark) and `Gata Daylight` (light), both entirely optional and never selected for you. The extension does not need any of them: the palette lands as foreground-only defaults on top of whatever theme you already use, and follows it from dark to light. |

## Installing

If you have a `.vsix`:

```bash
code --install-extension gata-highlighting-2.3.0.vsix
```

For development against a checkout, link it into your extensions folder and build the server once:

```bash
cp -r editors/vscode ~/.vscode/extensions/gata
cd ~/.vscode/extensions/gata
npm install          # the language client, used by extension.js
npm run compile      # installs and bundles the server into server/dist/server.js
```

Restart VS Code and open a `.g` file. The colors apply over your current theme, and the language server starts on its own.

> [!NOTE]
> `npm run compile` is what produces `server/dist/server.js`. Without it the extension still highlights, but hovers, the outline, completion and diagnostics are all unavailable, and you get a warning saying so.

## Building a VSIX

You need **Node 18 or newer**. Everything else is fetched by npm.

```bash
cd editors/vscode
npm install
npm run package
```

That runs [`@vscode/vsce`](https://github.com/microsoft/vscode-vsce), which triggers `vscode:prepublish`, which installs the server's dependencies and bundles it with esbuild before packaging. The result is `gata-highlighting-2.3.0.vsix` in the same folder.

To do it by hand, or to pin a version of `vsce`:

```bash
npm install -g @vscode/vsce
cd editors/vscode
npm install
npm run compile
vsce package
```

Useful checks along the way:

```bash
vsce ls --tree                        # every file that would go into the package
npm --prefix server run build         # rebuild only the server bundle
cd server && npx tsc --noEmit         # typecheck the server without emitting
```

What ends up in the package is the extension entry point, the grammars, the theme, the language configurations, the manifest schema, `server/dist/server.js`, and the language client from `node_modules`. `.vscodeignore` keeps the TypeScript sources, the server's `node_modules` and the build metadata out, since the server ships as one bundled file.

> [!TIP]
> `vsce package` refuses to run with a dirty `dist/`, a missing `README.md`, or a version that does not parse. If it complains about a repository field, that is a warning and not a failure.

## How the Coloring Works

Two layers, in this order.

**The grammar** (`syntaxes/gata.tmLanguage.json`) paints immediately, from shape alone. It knows the structure of the language, so it can be far more precise than a keyword list: a `[T, U]` after a class name is a parameter list and colors as parameters, while a `[String, List[int]]` in a type is an argument list and colors as types. It reads declaration heads as regions, so a parameter name is told apart from its type, an operator symbol from the `func` in front of it, and a union variant from a call. Raw C inside `native { }`, `native type X { }` and `fields { }` is deliberately flat, marking the point where you have left Gata.

**The language server** then classifies the same file properly and sends semantic tokens back. This is where guessing stops. `class Box[Element]` gives `Element` the generic-parameter color everywhere it appears, no matter how many letters it has. `Shape.Circle` is a union variant because `Shape` is a union that declares it. `Shape[int].Circle` is the same variant, because the qualifier steps back over the type arguments. `Dir.North` is an enum member for the same reason. A call is a function, a method declared in a class body is a method at its declaration and not only at its call sites, a field is a property, a `let` binds a variable, a parameter list binds parameters.

It reads the file's imports to do it. `server/src/imports.ts` resolves each one the way `Pipeline.ResolveOne` does in the compiler — a bare `import Name;` is `<stdlib>/Name.g`, a quoted `import "a/b.g";` is that path under the project root — and follows the graph transitively, because a Gata name is visible to a file exactly when it is declared somewhere in the closure of its imports. Nothing is keyed off a built-in list of module names: `import Span;` is a stdlib union because `Span.g` says `union Span[T]`, and a module you write yourself is read the same way. Each file is cached against its mtime, so the walk costs a `stat` per import after the first read.

Both sets of colors ship as configuration *defaults*, contributed from `package.json`. Nothing is written to your `settings.json`, no color theme is selected for you, and your current theme keeps every one of its own colors: the extension only adds foreground rules whose TextMate scopes all end in `.gata` and whose semantic selectors are all qualified with `:gata`, neither of which any other grammar produces. Outside a `.g` file nothing changes at all.

Because they are defaults, they are also the lowest-priority value there is. Put an `editor.tokenColorCustomizations` or `editor.semanticTokenColorCustomizations` of your own in `settings.json` and yours wins outright — which is the supported way to recolor a role you disagree with.

The palette ships twice. The dark ramp is the base; the light one sits under a `"[*Light*]"` key,
which VS Code matches against the name of the theme you have selected. Every built-in light theme —
`Light Modern`, `Light+`, `Quiet Light`, `Solarized Light` — carries `Light` in its name and picks it
up, and so do almost all third-party ones. A light theme that does not say so in its name will get
the dark ramp; adding a key for it by name in your own settings is a two-line fix, and yours wins.

Builds up to 2.0.0 did write the palette into global settings instead. Upgrading takes those entries back out once, so you get your `settings.json` back; anything in there that was not written by the extension is left alone.

It also turns off VS Code's bracket pair colorization for `.g` files only, so parentheses and brackets keep the grammar's color instead of cycling by nesting depth.

## The Palette

Gata reads in green. The logo's hues — `#00c795` through `#00e676` — are the centre of gravity, and
almost everything the program *is* sits in that family: types, calls, declaration keywords, control
flow. What is left of green is used sparingly and on purpose, so each remaining hue means one thing.

The palette exists twice, as one table with two grounds. The dark ramp is `Canopy Azure`, tuned
against `#1f1f1f`; the light ramp is `Daylight`, tuned against `#ffffff`. VS Code picks between them
from the theme you are using, so nothing needs setting.

**Green: what the program is made of.**

| Dark | Light | Meaning |
|---|---|---|
| Turquoise | Deep turquoise | Declared type names: `class Point`, `enum Dir`, `union Shape` |
| Darker turquoise | Teal | Type references |
| Sage | Moss | The standard library's types, and generic parameters |
| Spring green | Forest green | Functions and methods, and operator symbols in a declaration |
| Deep teal | Pine | Declaration keywords: `let`, `class`, `func`, `new`, `import`, ... and `self`, in italic |
| Mid teal | Green | Control flow: `if`, `while`, `for`, `match`, `try`, `catch`, `return`, `assign`, ... |
| Lime | Olive | Primitive types: `int`, `bool`, `usize`, ... |

**The other hues, one meaning each.**

| Dark | Light | Meaning |
|---|---|---|
| Steel cyan | Deep cyan | Module names in front of a dot, and a `kernel.` qualifier |
| Violet | Purple | Topology: `realm`, `kernel`, `userspace`, `process`, `thread`, `foreground`, `background` |
| Pale violet | Indigo | Realm, process and thread names, and the `::` qualifier |
| Dusty rose | Rose | The seven annotations, and their arguments a shade lighter |
| Coral | Brick | The risk surface: `unsafe`, `defer`, `throw`, `throws`, `panic`, `native`, `fields`, and only the outermost braces of `unsafe { }` and `native { }` |
| Cream | Ochre | Enum members, union variants, and `true` / `false` / `null` in bold |
| Amber | Ochre | Strings, chars and numbers |
| Grey-green | Grey-green | Modifiers: `public`, `private`, `static`, `entry`, `ref` |
| Off-white | Near-black | Variables, parameters and properties |
| Grey | Grey | Braces, brackets, commas, accessors, operators, comments, and raw C inside a native block |
| Red | Red | Shapes the compiler rejects outright |

Only foreground colors and font styles are ever set. Nothing sets a background. The only italics are
comments and `self`; the only bold is `true` / `false` / `null`.

Two distinctions are worth naming, because both were collisions in the v2.0 palette and both are
fixed by the server rather than by guesswork. A primitive can never read as a type: `int` is lime and
`Ring` is turquoise, far enough apart to be told apart at a glance. And `realm kernel` can never read
as `Console.PrintLine`: a `namespace` token carries the `declaration` modifier when it names a realm,
a process or a thread, and does not when it is the module in front of a dot, so the two take
different colors from the same token type.

`Gata Canopy` and `Gata Daylight` carry the whole palette as full color themes, with editor chrome to
match, if you would rather switch to one than overlay it. Pick either from `Preferences: Color Theme`.

### Why the risk regions survive nesting

`unsafe { ... }` holds ordinary Gata code, not raw C, so a naive `begin`/`end` rule ending at the first `}` would close the block at the end of the first nested `if` body. Every `{` inside a risk region is instead claimed by its own nested region, which recurses into the same rule set for its contents. Each level gets a properly paired region, so a `}` only ever closes the innermost one that is open. `native { }` uses the same technique for its raw C, and for the same reason the lexer's balanced reader does: a brace inside a comment or a string literal must not move the depth.

## Diagnostics

**Syntax, on every keystroke, in every file.** `server/src/lexer.ts` and `server/src/parser.ts` are ports of Appa's `Lexer.cs` and `Parser.cs`: the same token rules, the same recursive descent, the same codes, messages and hints. A process without a mode, a `thread` outside a process, a trailing comma, a `kernel` missing its `realm`, an assignment inside a condition, explicit type arguments at a call site, a process variable with no initial value: all of them are reported where they are written, with the same help lines the compiler prints. The one-line meaning of the code is appended, so `G060` says what `G060` is.

This layer runs in process with no external dependency, so it works on a loose `.g` file that belongs to no project at all.

**Semantics, on open and on save, in project files.** `server/src/semantic.ts` walks upward for a `*.gconf`. If it finds one, it runs `appa check` over that project, which is the full front end with no emission, and turns its output back into squiggles tagged `appa`. Type errors, undefined names, unmarked shadows, non-exhaustive matches and everything else in the `G000` to `G102` table come from the real compiler. Nothing about them is approximated here.

## Settings

| Setting | Default | What it does |
|---|---|---|
| `gata.enableSemanticChecks` | `true` | Whether to run `appa check` on open and on save. Turning it off leaves the always-on syntax layer untouched. |
| `gata.appaPath` | auto | An `Appa.dll` to run through `dotnet`, or a standalone `appa` binary. Empty means: look for a build of `Appa.csproj` next to this checkout, then fall back to an `appa` on `PATH`. |
| `gata.libgataPath` | auto | The directory passed to `appa check` as `--stdlib`. Empty means: look for a sibling `Gata/libgata`, otherwise rely on the toolchain `appa install` put in place. |

With nothing configured, the defaults describe the PawStack layout this extension ships from, so a monorepo checkout works without touching anything.

## Project Manifests

A `.gconf` is registered as its own language, colored with VS Code's built-in XML grammar and validated in process by the same server, so no third-party XML extension is required. The validator mirrors `Appa/src/CLI/Manifest.cs`:

| Reported | Severity |
|---|---|
| A root that is not `<appa>`, or an empty file | Error |
| A value outside the set appa accepts, with a "did you mean" | Error |
| An unknown or misspelled element, with a "did you mean" | Warning |
| The same element set twice | Warning |
| An empty `<ProjectName>` | Warning |
| A value in non-canonical case, such as `release` for `Release` | Hint |

Values are compared case-insensitively, exactly as appa parses them, which is why a lowercase value is a hint rather than an error. Content inside `<!-- -->` and `<![CDATA[ ]]>` is masked before scanning, so a commented-out element is never reported.

An XSD ships in `schemas/gconf.xsd` for anyone who would rather point the Red Hat XML extension at it. Nothing here depends on it.

## Repository Layout

```
editors/vscode/
├── extension.js                     Activation, the language client, the 2.0.0 settings cleanup
├── package.json                     Contributions and settings
├── assets/                          The extension icon, the file icon, the wordmark
├── gata-config.json                 Comments, brackets, auto-closing pairs for .g
├── gconf-config.json                The same for .gconf
├── syntaxes/
│   ├── gata.tmLanguage.json         The grammar
│   └── gconf.tmLanguage.json        A thin wrapper over the built-in XML grammar
├── themes/
│   ├── gata-canopy.json             The optional full theme, dark
│   └── gata-daylight.json           The same palette as a light theme
├── schemas/
│   └── gconf.xsd                    A manifest schema for external XML tooling
└── server/
    ├── src/lexer.ts                 Port of Appa's Lexer.cs
    ├── src/parser.ts                Port of Appa's Parser.cs, diagnostics only
    ├── src/token.ts                 Port of Appa's TK enum
    ├── src/codes.ts                 The G000 to G102 table, with one-line meanings
    ├── src/semtokens.ts             Semantic classification, behind the colors
    ├── src/imports.ts               Import resolution, the cross-file name index
    ├── src/symbols.ts               Declarations, behind the outline and the hovers
    ├── src/language.ts              Keyword, annotation and primitive documentation
    ├── src/semantic.ts              The 'appa check' bridge
    ├── src/gconf.ts                 Manifest validation
    └── src/server.ts                The LSP wiring
```

## Known Limits

Both layers read one file at a time and neither is a type checker, so a few things are out of reach without the compiler:

- A name a file never declares is classified from context. `let cb = AddOne;` gives `AddOne` the type color, because a bare capitalized name used as a value looks exactly like a type reference.
- Imports are followed, but only to their declarations. The server knows that another file declares `Shape` and that `Shape` has a `Circle`, not what type an arbitrary expression has, so `other.Thing` behind a local variable is still a property rather than whatever it really is. Anything that depends on inferring a type is left to `appa check`.
- An import that cannot be resolved — a loose file with no `*.gconf` above it and no reachable `libgata` — leaves the module name colored as a library type and contributes no other names. Point `gata.libgataPath` at a checkout to fix it.
- The syntax layer reports the first error in a file, exactly as the compiler's parser does, rather than recovering and continuing.

None of this affects the compiler. It is all cosmetic, or it is a diagnostic the real one repeats.

## What Changed in v2.3.0

- **Imports are followed.** `import Span;` used to leave `Span` colored as a plain variable, because
  the server carried a hardcoded list of standard-library module names and `Span` was not on it. That
  list is gone. What succeeds an `import` is resolved to a file, the file is read, and its
  declarations are what decide the color — transitively, and by the same rule the compiler uses. A
  name from another file is now a class, an enum, a union or a function because that is what it was
  declared as, and the standard library is marked as such because of where the file it came from
  lives, not because of what it is called.
- **Hovers and completion cross files too.** Hovering an imported name shows its declaration as
  written; completion offers everything the closure of the imports declares.
- **Annotations no longer swallow their argument.** `@intrinsic(alloc)` is one token in the lexer,
  whose span runs to the closing parenthesis, so the semantic layer painted the argument and the
  parentheses as part of the keyword. Only `@intrinsic` is painted now, and the grammar's own colors
  for the role and the brackets come back.
- **Fields are properties, methods are methods.** A field declaration in a class body was colored as
  a local variable while `self.field` was colored as a property; a method declaration was colored as
  a free function while its call sites were colored as methods. Both now agree with themselves.
- **`Shape[int].Circle` is a variant.** The owner of a member access is now found by stepping back
  over the type argument list, so a qualified variant or enum member on a generic type is no longer
  read as a property, and constructing a variant is no longer read as a method call.
- **Enum members are declarations** where they are declared, matching union variants, and a
  `native type` name is now colored as the class it declares.
- **A one-letter module import.** `import S;` matched the grammar's generic-parameter shape before
  anything else; imports are now read as imports.

## What Changed in v2.2.0

- **A new palette, on both grounds.** `Canopy Azure` on dark and `Daylight` on light, built from the
  logo's greens rather than around them. Roughly half the colored ink on a page is now green, where
  the v2.0 palette put more than half of it in blue and amber.
- **Two collisions gone.** A primitive can no longer be mistaken for a type, and a realm name can no
  longer be mistaken for a module: `namespace.declaration` and `namespace` are now colored apart. No
  pair of roles that has to be told apart sits closer than ΔE 18 on either ground.
- **It follows your theme from dark to light.** The light ramp is a separate table tuned against
  white, not an inversion — every role clears 4.5:1 there, which no previous palette did.
- **Fewer italics.** Parameters and generic parameters stand upright now. Comments and `self` are the
  only slanted things left.
- **Two optional themes.** `Gata Canopy` and `Gata Daylight` carry the palette as full themes, with
  editor chrome to match.

## What Changed in v2.1.0

- **The palette stopped touching your settings.** It ships as contributed defaults now, so no color theme is ever selected for you and `settings.json` is never written. Entries an older build left behind are removed once, on the first launch after the upgrade.
- **Squiggles land on the right span.** `appa` reports the width of the offending span only as the caret row under the source snippet, which the client used to throw away, underlining a single character at the start of the statement instead. It reads the carets now, so `undefinedThing` is underlined, not the `l` of the `let` in front of it.
- **A smaller file icon.** The mark was 13px wide in a 16px slot, wider than every icon around it in the explorer and flush against the left edge. Its canvas grew so the mark lands at 11.5px, with the same left bearing as the rest of the tree.

## What Changed in v2.0.0

The extension was rebuilt around the language server rather than around the grammar.

- **Semantic highlighting**, which is new. The server classifies identifiers from their declarations and the editor paints them over the grammar, which is what finally makes generics, variants, enum members and members-after-a-dot correct instead of approximated.
- **Hovers, an outline and completion**, all new, all driven by the same reading of the file.
- **A rewritten grammar.** Declaration heads are regions now, so generic parameter lists, parameter names, operator symbols, union variants, enum members and match bindings each get their own scope. Illegal shapes are colored as errors.
- **The current language.** `realm kernel` and `realm userspace` replace the old `kernel`/`user` blocks, `::` and `kernel.` qualifiers are understood, `@shadows` is recognised, process variables parse, and `process`, `thread` and `native` are treated as the contextual keywords they are.
- **A full port refresh.** The lexer, the parser, and the diagnostic table now match Appa v2.0.0, including its messages and its help lines. The whole of `libgata` parses clean.
- **A rebuilt palette** with distinct colors for declared types, type references, variants, enum members, parameters and namespaces, and an overlay that now covers semantic colors as well as TextMate scopes.

## License

This extension is part of the [Gata](https://github.com/ApparentlyPlus/Gata) repository and is covered by that repository's license.

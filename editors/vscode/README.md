<h1 align="center">Gata for VS Code</h1>

<p align="center">
  <img src="https://img.shields.io/badge/extension-v2.0.0-e0b34d" alt="Extension v2.0.0">
  <img src="https://img.shields.io/badge/vscode-%5E1.75.0-1263cf" alt="VS Code ^1.75.0">
  <img src="https://img.shields.io/badge/languages-.g%20%7C%20.gconf-7fc4b8" alt="Languages">
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
- [What Changed in v2.0.0](#what-changed-in-v200)

## What You Get

| Feature | What it does |
|---|---|
| **Semantic highlighting** | The language server classifies every identifier from its declaration: a generic parameter is colored as one because it was declared as one, a variant because its union declares it, a method because of what sits left of the dot. |
| **Syntax highlighting** | A TextMate grammar covering every token the lexer produces, including realms, processes, threads, scope qualifiers, generics, operator declarations, interpolation holes, and raw C bodies. It is the layer that paints before the server answers. |
| **Illegal shapes, marked** | An unknown annotation, a role outside the closed `@intrinsic` vocabulary, a malformed numeric literal, a bad escape, a name starting with two underscores, a prefix `++`: all of them are colored as errors by the grammar alone. |
| **Live syntax diagnostics** | The ported lexer and parser run in process on every keystroke, with the compiler's own codes, messages and help lines. |
| **Real semantic diagnostics** | On open and on save, `appa check` runs over the project the file belongs to and its output becomes squiggles, help lines included. |
| **Hovers** | Every keyword, annotation and primitive carries an explanation of the rule behind it. Hovering a name declared in the file shows the declaration as written. |
| **Outline and breadcrumbs** | Types, methods, operators, enum members, union variants, realms, processes and threads, each under what contains it. |
| **Completion** | Keywords, primitives, annotations and everything the current file declares, each with the same documentation the hover shows. |
| **A theme** | `Gata Gold`, optional. The extension does not need it: its colors are applied as an overlay on top of whatever theme you already use. |

## Installing

If you have a `.vsix`:

```bash
code --install-extension gata-highlighting-2.0.0.vsix
```

For development against a checkout, link it into your extensions folder and build the server once:

```bash
cp -r editors/vscode ~/.vscode/extensions/gata-lang
cd ~/.vscode/extensions/gata-lang
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

That runs [`@vscode/vsce`](https://github.com/microsoft/vscode-vsce), which triggers `vscode:prepublish`, which installs the server's dependencies and bundles it with esbuild before packaging. The result is `gata-highlighting-2.0.0.vsix` in the same folder.

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

**The language server** then classifies the same file properly and sends semantic tokens back. This is where guessing stops. `class Box[Element]` gives `Element` the generic-parameter color everywhere it appears, no matter how many letters it has. `Shape.Circle` is a union variant because `Shape` is a union that declares it. `Dir.North` is an enum member for the same reason. A call is a function, a member is a property, a `let` binds a variable, a parameter list binds parameters.

The extension writes both sets of colors into your global settings as an overlay. Every TextMate scope it writes ends in `.gata` and every semantic rule is qualified with `:gata`, neither of which any other grammar produces, so nothing outside a Gata file can be affected. Re-running the extension replaces its own rules and leaves any you wrote alone.

It also turns off VS Code's bracket pair colorization for `.g` files only, so parentheses and brackets keep the grammar's color instead of cycling by nesting depth.

## The Palette

Gata reads in green and gold. Gold is what the program is made of: types, values, literals. Green and the blues either side of it are what the program does: control flow, functions, declarations. The split is the point, and it is why a `.g` file can be skimmed for shape before it is read for detail.

**The gold half: data.**

| Color | Meaning |
|---|---|
| Bright gold | Declared type names: `class Point`, `enum Dir`, `union Shape` |
| Gold | Type references, and the standard library's types |
| Muted gold | Primitive types: `int`, `bool`, `usize`, ... |
| Amber gold | Union variants |
| Bronze, italic | Generic parameters |
| Champagne | Enum members, and `true` / `false` / `null` |
| Amber | Strings, chars and numbers |

**The green and blue half: behavior.**

| Color | Meaning |
|---|---|
| Sage green | Control flow: `if`, `while`, `for`, `switch`, `match`, `try`, `catch`, `return`, `assign`, ... |
| Teal | Functions, methods, and operator symbols in a declaration |
| Cobalt blue | Declaration keywords: `let`, `class`, `func`, `new`, `import`, ... and `self` |
| Steel blue | Modifiers: `public`, `private`, `static`, `entry`, `ref`, and the `as` and `sizeof` operators |

**Everything else.**

| Color | Meaning |
|---|---|
| Violet | Topology: `realm`, `kernel`, `userspace`, `process`, `thread`, `foreground`, `background`, and the seven annotations |
| Light violet | Realm, process and thread names, and a `::` or `kernel.` qualifier |
| Maroon | The risk surface: `unsafe`, `defer`, `throw`, `throws`, `panic`, `native`, `fields`, and only the outermost braces of `unsafe { }` and `native { }` |
| Off-white | Variables, properties and operators. Parameters are the same color, in italic |
| Citrine | Parentheses and brackets, a cooler yellow than the golds so `List[String]()` does not blur into one smear |
| Grey | Braces, commas, accessors, and raw C inside a native block |
| Red | Shapes the compiler rejects outright |

Only foreground colors and font styles are ever set. Nothing sets a background.

The `Gata Gold` theme carries this whole palette, greens and blues included, as a full color theme with the editor chrome to match, if you would rather switch to it than overlay it. Pick it from `Preferences: Color Theme`.

### Why the risk regions survive nesting

`unsafe { ... }` holds ordinary Gata code, not raw C, so a naive `begin`/`end` rule ending at the first `}` would close the block at the end of the first nested `if` body. Every `{` inside a risk region is instead claimed by its own nested region, which recurses into the same rule set for its contents. Each level gets a properly paired region, so a `}` only ever closes the innermost one that is open. `native { }` uses the same technique for its raw C, and for the same reason the lexer's balanced reader does: a brace inside a comment or a string literal must not move the depth.

## Diagnostics

**Syntax, on every keystroke, in every file.** `server/src/lexer.ts` and `server/src/parser.ts` are ports of Appa's `Lexer.cs` and `Parser.cs`: the same token rules, the same recursive descent, the same codes, messages and hints. A process without a mode, a `thread` outside a process, a trailing comma, a `kernel` missing its `realm`, an assignment inside a condition, explicit type arguments at a call site, a process variable with no initial value: all of them are reported where they are written, with the same help lines the compiler prints. The one-line meaning of the code is appended, so `G060` says what `G060` is.

This layer runs in process with no external dependency, so it works on a loose `.g` file that belongs to no project at all.

**Semantics, on open and on save, in project files.** `server/src/semantic.ts` walks upward for a `*.gconf`. If it finds one, it runs `appa check` over that project, which is the full front end with no emission, and turns its output back into squiggles tagged `appa`. Type errors, undefined names, unmarked shadows, non-exhaustive matches and everything else in the `G000` to `G101` table come from the real compiler. Nothing about them is approximated here.

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
├── extension.js                     Activation, the color overlay, the language client
├── package.json                     Contributions and settings
├── gata-config.json                 Comments, brackets, auto-closing pairs for .g
├── gconf-config.json                The same for .gconf
├── syntaxes/
│   ├── gata.tmLanguage.json         The grammar
│   └── gconf.tmLanguage.json        A thin wrapper over the built-in XML grammar
├── themes/
│   └── gata-gold.json               The optional full theme
├── schemas/
│   └── gconf.xsd                    A manifest schema for external XML tooling
└── server/
    ├── src/lexer.ts                 Port of Appa's Lexer.cs
    ├── src/parser.ts                Port of Appa's Parser.cs, diagnostics only
    ├── src/token.ts                 Port of Appa's TK enum
    ├── src/codes.ts                 The G000 to G101 table, with one-line meanings
    ├── src/semtokens.ts             Semantic classification, behind the colors
    ├── src/symbols.ts               Declarations, behind the outline and the hovers
    ├── src/language.ts              Keyword, annotation and primitive documentation
    ├── src/semantic.ts              The 'appa check' bridge
    ├── src/gconf.ts                 Manifest validation
    └── src/server.ts                The LSP wiring
```

## Known Limits

Both layers read one file at a time and neither is a type checker, so a few things are out of reach without the compiler:

- A name a file never declares is classified from context. `let cb = AddOne;` gives `AddOne` the type color, because a bare capitalized name used as a value looks exactly like a type reference.
- Imports are not followed. A type from another file is colored as a type, but its members are not known, so `other.Thing` is a property rather than whatever it really is. Anything that depends on cross-file knowledge is left to `appa check`.
- The syntax layer reports the first error in a file, exactly as the compiler's parser does, rather than recovering and continuing.

None of this affects the compiler. It is all cosmetic, or it is a diagnostic the real one repeats.

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

# The Gata Programming Language

*A complete, book-length introduction to Gata and its compiler, appa*

## Foreword

Welcome to Gata.

This book will teach you how to use the Gata programming language, but more importantly, it will teach you a different approach to operating system development.

Traditionally, creating an operating system means working directly with low-level languages such as C or C++, manually configuring build systems, selecting kernel subsystems, managing memory layouts, wiring together drivers, handling privilege transitions, and dealing with thousands of implementation details before you can even begin writing the software you actually care about.

Pawstack is a toolchain I personally built meant to challenge that model. Its central idea is simple: **Your program is the operating system.**

Instead of writing an application that runs on top of an operating system, you write a Gata program that *becomes* the operating system itself.

- You describe your logic.
- The compiler determines what kernel functionality is required from GatOS.
- The toolchain assembles only the necessary operating system components.
- The final result is a complete, bootable x86 operating system image.
- No manual kernel configuration.
- No hand-written build pipelines.
- No maintaining dozens of subsystems you never use.

Just your code and appa, the Gata compiler.

## The PawStack Ecosystem

Gata is only one piece of a larger build system I decided to call **PawStack**. The full vision of the project is extensively laid out in the [GatOS Github Repository](https://github.com/ApparentlyPlus/GatOS), but for the purposes of this book, I'll reiterate it here.

PawStack consists of three major components:

### GatOS

GatOS is a highly modular operating system kernel that serves as the runtime foundation of the entire ecosystem.

Unlike traditional monolithic kernels where all functionality is compiled together regardless of use, GatOS is designed around composable subsystems.

Memory management, scheduling, synchronization primitives, userland support and countless other facilities exist as independent modules that can be included or excluded based on the needs of a specific project.

Most operating systems force developers to build on top of a fixed kernel. GatOS is designed so that the kernel itself can be shaped by the program being compiled.

### Appa

Appa is the Gata compiler.

Its role extends far beyond syntax checking and code generation.

Appa analyzes a Gata program, determines which operating system facilities it requires, generates the corresponding low-level implementation, configures GatOS accordingly, and constructs a custom kernel image tailored specifically to that application.

In a traditional software stack, a compiler produces an executable. In PawStack, Appa produces an operating system — and specifically, *your* operating system.

### Gata

Gata is the language that you, the developer, will interact with directly.

It is a statically typed systems programming language designed specifically around the needs of operating system development. Because of this, Gata differs syntax-wise from other programming languages you might know, although not by much.

Its goal is to make operating system development feel closer to writing a modern application, without forgoing the low level escape hatches that any serious kernel might need.

Features that traditionally require extensive boilerplate, intricate memory management, or deep knowledge of kernel architecture are elevated into first-class language constructs.

The language is intentionally designed around the realities of systems programming while attempting to eliminate as much accidental complexity as possible.

>[!NOTE]
> While Gata itself is complete as a language, several features that one might expect from it are missing. This isn't a design issue, but rather a scope issue. Libgata, Gata's standard library, cannot have any functionality that GatOS (its backend) does not implement. For this reason, networking and filesystems are currently **not supported, because GatOS does not implement them**. I am but a single student trying to finish my undergraduate thesis, so I couldn't realistically implement those too, especially on my own.

## The Compilation Pipeline

The complete PawStack build process looks like this:

```text
 Gata Source Code       # Your own Gata source
        │
        ▼
   Appa Compiler        # Syntactic + Lexical + Semantic Analysis
        │
        ▼
   Logic Analysis       # Feature extraction depending on your logic
        │
        ▼
 Custom GatOS Build     # Custom GatOS source code built for your logic
        │
        ▼
 Native Compilation     # GCC + GRUB + xorriso compilation and linking
        │
        ▼
 Bootable OS Image      # Kernel.bin + kernel.iso bootable images are emitted
```

The crucial difference is that the compiler (appa) is constructing an operating system architecture around the needs of the program.

A simple Hello World program may produce a tiny kernel image containing only a handful of required services. Empirically, **~2.5x** smaller than a full build. For reference, a full GatOS build might be **200KB** and a hello world program might be **~70KB** total.

Both are extremely small. The same language scales across both extremes.

## Hosted and Native Targets

Although Gata ultimately targets GatOS, the language also supports a hosted development environment.

In hosted mode, Gata programs compile into ordinary applications that run on a conventional operating system using a `libc` backend.

This allows developers to:

* Iterate rapidly
* Use mature debugging tools
* Leverage existing profilers
* Validate business logic
* Test algorithms without rebooting virtual machines

Once the logic is correct, the same code can be compiled into a native operating system image — with one structural adjustment covered in Chapter 4, since the two targets disagree about where the entry point lives.

Hosted mode exists as a development convenience. The language's true purpose remains operating system construction.

## What does appa compile to?

It is easy to think that appa compiles your Gata logic directly to machine code (assembly) and links it against a custom version of GatOS, as described. However, that is not what happens.

Appa is a pure transpiler, meaning it does nothing other than orchestrate the build and turn your Gata logic into pure C (and emit `.c`/`.h` files). That C code is then wired into the GatOS source, and when GCC compiles GatOS, it strips away whatever baggage is not needed by your program, by design.

Therefore, appa *transpiles* your Gata logic directly to C, and wires it into a GatOS backend template, which then gets stripped and compiled down to machine code by GCC.

## What This Book Assumes

This book assumes no prior knowledge of Gata.

Knowledge of systems programming, C, operating systems, or compiler design may help explain why certain features exist, but none are required.

Every concept is introduced before it is used. Examples begin with the smallest possible programs and gradually build toward complex ones.

By the end of this book, you will understand not only how to write Gata code, but also how appa transforms that code into a fully functioning operating system built on top of GatOS.

## How This Book Is Organised

The book is built bottom-up, in the order the compiler itself sees your program: first what a build *is*, then what a source file is made of lexically, then the type system those tokens describe, then the declarations that carry types, then the topology those declarations live in, then the statements and expressions inside them, and finally the machinery underneath — annotations, native interop, reference counting, and code generation.

That ordering has one consequence worth stating up front. A few constructs have to *appear* in examples before they are formally introduced, because there is no such thing as a Gata program without an entry point and a realm to hold it. Chapter 4 gives you that skeleton early, in full, precisely so the rest of the book can put fragments inside it without hand-waving. Whenever a fragment in this book is shown bare, mentally wrap it in the skeleton from Chapter 4.

Three conventions run throughout:

- **Diagnostic codes are named where they fire.** Gata's compiler assigns every error and warning a stable code, `G000` through `G101`. When the text says something is rejected, it names the code. Chapter 39 collects all of them in one table.
- **"WHY" is treated as part of the specification.** Where the compiler's behaviour is surprising, this book explains what the alternative would have cost. A rule you understand is a rule you stop tripping over.
- **Examples are real.** Every example here is written against the language as the compiler actually implements it, not against an idealised version of it.

## Table of Contents

**Part I: The Shape of a Build**

1. [Why Gata?](#1-why-gata)
2. [Files, the Toolchain, and the Project Manifest](#2-files-the-toolchain-and-the-project-manifest)
3. [How a Build Runs: the Pass Order](#3-how-a-build-runs-the-pass-order)
4. [The Minimal Complete Program](#4-the-minimal-complete-program)

**Part II: Lexical Structure**

5. [Comments, Identifiers, and Keywords](#5-comments-identifiers-and-keywords)
6. [Numbers, Characters, and Strings](#6-numbers-characters-and-strings)
7. [Interpolated Strings](#7-interpolated-strings)
8. [Operators and Punctuation as Tokens](#8-operators-and-punctuation-as-tokens)

**Part III: The Type System**

9. [Primitive Types](#9-primitive-types)
10. [Pointers](#10-pointers)
11. [Fixed-Size Arrays](#11-fixed-size-arrays)
12. [Function Pointer Types](#12-function-pointer-types)
13. [Declared Types and Builtin Types](#13-declared-types-and-builtin-types)
14. [Type Inference and the Full Type Grammar](#14-type-inference-and-the-full-type-grammar)

**Part IV: Declarations and Visibility**

15. [What May Appear at the Top Level](#15-what-may-appear-at-the-top-level)
16. [Modifiers and Visibility](#16-modifiers-and-visibility)

**Part V: User-Defined Types**

17. [Classes](#17-classes)
18. [Modules](#18-modules)
19. [Enums](#19-enums)
20. [Unions and Pattern Matching](#20-unions-and-pattern-matching)

**Part VI: Generic Programming**

21. [Generics and Monomorphization](#21-generics-and-monomorphization)

**Part VII: Realms, Processes, and Threads**

22. [Realms](#22-realms)
23. [Processes and Threads](#23-processes-and-threads)
24. [Process Variables](#24-process-variables)

**Part VIII: Statements and Expressions**

25. [Statements](#25-statements)
26. [Expressions](#26-expressions)

**Part IX: Operators and Conversions**

27. [Operator Overloading](#27-operator-overloading)
28. [Conversions and Casts](#28-conversions-and-casts)

**Part X: Handling Failure**

29. [Error Handling: `throws`, `throw`, `try`, `catch`, `assign`](#29-error-handling-throws-throw-try-catch-assign)

**Part XI: Names Across Scopes and Files**

30. [Scoping, Shadowing, and Scope Qualifiers](#30-scoping-shadowing-and-scope-qualifiers)
31. [Files, Imports, and Cross-File Names](#31-files-imports-and-cross-file-names)

**Part XII: The Machine Underneath**

32. [Annotations](#32-annotations)
33. [Native Interop](#33-native-interop)
34. [The Environment: Preambles and Floor Binds](#34-the-environment-preambles-and-floor-binds)
35. [The Memory Model](#35-the-memory-model)
36. [Dead Code, Capability Discovery, and Output Layout](#36-dead-code-capability-discovery-and-output-layout)
37. [The Standard Library: `libgata`](#37-the-standard-library-libgata)

**Part XIII: Reference**

38. [What Gata Does Not Have](#38-what-gata-does-not-have)
39. [Diagnostics Reference (G000–G101)](#39-diagnostics-reference-g000g101)
40. [Grammar Summary](#40-grammar-summary)
41. [Appendix: Keywords and Operator Precedence](#41-appendix-keywords-and-operator-precedence)
42. [A Program Using Most of the Language](#42-a-program-using-most-of-the-language)


# Part I: The Shape of a Build

Before any language feature matters, you need to know what a Gata build *is*: which files take part, what tool drives them, in what order the compiler looks at them, and what the smallest thing that compiles at all looks like. This part answers those four questions and nothing else. It is short on syntax deliberately — every construct it shows is introduced properly later — but by the end of it you will be able to read any example in this book and know exactly what would have to surround it to make it a program.

## 1. Why Gata?

For most of this book, Gata will feel like any other statically-typed, compiled language: you'll write variables, classes, generics, and error handling the same way you would in C#, Rust, or Swift. The one structural difference is what `appa build` produces at the end.

As we established, instead of producing an executable for some existing operating system to run, it can produce a bootable image that *is* the operating system — that target is called **GatOS**, and it's the reason Gata exists.

Everything else (the standard library, the type system, the tooling) is built so that writing for GatOS feels as close as possible to writing any other program, rather than feeling like writing an OS kernel in C.

That last part matters because writing a kernel in C normally means giving up nearly every convenience a modern language offers: no generics, no destructors, no operator overloading, manual reference counting (if any memory-management discipline at all).

Gata gives you those features back — classes, generics that are monomorphized rather than boxed, operator overloading, tagged unions with exhaustiveness checking, automatic reference counting, structural `for..in`, function pointers — without smuggling in the things a kernel genuinely can't have: no garbage collector, no exceptions-as-control-flow, no hidden virtual dispatch.

You also don't need to know how an OS works under the hood to use Gata productively. GatOS is built as a set of independent subsystems (memory management, input drivers, threading, and so on) and `appa` performs **capability discovery**: it scans your program for what it actually calls and links in only the matching subsystems, stripping the rest out of the build automatically (Chapter 36).

Writing a Gata program that never touches the keyboard, for instance, just doesn't pay for keyboard-driver code; you don't have to ask for that, and you don't have to know it happened.

Gata's only compilation target is C: every `appa build` run transpiles a Gata program into plain C, which is then handed to a regular C toolchain. That C can end up running in one of two places:

- **GatOS**: a freestanding x86_64 kernel target. This is what Gata is *for*. A Gata program compiled for GatOS produces a bootable kernel image, runnable directly in QEMU or on real hardware, optionally spawning user-space processes that run under that kernel's own scheduler.
- **Hosted**: an ordinary target that links against libc. This exists so you can develop and test the parts of your program that don't touch hardware directly on your host OS, with a real debugger, before ever booting the same source as a kernel.

The same language, the same grammar, and the same standard library (`libgata`) target both. If you've written C and wished for generics and a destructor, or written Rust/C#/Java and wished you could see exactly what the runtime is doing at every step, Gata is aimed at exactly that middle ground.

There is a second, quieter reason the language looks the way it does, and it is worth naming now because it explains most of the design decisions in the rest of this book: **Gata refuses to guess.** Where two readings of a piece of code are both plausible, the language does not pick one silently — it rejects the code and names the disambiguation. Assignment is not an expression, so `if (x = 1)` cannot be a typo that compiles. Conditions must be `bool`, so there is no truthiness to reason about. Narrowing a number needs a cast, mixing signed and unsigned in a comparison needs a cast, displacing an outer name needs an annotation, and a `match` that forgot a variant is an error rather than a fall-through. Every one of those rules costs you a few keystrokes exactly once and saves a class of bug permanently.

## 2. Files, the Toolchain, and the Project Manifest

Gata source files use the extension `.g`. There is no header/implementation split, no forward declaration, and no include order to maintain: a file declares things, and other files `import` it.

The compiler is `appa`. It is also the project manager, the toolchain installer, the build driver, and (for GatOS) the emulator launcher, so there is no separate build-system layer to learn. It transpiles Gata to C and then drives a bundled cross-toolchain over that C.

### The subcommands

```
appa install               install the toolchain, libgata, the environments, and the project template
appa update                the same, refreshing an existing installation (also self-updates appa)
appa new <name>            scaffold a project
appa check [flags]         run the front end only — parse, resolve, diagnose, emit nothing
appa build [flags]         a full build, up to the ISO
appa run   [flags]         build the ISO, then boot it in QEMU
appa clean [dir]           remove transpilation/, build/, and artifacts/
appa --version
appa --help
```

`appa install` is the one interactive command. It asks whether to add `appa` to your `PATH`, which needs elevated privileges; answering yes re-runs the installer elevated, and declining stops rather than half-installing. You can answer the question up front instead with `--with-path` or `--no-path`.

>[!NOTE]
> Appa is entirely cross platform, so if you are on Windows, just follow the instructions that appa itself gives you.

`appa update` does everything `install` does, non-interactively, against an installation that already exists — and it updates the `appa` binary itself, so it is how you move to a new release.

The distinction between `check`, `build`, and `run` is worth internalising early, because it maps onto how you will actually work. `appa check` runs the *front end* only: lexing, parsing, name resolution, type checking, and every semantic diagnostic in Chapter 39. It emits no C, invokes no C compiler, and produces no image, which makes it fast enough to run on every save. `appa build` runs the whole pipeline through to a bootable ISO. `appa run` builds and then boots the result in QEMU.

### Build and run flags

```
--env <file>          use this file as the environment, instead of discovering it
--entry <file>        use this file as the entry source, instead of discovering it
--stdlib <dir>        use this directory as libgata
--werror              treat warnings as errors
--pure-transpile      emit C and stop; skip .gconf resolution entirely
--emit-sourcemap      write sourcemap.json, mapping renamed internal symbols back to your names
```

`appa run` accepts all of those, plus two of its own:

```
headless              run QEMU with no SDL display
timeout=<30s|5m|1h>   kill the QEMU instance after this long
```

`--pure-transpile` is the loose-file escape hatch: it bypasses the project manifest completely, which is why it requires you to name both `--env` and `--entry` yourself. It is what you reach for when you want to read the C that a small fragment produces without building a project around it. `headless` combined with a serial-output build is the standard shape for a scripted boot test — the kernel's console output lands directly on your terminal, and `timeout=` guarantees the test terminates.

### The project manifest

A project is configured by exactly one `<name>.gconf` file in the project root. It is small XML, and it describes *what* to build:

```xml
<appa>
  <ProjectName>demo</ProjectName>
  <TargetBackend>GatOS</TargetBackend>          <!-- GatOS | Hosted -->
  <BuildMode>Debug</BuildMode>                  <!-- Debug | Release -->
  <OutputType>Framebuffer</OutputType>          <!-- Framebuffer | Serial -->
  <KeyboardSupport>Default</KeyboardSupport>    <!-- Default | External | Hotplug -->
  <CapabilityDiscovery>On</CapabilityDiscovery> <!-- On | Off -->
</appa>
```

| Element | Values | Meaning |
|---|---|---|
| `ProjectName` | any name | The project's name; names the output artifacts. |
| `TargetBackend` | `GatOS` \| `Hosted` | Which of the two targets from Chapter 1 to build for. This choice changes the structural rules your program must satisfy — see Chapter 4. |
| `BuildMode` | `Debug` \| `Release` | `Debug` is unoptimised with diagnostics enabled. `Release` is optimised, and rejects `debug`/`panic` statements outright rather than compiling them away (Chapter 25). |
| `OutputType` | `Framebuffer` \| `Serial` | GatOS's output device. |
| `KeyboardSupport` | `Default` \| `External` \| `Hotplug` | `Default` is PS/2 only; `External` adds USB; `Hotplug` adds dynamic (re)detection. |
| `CapabilityDiscovery` | `On` \| `Off` | `On` infers which kernel subsystems the program needs and links only those. `Off` assumes all of them (Chapter 36). |

Every value is parsed case-insensitively, and an unrecognised one is a manifest error that lists the accepted spellings.

What is deliberately *not* in the manifest is just as informative: there are no gcc flags, no entry-file setting, and no environment-file setting. `appa` owns the C toolchain invocation, discovers the entry file (`src/main.g` by convention), and discovers the environment file by looking for the `@environment` marker (Chapter 34). The manifest describes the *product*; it is not a build script.

### Your first project

```
appa new myos
cd myos
appa run
```

`appa new myos` creates:

```
myos/
  myos.gconf        # the build manifest
  env.g             # the target environment (Chapter 34)
  src/
    main.g          # your program's entry point
```

and writes a starter `src/main.g` along these lines:

```go
import Misc;
import Console;

realm kernel {
    entry func Main() {
        Misc.PrintBanner();
        Console.PrintLine("Hello from myos!");
    }
}

realm userspace {
    foreground process App {
        thread Main {
            entry func Run() {
                Console.PrintLine("Hello from userspace!");
            }
        }
    }
}
```

`Misc.PrintBanner()` draws the GatOS startup banner — a `libgata` nicety, not a requirement; delete the line and its `import Misc;` and the banner is gone.

`appa run` takes this file, produces a bootable image, and boots it in QEMU. When QEMU boots, use `ALT+TAB` to cycle through consoles — one for each user process, plus the kernel console. In this example there are two: the kernel's and `App`'s.

### What is kernel and what is user?

This is the first GatOS-specific idea you'll meet, and it's worth understanding now even though the full mechanics wait until Part VII. GatOS genuinely runs two different kinds of code: kernel code, and ordinary user-space code organised into processes and threads the way any OS runs your programs.

These aren't two coding conventions. They execute differently: kernel code runs as part of the boot sequence with direct hardware access, while user code is handed to a scheduler and time-sliced like any process on a normal OS. They are also emitted into *separate C translation units*, which is the mechanical reason the split has to be visible in the syntax at all.

Gata makes the split first-class (`realm kernel { }` and `realm userspace { }`) specifically so it is structurally impossible to write user-space logic that ends up compiled into the kernel, or vice versa. That's also why `entry func Main()` (the kernel's boot entry) and `entry func Run()` (a thread's start routine) live in visibly different places: they run in visibly different worlds.

For now, read `realm kernel { }` as "boot-time, privileged" and `realm userspace { }` as "scheduled, like a normal program". Chapter 22 makes good on the rest.

### The environment file

Alongside the manifest sits `env.g`, the **environment file**. You will almost never edit it; `appa` ships a working one for both targets. All you need to know now is that it exists, that exactly one file per build carries the `@environment` marker, and that it is what makes `Console.PrintLine` mean "write to the framebuffer" on GatOS and "write to stdout" on Hosted without the rest of the language knowing the difference.

It also does something less obvious that Chapter 4 depends on: the environment declares, by which raw-C preamble blocks it contains, *which realms the build has at all*. Chapter 34 covers it in full.

## 3. How a Build Runs: the Pass Order

You do not need to know how `appa` is built internally to write Gata. But knowing the *order* of its passes explains something you will otherwise find arbitrary: why a given mistake is reported where it is, and why two errors that feel similar are caught at visibly different moments.

A build runs these passes, in this order:

```text
Lexer
  → Parser
  → ScopeBinder        realm/process scopes, @shadows, scope qualifiers
  → Monomorphizer      stamp generic classes and unions
  → SymbolCollector    the declaration registry; @intrinsic / @builtin binding
  → TypeResolver       types, overloads, and every semantic diagnostic
  → Desugar            string interpolation, switch, match
  → CapabilityScan
  → DCE                dead code elimination
  → Densifier          symbol renaming
  → Ownership          ARC insertion, throws lowering, defer splicing
  → Emitter
  → C
  → gcc
```

Four consequences of this shape are worth carrying with you through the rest of the book.

**Scopes are bound before anything is resolved.** The ScopeBinder runs third, before any type exists. That is why `kernel` and `userspace` are hard keywords rather than contextual ones (Chapter 5): `kernel.Foo` has to be recognisable as a *scope qualifier* at a point in the pipeline where nothing knows what `Foo` is. It is also why an unmarked shadow (`G088`, Chapter 30) is reported so early and so bluntly.

**Generic types are stamped before generic functions.** The Monomorphizer runs over the syntax tree, before resolution; generic *functions* are stamped later, during resolution, once inference has decided what their type parameters are. This asymmetry has one visible consequence, covered in Chapter 21, and it is otherwise invisible.

**Nearly every semantic error comes from one pass.** TypeResolver is where types, overload resolution, visibility, exhaustiveness, `unsafe` requirements, and most of Chapter 39's table are decided. If a diagnostic mentions types at all, it came from here.

**Reference counting is the last thing that happens to your code.** The Ownership pass runs after dead-code elimination and after renaming, which is why nothing you write can observe it and why the emitted C is the only place you can see it (Chapter 35).

One more detail matters in practice: **the front end re-runs, up to six rounds, when resolution discovers new generic instantiations.** Resolving one function body can reveal that `List[Point]` is needed, which stamps a new class, whose own bodies may in turn name `Optional[Point]`, and so on. The loop terminates at six rounds, which is also where the "type arguments nest at most 6 deep" limit in Chapter 21 comes from.

## 4. The Minimal Complete Program

Everything in this book after this chapter is a fragment. This chapter is the thing fragments go inside.

A Gata program needs exactly two things to be complete: a **realm**, which is a block naming an execution environment, and an **entry point** inside it, which is a function marked `entry`. Which realm, and which shape of entry point, depends on the target you picked in the manifest.

### The GatOS target

```go
realm kernel {
    entry func Main() { }
}
```

That is a complete, buildable GatOS program. It boots, it does nothing, and it halts. The name `Main` is a convention, not a requirement — what makes this the entry point is the `entry` keyword, not the identifier.

### The Hosted target

```go
realm userspace {
    entry func Main() { }
}
```

That is a complete Hosted program. Note what changed: the realm. A Hosted build has *no kernel realm at all*, and the entry point moves into `realm userspace`, where it becomes the generated C `main()`.

### The rules, precisely

The structural check is worth stating exactly, because it is the single most common thing to get wrong when moving code between targets, and because its phrasing contains a distinction that surprises people.

**What is counted is the entry point, never the block.** A realm is one namespace no matter how many blocks open it, in how many files (Chapter 30 covers why). You may open `realm kernel { }` twenty times across twenty files; that is not twenty kernels, it is one kernel described in twenty places.

For a **GatOS** build:

- There must be a `realm kernel` holding **exactly one** `entry func` in the build. Zero is `G002`; more than one is `G059`.
- An `entry func` inside `realm userspace` is `G068`. In a GatOS build, userspace entry points are *thread* entries (Chapter 23), not free functions.
- Any number of blocks of either realm is fine.

For a **Hosted** build:

- There must be **no** `realm kernel` block at all — one is `G055`.
- There must be a `realm userspace` holding **exactly one** `entry func`. Zero is `G058`; more than one is `G059`.
- Any number of blocks is fine.

And in both targets, an `entry func` written outside any realm block is `G068`.

>[!IMPORTANT]
> This is the one place where the same source cannot serve both targets unchanged. A GatOS program's boot entry lives in `realm kernel`; a Hosted program's `main` lives in `realm userspace`. Everything else — classes, generics, libgata, your logic — is genuinely portable between the two. Structure a program you intend to run both ways so that the realm blocks contain as little as possible and call into shared top-level code.

### Reading fragments in this book

From here on, examples are shown bare when the surrounding skeleton would only be noise:

```go
let int x = 5;
```

That is not a program. Read it as:

```go
realm kernel {
    entry func Main() {
        let int x = 5;
    }
}
```

Where a fragment declares something that cannot live inside a function — a class, an enum, a module — read it as sitting at the top level of the file, outside every realm block, which Chapter 15 establishes is a legal place for it.

With a build you can describe, a toolchain you can drive, and a skeleton to put code in, the next part starts at the bottom: what a Gata source file is made of, one token at a time.


# Part II: Lexical Structure

This part is about what a Gata file is made of before anything means anything: comments, names, keywords, literals, and punctuation. It is the shortest part of the book and the one you will re-read least, but two of its four chapters contain rules that catch people out for real — the keyword status of `kernel`/`userspace` in Chapter 5, and the literal type-inference table in Chapter 6 — so it is worth reading once properly rather than skimming.

## 5. Comments, Identifiers, and Keywords

### Comments

```go
// a line comment, running to the end of the line

/* a block comment,
   spanning lines */
```

Block comments **do not nest**. A `/*` inside a block comment is just two characters; the first `*/` ends the comment, whatever came before it. An unterminated block comment is `G046`.

This is a deliberate simplification rather than an oversight. Nesting block comments requires the lexer to count depth, which means a `/*` inside a *string literal* inside commented-out code changes where the comment ends. Non-nesting comments cost you the ability to comment out a region that already contains a block comment; the fix is to use line comments for that, which every editor will do for you.

### Identifiers

ASCII only: an identifier starts with a letter or underscore, and continues with letters, digits, or underscores.

```
[A-Za-z_][A-Za-z0-9_]*
```

```go
let int _count = 0;
let int camelCase = 1;
let int MAX_SIZE = 64;
```

There are no Unicode identifiers. Gata targets a freestanding kernel where the compiler cannot assume a Unicode-aware toolchain below it, and an identifier that a C compiler cannot spell is an identifier the backend cannot emit.

One naming rule is enforced rather than suggested: **a name beginning with two underscores is reserved for the compiler's own temporaries**, and declaring one is `G003`. This applies to every name that reaches the output as written — a local, a parameter, a `for..in` variable, a `match` binding.

```go
let int _scratch = 1;      // fine
let int __scratch = 1;     // error[G003] — '__' belongs to the compiler
```

A *single* leading underscore is yours, and it carries a convention the compiler participates in: it is the marker for a binding you deliberately never read. An unused parameter named `_something` is exempt from the unused-parameter warning `G076` (Chapter 39).

### Keywords

These words are reserved everywhere and can never be identifiers:

```
import realm kernel userspace foreground background
class enum module union func static public private entry throws operator as
fields ref return if else while for in switch case break continue
debug panic try catch new let null unsafe throw sizeof default defer match
assign
bool int char float double short void
int64 uint uint64 ushort byte sbyte usize uintptr
true false
```

Two of these deserve individual attention.

**`kernel` and `userspace` are hard keywords.** You cannot name anything either one, in any position:

```go
class userspace { }            // error[G044]
let int kernel = 1;            // error[G044]
```

The reason is the pass order from Chapter 3. `kernel.Foo` is a *scope qualifier* — it means "the `Foo` declared in the kernel realm" — and it has to be recognised as one by the ScopeBinder, which runs before any name is resolved to anything. If `kernel` could also be a variable, then `kernel.Foo` would be ambiguous between a qualifier and a field access at a point in the pipeline where nothing has the information to choose. Reserving two words buys a scope-qualifier syntax that never needs to guess. Chapter 30 is where those qualifiers earn their keep.

### Contextual keywords

Three words carry meaning only in declaration position, and remain ordinary identifiers everywhere else:

```
process    thread    native
```

```go
realm kernel {
    entry func Main() {
        let int process = 2;       // fine
        let int thread  = 3;       // fine
        let int native  = 4;       // fine
    }
}
```

They become keywords only where a declaration can start: `process Name {` and `Name : foreground`, `thread Name {`, and `native {` / `native type Name {`. Unlike `kernel` and `userspace`, none of them ever appears in the middle of an expression, so there is no ambiguity to resolve early and no reason to take three common nouns away from you.

### `self` is not a keyword either

`self` is an ordinary name that the compiler makes available inside an instance method, bound to the receiver. It is not reserved, and it is not defined anywhere else — using it in a static method, a free function, or a thread entry is `G005`, "undefined name", because that is precisely what it is there.

This is a small thing with a pleasant consequence: `self` behaves exactly like a parameter for every purpose in the rest of the language. It shadows like one, it is captured by nothing, and Chapter 17 needs no special rules for it.

## 6. Numbers, Characters, and Strings

### Integer literals

An integer literal is decimal or hexadecimal, with optional `u`/`U` and `l`/`L` suffix characters in any run:

```go
let a = 42;                    // int
let b = 0xFF;                  // int, emitted verbatim as 0xFF
let c = 100L;                  // int64
let d = 4096u;                 // uint
let e = 0xFFULL;               // uint64
let f = 5000000000;            // int64  — too big for int
let g = 18446744073709551615;  // uint64 — too big for int64
```

The type of a literal with no explicit type context is decided by this table:

| Suffix | Inferred type |
|---|---|
| `u` and `l` together | `uint64` |
| `l` | `int64` |
| `u` | `uint` if it fits, otherwise `uint64` |
| none | `int` if it fits, else `int64`, else `uint64` |

Two things follow from that last row, and they are the reason the table is worth memorising rather than looking up. First, a literal's type is a property of its *value*, not just its spelling: `2000000000` is an `int` and `3000000000` is an `int64`, with no syntactic difference between them. Second, this only decides the literal's type in the absence of a target type. When a literal is being stored into or compared against something with a known type, the rules in Chapter 28 take over, and an integer literal converts into any numeric type it fits in.

Malformed literals are caught in the lexer:

```go
let x = 0x;                        // error[G049] — no digits
let y = 12abc;                     // error[G049] — bad suffix
let z = 99999999999999999999999;   // error[G004] — does not fit in 64 bits
```

Note that hexadecimal literals are emitted *verbatim* into the generated C. `0xFF` stays `0xFF`, not `255`. This is entirely cosmetic, but it means a register mask you wrote in hex is still readable as a mask when you go read the emitted C.

### Float literals

```go
let a = 1.0;        // double
let b = 2.5f;       // float  — the f/F suffix
let c = 1.0e+300;   // double
let d = 2e10f;      // float
let e = 1.5e-10;    // double
```

A float literal needs either a decimal point followed by a digit, or an exponent. The unsuffixed form is `double`; `f` or `F` makes it `float`.

The "followed by a digit" part is a real rule with a visible consequence:

```go
1.f       // NOT a float — this is a member access on the integer literal 1
1.0f      // a float
```

A `.` starts a fraction only when a digit follows it. Otherwise it is the member-access operator, and `1.f` parses as "the member `f` of `1`". This costs nothing in practice — nobody writes `1.f` on purpose — but it is why the grammar can allow method calls on numeric literals at all.

### Character literals

Exactly one character, or one escape, in single quotes. The value is that character's codepoint, and the type is `char`.

```go
let c  = 'a';
let nl = '\n';
let q  = '\'';
let z  = '\0';
```

The recognised escapes, and they are the same everywhere — in a `char`, in a `String`, and inside an interpolated string:

```
\n   \t   \r   \0   \'   \\   \"
```

Anything else after a backslash is `G047`. There is no `\x41`, no `A`, and no octal form. The set is deliberately the small one every target agrees on.

```go
let bad = '\q';     // error[G047]
let e2  = '';       // error[G046] — empty
let e3  = 'ab';     // error[G046] — more than one character
```

### String literals

Double-quoted, with no embedded raw newline:

```go
let s = "hello";
let t = "tab\there";

let bad = "line
break";             // error[G046] — unterminated: a raw newline ends the literal
```

Here is the part that matters more than the syntax. **A string literal is a `String` value** — the managed class type from `libgata` (Chapter 13) — and specifically it is *one static `String` object per literal*, created once, never freed, and never mutated.

That single sentence explains three things you would otherwise have to discover:

- **Literals cost nothing at runtime.** Writing `"hello"` in a loop does not allocate on each iteration. The object already exists in the image.
- **Literals are never reference counted.** Their header carries a sentinel refcount, so retain and release both leave them alone and their destructor never runs (Chapter 35). This is what makes it safe to return a literal from a function that also returns freshly allocated strings.
- **`String` has no `[]=` operator.** A string you were handed might be one of these immortal, shared objects, so nothing in the language may write through a `String` reference. Mutation lives in `StringBuilder` instead.

## 7. Interpolated Strings

A string literal prefixed with `$` may embed expressions in braces:

```go
let int n = 7;
let String s = $"n = {n}, twice = {n * 2}";
```

Any expression may appear between the braces, and each part is converted to `String` by the rules in Chapter 28. To write a literal brace, double it:

```go
let String s = $"{{literal braces}} and {n}";   // "{literal braces} and 7"
```

Braces nest correctly inside the expression — the lexer tracks depth rather than scanning for the first `}` — so an interpolation containing a collection initializer or a nested interpolation parses the way you would hope. An unterminated `{`, or an unterminated string, is `G046`.

### What it lowers to

Interpolation is desugared, not implemented at runtime, and the compiler picks the cheapest shape for the number of parts it sees:

- **One part** lowers to just that part's `String` conversion. `$"{x}"` is `x as String` and nothing more.
- **Two parts** lower to a single `+` concatenation.
- **Three or more parts** build the result through one `StringBuilder`.

That last case is the reason `StringBuilder` is a compiler-known builtin (Chapter 13) rather than an ordinary library class. A ten-part interpolation costs one growable buffer, not nine intermediate `String` objects each allocated and immediately released.

### The dropped-`$` warning

A very specific mistake gets its own diagnostic. If a *plain* string literal — no `$` — contains `{name}`, and `name` is a variable in scope, that is `G080`:

```go
let int count = 1;
let String s = "count = {count}";   // warning[G080] — did you mean $"..."?
```

The check is narrow on purpose. It fires only when the braced text resolves to a real variable, so a string containing `{}` or `{TODO}` or a JSON fragment stays silent. That narrowness is what makes it worth having: it has essentially no false positives, and the mistake it catches produces a program that compiles, runs, and prints the wrong thing.

### What interpolation is not

There is no format-specifier syntax inside the braces — no `{x:2}`, no `{x,10}`, no padding or precision. Interpolation converts, and that is all it does. When you need alignment, radix, or a fixed number of decimal places, that is `libgata`'s `Format` module (Chapter 37), called as an ordinary function inside the braces if you like:

```go
let String s = $"pi = {Format.Double(pi, 4)}";
```

Keeping formatting in a library rather than in the lexer means the format vocabulary can grow, be typed, and be read by a human, instead of becoming a second grammar embedded in string literals.

## 8. Operators and Punctuation as Tokens

Every operator and punctuation token in the language:

```
+  -  *  /  %       &  |  ^  ~  <<  >>       !  &&  ||
==  !=  <  >  <=  >=
=  +=  -=  *=  /=  %=  &=  |=  ^=  <<=  >>=
++  --   ->   ::   ?   :   .   ,   ;   ( )  { }  [ ]   @   $
```

What each of these *means* is Chapter 26's job; this chapter is only about how they are tokenized. Three of them are worth a note here, because tokenization is exactly where they surprise people.

**`->` exists only in function-pointer types.** It is not an arrow operator, not a member access on a pointer, and not usable in an expression. `func(int) -> int` is where it lives (Chapter 12), and nowhere else. Member access is always `.`, even on a pointer.

**There is no prefix `++`/`--`.** Both exist only as postfix operators. `++i` does not parse as an increment; the lexer produces `++` and then `i`, and the parser has nothing to do with that. This is the "Gata refuses to guess" principle applied to the single most notorious ambiguity in C-family languages: the difference between `i++` and `++i` as expressions is a real semantic difference that reads as a typo, so only one of them exists, and (per Chapter 25) it is a statement rather than an expression, which removes the question entirely.

**`::` is always the root-scope qualifier**, lexed as one token. That has one consequence you will meet exactly once and then never forget:

```go
let int z = c ? 1 : ::Step();     // fine
let int z = c ? 1 :::Step();      // error[G044]
```

In the second line the lexer sees `::` first and then `:`, which is not a ternary. The compiler reports this with a hint naming the cause rather than a bare syntax error, so you are not left staring at it, but the fix is simply a space: a `::`-qualified branch of a ternary needs one after the `:`.

With the lexical layer settled, the next part covers what those tokens describe: the type system.


# Part III: The Type System

Gata is statically typed, and its type system is small on purpose: eighteen primitives, pointers, fixed arrays, function pointers, three kinds of declared type, and four names the compiler knows by role. There is no inheritance, no interface, no `dyn`, no `any`, and no runtime type information — which means every type in this part is exactly what it says it is, with a known size and a known representation, at compile time.

This part covers each category, then the inference rules that let you leave a type unwritten, then the full grammar for writing one down.

## 9. Primitive Types

Every primitive, its C representation, its signedness, and its promotion rank:

| Gata | C type | Signed? | Promotion rank |
|---|---|---|---|
| `bool` | `bool` | (integral) | 1 |
| `char` | `char` | signed | 2 |
| `sbyte` | `int8_t` | signed | 2 |
| `byte` | `uint8_t` | unsigned | 2 |
| `short` | `int16_t` | signed | 3 |
| `ushort` | `uint16_t` | unsigned | 3 |
| `int` | `int32_t` | signed | 4 |
| `uint` | `uint32_t` | unsigned | 4 |
| `int64` | `int64_t` | signed | 5 |
| `uint64` | `uint64_t` | unsigned | 5 |
| `usize` | `size_t` | unsigned | 5 |
| `uintptr` | `uintptr_t` | unsigned | 5 |
| `float` | `float` | — | 6 |
| `double` | `double` | — | 7 |
| `void` | `void` | — | 0 |

### Widths are fixed, not platform-dependent

The middle column is the whole point. `int` is `int32_t` — always, on every target, in every build. It is not "at least 16 bits", it is not "the machine word", and it does not change between the Hosted build you tested on and the kernel image you booted.

This is the single largest departure from C's model, and it is not a stylistic preference. Gata's reason for existing is that the same source compiles to a hosted program and to a bare-metal kernel; a type whose width depends on the target would make those two builds different programs. An overflow you did not see in testing because `int` was wider there is exactly the class of bug that a kernel cannot afford.

The two exceptions are the two that must be: `usize` is `size_t` and `uintptr` is `uintptr_t`, because both exist precisely to be "whatever this machine's addresses are". Use `usize` for sizes and counts that index memory, and `uintptr` when you genuinely need an integer that can hold a pointer.

```go
let byte    b = (7 as byte);
let usize   n = (9 as usize);
let uintptr p = (0 as uintptr);
```

### Promotion rank

The rank column drives every implicit conversion and every binary-operator result type. In one sentence: a value may convert implicitly to a type of *higher* rank, and a binary arithmetic expression resolves at the higher-ranked of its two operands. Chapter 28 covers both rules properly, including the one place — mixing signedness — where rank alone is not enough to decide safely.

Note that rank ties exist and are meaningful. `char`, `sbyte`, and `byte` all have rank 2; `int` and `uint` both have rank 4. A tie means the two types are the same *size class* but not interchangeable, and the conversion rules take signedness into account rather than picking by rank alone.

### `bool` is integral, and that is all it is

`bool` has rank 1, which puts it inside the numeric ladder. That is a representational fact, not a licence: there is **no truthiness** in Gata. An `if` condition must be `bool` (`G029`), and an integer does not convert to `bool` implicitly. What rank 1 buys you is that `bool` has a defined position when it is explicitly cast, nothing more.

### `void` is not a value type

`void` is legal in exactly two positions: as a function's return type, and as a pointee (`void*`). Anywhere a value could be stored, it is `G007`:

```go
let void v;                    // error[G007]
void func F(void x) { }        // error[G007] — a void parameter
```

There is also no `void` value to produce, which is why `let x = SomeVoidFunc();` is an inference failure (Chapter 14) rather than a variable holding nothing.

## 10. Pointers

A pointer type is written with a trailing `*`, at any depth:

```
T*    T**    void*    char***
```

Declaring a pointer-typed variable requires nothing special. *Using* one does:

```go
unsafe {
    let int  n = 1;
    let int* p = &n;
    let int  v = *p;
}
```

Every pointer operation must be inside an `unsafe { }` block, and each of these is `G033` outside one:

- address-of, `&x`
- dereference, `*p`
- pointer indexing, `p[i]`
- pointer arithmetic, `p + n` and `p - n`
- `p++` and `p--` on a pointer
- casts to or from a pointer type

The type itself is not the dangerous part, so the type itself is not gated. You can write a `T*` field, a `T*` parameter, and a `T*` local in ordinary safe code; you simply cannot *do* anything with one until you have said `unsafe`. That split is deliberate — it means a class can store a raw pointer, and expose a completely safe API over it, with `unsafe` appearing only in the handful of method bodies that actually touch memory. `libgata`'s containers are built exactly this way.

`void*` at any depth is a legal type with no further checking; it is the universal opaque handle, and Chapter 13's `Process` and `Thread` types are exactly that.

Chapter 25 covers `unsafe` as a statement, including the thing it does that is *not* about pointers: it turns off automatic reference counting for the whole block.

## 11. Fixed-Size Arrays

An array type writes its size **before** its element type:

```go
let [3]int  a = [1, 2, 3];
let [3]char seq = [(27 as char), '[', 'H'];
let [2][4]int grid;             // 2 arrays of 4 ints
```

The prefix position is not arbitrary. It makes the type read outside-in, in the same order the words go: `[2][4]int` is "2 of (4 of int)". C's `int grid[2][4]` requires reading the name outward in both directions, and multi-dimensional declarations are where that reliably goes wrong.

Four rules govern them.

**The size is part of the type.** `[3]int` and `[4]int` are different, unrelated types. Neither converts to the other, and a function taking `[3]int` will not accept `[4]int`.

**The size must be a positive integer literal.** Not a constant expression, not an enum member, not a `const` (there is no `const`). Anything else is `G007`.

**An array is a value type.** It is emitted as a boxed struct, which means assigning one **copies it**, and passing one to a function copies it. This is worth pausing on if you are coming from C, where an array decays to a pointer at the slightest provocation. In Gata it does not decay, ever. If you want reference semantics for a block of elements, that is what `List[T]` is for; if you want to hand a function something it can write through, that is a `ref` parameter (Chapter 25) or a raw pointer inside `unsafe`.

**They participate in `for..in`.** A fixed array is one of the two things the structural loop in Chapter 25 accepts.

### The managed-element warning

There is one sharp edge, and the compiler warns about it rather than forbidding it:

```go
let [4]Point pts;      // warning[G094] if Point is a class
```

A fixed array is raw storage with no destructor. Stores into one *are* reference counted, so the elements never dangle — but nothing releases them when the array goes out of scope, so they leak. `G094` says exactly that, and the fix is to use `List[T]` when the elements are owned.

The reason this is a warning rather than an error is that a fixed array of managed elements is genuinely useful when the elements are static or process-lifetime — a table of string literals, for instance, which are never released anyway.

## 12. Function Pointer Types

A function pointer type is written:

```
func(T1, T2, ...) -> R
```

```go
int func Add(int a, int b) { return a + b; }

realm kernel {
    entry func Main() {
        let func(int, int) -> int f = Add;
        let int n = f(2, 3);
    }
}
```

A bare reference to a function's name, not immediately called, is a value of its function-pointer type. There is no address-of operator involved and no `unsafe` block required — this is a checked, typed value, not a raw pointer.

`func() -> void` is the zero-parameter, no-result form; the `-> R` is never omitted, even for `void`.

Function pointers are how Gata does indirect dispatch, and since there is no inheritance and no virtual methods, they are the *only* way. An array of them is a vtable:

```go
let [2]func(int) -> int ops = [AddOne, Double];
let int c = ops[0](10);
```

A field of function-pointer type gives a class a customisation point without a class hierarchy:

```go
class Handler {
    public func(int) -> int cb;
}
// h.cb(3) is an indirect call through the field
```

### What you cannot point at

Five things cannot become a function-pointer value, and each restriction is the direct consequence of something the *type* cannot express:

- **An overloaded function** — `G015`. The name does not identify one function, and the type gives no way to say which.
- **An `entry func`** — `G030`. Entry points are invoked by the boot sequence or the scheduler, and taking one's address would let ordinary code call it.
- **A `throws` function** — `G004`. A throwing function does not return `R`; it returns a generated `Result` shape (Chapter 29), and `func(...) -> R` cannot say that.
- **A function with a `ref` parameter** — `G004`. The type has no syntax for `ref`.
- **A pointer *to* a function type** — `G053`. `func(int) -> int*` parses as a function returning `int*`, which is almost always what you meant; the explicitly-parenthesised `(func(int) -> int)*` form is rejected rather than given a meaning.

And symmetrically, an indirect call cannot take `ref` arguments (`G037`), for the same reason the fourth item exists.

There are also **no closures**. A function pointer points at a free function, full stop: no captured locals, no bound receiver, no environment. This is not a temporary gap — a closure needs an allocation and a lifetime for its captures, and Gata's answer to "behaviour plus state" is a class with a field, which you can already write. `libgata`'s `Algorithms.SortBy` takes a `func(T, T) -> bool` for exactly this reason, and callers that need state pass it in the elements instead.

## 13. Declared Types and Builtin Types

### The three declared kinds

Three declarations create new named types, and they differ in their *representation* as much as in their syntax:

- **`class`** — a heap-allocated, reference-counted object. A class-typed variable is a reference (a pointer, underneath) that participates in reference counting. Chapter 17.
- **`enum`** — an integer-backed set of named constants. A value type with no header and no allocation. Chapter 19.
- **`union`** — a tagged union: a tag plus a payload struct. A **value type**, copied on assignment, not reference counted itself (though its payloads may be). Chapter 20.

A fourth declaration, **`module`** (Chapter 18), creates a namespace rather than a type — it has no instances and no storage, and a module name is not usable in a type position.

The distinction between "reference" and "value" here is the one that will bite if you skim it. Assigning a class-typed variable makes two names for one object; assigning a union-typed or array-typed variable copies. Chapter 35 covers what that means for ownership.

### The four builtin types

Four type names are known to the compiler *by role*. They are not hardcoded: the compiler resolves each one from whichever declaration in the build carries the matching `@builtin` annotation (Chapter 32).

| Name | What it is | Where the compiler needs it |
|---|---|---|
| `String` | the managed text type | every string literal has this type |
| `StringBuilder` | a growable text buffer | interpolation lowering, for 3+ parts (Chapter 7) |
| `Process` | an opaque process handle | the generated process launcher (Chapter 36) |
| `Thread` | an opaque thread handle | thread spawning |

```go
@builtin(String)
class String { char* data; usize length; /* ... */ }

@builtin(Process)
native type Process { void* _opaque; }
```

`Process` and `Thread` resolve to `void*` underneath — they are handles the runtime hands you and takes back, with no fields you can reach.

This indirection is worth understanding because it is the same trick the language uses everywhere. The compiler generates code that needs a string type; rather than baking in the name `String` and its layout, it emits a call to whatever declaration claimed the `String` role. That means `libgata` is genuinely just a library — you could replace it wholesale, and the compiler would keep working, because nothing in the compiler knows any of its names. Chapter 32 generalises this to functions with `@intrinsic`.

## 14. Type Inference and the Full Type Grammar

### Inference

A `let` may omit its type when an initializer determines it:

```go
let x = 5;                 // int
let s = "hi";              // String
let a = [1, 2];            // [2]int
let c = new List[int]();   // List[int]
```

Inference in Gata is deliberately *local*. It looks at the initializer expression and nothing else — never at how the variable is used later, never at a whole function body. This is why the rules fit in a paragraph and why an inference failure always points at one line.

Three things cannot be inferred, and each has a specific diagnostic:

```go
let x;                     // error[G054] — no type and no initializer
let x = null;              // error[G054] — null has no type of its own
let x = SomeVoidFunc();    // error[G054] — the initializer produces no value
```

`null` is the interesting one. It is assignable to *any* class reference, pointer, or function pointer, which is exactly why it cannot determine a type by itself: there is no single type it means. Write the type down:

```go
let Point p = null;        // fine
let int*  q = null;        // fine
```

Declaring a variable with a type and no initializer is legal and does not infer anything:

```go
let int c;                 // declared, holds nothing yet
c = 3;
```

Chapter 25 covers what happens if you read `c` before that assignment.

### The full type grammar

Everything that can appear in a type position:

```
type      := arraypfx* ( funcptr | name genericargs? ) '*'*
arraypfx  := '[' intlit ']'
funcptr   := 'func' '(' type,* ')' '->' type
name      := scopequal? ident ( '.' ident )*  |  primitive
scopequal := '::' | 'kernel' '.' | 'userspace' '.'
```

Read outward: array prefixes first, then the base (a function-pointer type, or a name with optional generic arguments), then pointer stars.

One example of each slot:

```go
let ::Cargo c;                     // root-scope qualified (Chapter 30)
let kernel.Cargo k;                // realm-scope qualified
let Map[String, List[int]] m;      // nested generic arguments
let func(int) -> Optional[int] f;  // a generic type inside a function-pointer type
let [4]Point pts;                  // an array of class references
let int** pp;                      // a pointer to a pointer
```

The `scopequal` production is the one piece here that has no analogue in most languages, and it is not worth explaining in full until you have realms and processes to qualify against. Chapter 30 does that. For now, read `::Name` as "the `Name` at the top level of the build, specifically", and note only that qualifiers are valid in *type* position and not just in expressions — which matters, because four of the things a scope can name are types.

With the type system laid out, the next part covers the declarations that carry those types, and who is allowed to see them.


# Part IV: Declarations and Visibility

A Gata file is a list of declarations. This part covers which declarations may appear at a file's top level, what each one does, and the modifiers that control who can see them. Free functions get their full treatment here, since a free function *is* a top-level declaration and there is nowhere better to put them.

## 15. What May Appear at the Top Level

Exactly these, and nothing else:

```go
import ...;
@environment
native { ... }
native type Name { ... }
@extern <ret> func Name(params);
enum / union / class / module declarations
free function declarations
realm kernel { ... }  /  realm userspace { ... }
```

Three things that people reasonably expect are **not** on that list:

- **`process`** — `G001`. A process must be inside a realm (Chapter 23).
- **`thread`** — `G001`. A thread must be inside a process.
- **`let`** — there are no global variables in Gata, at any scope, ever. The only storage that outlives a function is a *process variable* (Chapter 24), and it belongs to a process rather than to the program.

That last absence is a load-bearing design decision rather than an omission, and Chapter 24 makes the argument for it. For now: if you are looking for a place to put mutable state shared across a program, the answer is a process, and if you are looking for a place to put a constant, the answer is a function that returns it or an `enum`.

### 15.1 Imports

```go
import String;            // a library module: <stdlib>/String.g
import "src/util.g";      // the path form
```

Two forms, and the difference is where the compiler looks. The bare-identifier form names a `libgata` module and resolves against the standard library directory. The quoted form is a path, and it is **resolved relative to the project root** — not relative to the importing file.

That is worth reading twice, because it is the opposite of C's `#include "..."` and of most module systems. The project root is the directory containing the `.gconf`, or, in the loose `--env`/`--entry` mode from Chapter 2, the directory containing the entry file. A file at `src/net/socket.g` importing a sibling writes `import "src/net/util.g"`, not `import "util.g"`.

The reason is that it makes an import path mean one thing in the whole program. A relative-to-file scheme gives the same file two spellings depending on who imports it, which then has to be canonicalised somewhere, and the place that gets it wrong is always a build with symlinks in it. One root, one spelling.

Three rules:

- **Imports must be at a file's top level.** An `import` inside a realm, a process, or a class is `G001`.
- **Cycles are fine.** Each file is parsed exactly once, so `a.g` importing `b.g` importing `a.g` is not an error and needs no include guard.
- **Annotations on an import are `G048`.** An import is not a declaration you can mark.

### What an import gives you

A file may name the top-level declarations of *itself*, plus the **transitive closure** of its imports.

Transitive is the important word. If `main.g` imports `Console`, and `Console` imports `String`, then `main.g` can name `String` without importing it. That is convenient and it is also how the standard library stays usable — `import Console;` reaching `String` and `Int` is what stops every file from opening with a wall of imports.

As a matter of style, still import what you directly reference. Transitivity is a convenience for the reader, not a licence to depend on another module's dependency list, which may change.

A type that exists in the build but is not reachable through your imports is not silently invisible — the diagnostic says so:

```go
// a.g
class Widget { public int n; }

// b.g  (does not import a.g)
void func F() { let Widget w = new Widget(); }   // error[G007] — not in scope; import its module
```

Chapter 31 covers what happens when two files reach for the same name.

### 15.2 `@environment`

```go
@environment
```

A bare marker, at the top level of a file, with no argument. It designates that file as the build's **environment definition** — the file that provides the platform floor as raw-C preambles.

Exactly one file per build must carry it. Zero is `G000`; two is `G000`. Placing it inside a realm block is `G064`.

Chapter 34 is entirely about what an environment file contains and why. For now, note only that `appa` finds this file by scanning for the marker, which is why the manifest has no "environment file" setting to configure.

### 15.3 `native { }` blocks

```go
native {
    #include <stdio.h>
    static int helper(void) { return 1; }
}
```

Raw C, captured verbatim by the lexer and spliced into the emitted output without being parsed as Gata.

The capture is brace-balanced, and it is aware of C comments and of C string and character literals — so a `}` inside `char* s = "}"` does not end the block, and neither does one inside `/* } */`. This matters more than it sounds: a naive brace-counter makes it impossible to embed a large chunk of real C, which is exactly what this feature is for.

**Placement decides the translation unit.** At the top level, the block is shared by every unit. Inside `realm kernel`, it goes to the kernel unit only; inside `realm userspace`, to the user unit only. That is the mechanism behind the per-realm C helper pattern in Chapter 33.

With the `@preamble` annotation (Chapter 32), a native block is emitted *before* everything else in its unit, which is how the environment file gets its includes in place first.

### 15.4 `native type`

```go
native type obj {
    gata_Fn_void__void_p __dtor;
    size_t               __rc;
}
```

Registers a C struct as a named Gata type. The body is emitted verbatim as the struct body, and the name becomes usable anywhere a type can go.

The important property is that **its fields are not visible to Gata**. It is an *opaque struct*: the compiler cannot see inside it, so member access and method lookup on such a value are silently allowed rather than reported as errors. The compiler is not pretending the members exist; it is declining to claim they do not, because it genuinely does not know. Mistakes here are caught by the C compiler, one layer down.

A `native type` may carry `@intrinsic` and `@builtin` (Chapter 32), which is how `Process` and `Thread` come to exist.

### 15.5 `@extern`

```go
@extern void  func _env_yield();
@extern int   func _env_read(char* buf, int max);
@extern void* func _env_alloc(usize n);
```

Declares that a C function exists, so Gata code may call it. There is no body, and the declaration is terminated by `;`.

- Declaring the same name twice with a *different* signature is `G003`. An `@extern` names one C symbol, so two disagreeing descriptions of it cannot both be right.
- Declaring a name both as `@extern` and as a normal Gata function is `G003`.
- Declaring it identically in two files is fine, and expected — every file that calls it may declare it.

>[!IMPORTANT]
> **appa does not emit a C prototype for an `@extern`.** You must ensure a real C declaration reaches the translation unit yourself, normally via a `native { #include <...> }` or a `native { }` definition. Without one, the C compiler reports an implicit declaration and the build fails there rather than in `appa`.
>
> This is deliberate rather than unfinished. Gata cannot spell a truthful C signature for many C functions — it has no `const`, so a generated `int puts(char*)` contradicts the `int puts(const char*)` in the real header, and the C compiler is right to complain. Rather than emit a prototype that is sometimes a lie, `appa` emits none and leaves the declaration to the one place that can state it correctly: C.
>
> The consequence is that **the extern boundary is unchecked in both directions.** Nothing verifies that the signature you wrote matches the function you linked against, exactly as nothing verifies the contents of a `native { }` block.

The working pattern is to write both halves next to each other:

```go
native { void lib_probe(void); }     // the declaration C needs
@extern void func lib_probe();       // the declaration Gata needs
```

### 15.6 Free Functions

A free function is a function declared outside any class or module. It is the unit of reusable, non-method logic, and everything from a one-line helper to your program's entry point is one.

```go
int func add(int a, int b) {
    return a + b;
}

func sayHi() {                       // no return type written — implicitly void
    Console.PrintLine("hi");
}

void func sayBye() {                 // explicitly void — identical to the above
    Console.PrintLine("bye");
}
```

### The signature shape

```
[annotations] [modifiers] [entry] [throws] [returntype] func Name [generics] (params) body
```

There is exactly one place a return type may go: immediately before `func`. Writing it after the parameter list, C-style, is `G053` with a message saying where it belongs.

Omitting the return type means `void`, which is why `func F()` and `void func F()` are the same declaration. Both spellings are idiomatic; pick one and be consistent within a file.

A parameter is `[ref] type name`. There are **no default parameter values, no named arguments, and no varargs** — each of which would require the call site to be resolved against something other than the argument types, and Gata's overload resolution (below) depends on that not being the case.

The body is either a block, or a raw-C `native { }` body (Chapter 33).

### Returning

A non-`void` function must return on **every** path, or it is `G027`. There is no implicit return of a zero value, and no "falls off the end" behaviour.

```go
int func Sign(int n) {
    if (n > 0) { return 1; }
    if (n < 0) { return -1; }
}                                    // error[G027] — no return on the n == 0 path
```

Mixing the two shapes is caught too: `return;` in a non-`void` function is `G010`, and `return v;` in a `void` one is `G010`. A trailing `return;` at the very end of a `void` function is `G026`, a warning — it is harmless, but it is also always redundant, and leaving it in makes the *meaningful* early returns harder to spot.

One flow-analysis subtlety is worth knowing before it surprises you: a `return` inside a `native { }` *statement* embedded in an otherwise-Gata body does **not** satisfy the missing-return check. The compiler cannot see into raw C, so as far as `G027` is concerned that path falls off the end. The diagnostic says so and names the fix, which is to make the whole body native rather than splicing C into a Gata one.

### Overloading

Free functions may be overloaded by parameter types:

```go
int   func combine(int a, int b)     { return a + b; }
int64 func combine(int64 a, int64 b) { return a + b; }

realm kernel {
    entry func Main() {
        let int   r1 = combine(1, 2);
        let int64 r2 = combine(10L, 4L);
    }
}
```

Overloads are distinguished by their parameter types only — not by return type, and not by parameter names. Two declarations with the same name and the same parameter types are `G003`, in one file or across two.

**Resolution is by conversion cost.** Every visible candidate of that name is scored, argument by argument:

| Cost | Conversion |
|---|---|
| 0 | exact match |
| 1 | widening, or pointer covariance |
| 2 | narrowing |

The lowest total wins. A tie between two candidates is `G015` (ambiguous), and no candidate matching at all is `G016` (no matching overload). Both diagnostics list the candidates they considered, so the fix is usually visible in the message.

This scheme has one property worth relying on: because an exact match costs zero and nothing else does, adding an overload can never silently steal a call that already matched exactly. It can only take calls that were previously converting.

## 16. Modifiers and Visibility

There are exactly three modifiers.

```
static     on a class method only
public     on a class or module member only
private    on a class or module member, or on a free function
```

They may combine (`public static`), never repeat (`G065`), and `public private` together is `G065`.

### Where each is legal

This table is worth reading in full, because roughly half the entries are errors, and each error is telling you something about the language's shape:

| Declaration | `public` | `private` | `static` |
|---|---|---|---|
| free function | `G053` | ✅ | `G040` |
| class field | ✅ | ✅ (default) | **`G053`** |
| class method | ✅ | ✅ (default) | ✅ |
| operator | ✅ | ✅ (default) | `G053` |
| module member | ✅ | ✅ (default) | implied |
| type declaration (`class`/`enum`/`union`/`module`/`native type`) | `G053` | `G053` | `G053` |
| thread entry | `G053` | `G053` | `G053` |

Four of those cells deserve their reasoning spelled out.

**`public` on a free function is an error, not a redundancy.** A free function is *already* visible to every file that imports the one declaring it. Writing `public` would state a decision that was never made, and — worse — writing it on some functions and not others makes the unmarked ones read as restricted when they are not. Rather than let a modifier mean nothing, Gata rejects it.

**`static` on a class field is an error, and this is the big one.** There are no static fields in Gata. Combined with the absence of global `let` from Chapter 15 and the fact that modules cannot declare fields at all (Chapter 18), this means **there is no global mutable state in the language** other than process variables (Chapter 24). Not "discouraged" — absent. Chapter 24 makes the full argument; the short version is that a process is the one construct where "one of these, shared by everything inside it" has an unambiguous meaning, and everything else that looks like global state is a global with extra steps.

**`static` on an operator is an error** because an `as` conversion operator is already implicitly static (Chapter 27), and no other operator can be.

**Type declarations take no modifiers at all.** `public class C` and `private enum E` are both `G053`. A top-level type is visible to importers; that is the only visibility a type has. If you want to restrict a type to one file, the mechanism is not a modifier — it is not declaring it at the top level.

### Defaults

**Class and module members — fields, methods, operators — are private unless marked `public`.** Accessing one from outside its declaring type is `G035`.

```go
class Counter {
    int n;                                        // private field
    public int func Value() { return self.n; }
    void func Bump() { self.n = self.n + 1; }     // private method
}

realm kernel {
    entry func Main() {
        let Counter c = new Counter();
        let int v = c.Value();     // fine
        let int q = c.n;           // error[G035]
        c.Bump();                  // error[G035]
    }
}
```

**Free functions and top-level types are visible to every file that imports their file.** There is no opt-in and no opt-out for types; for free functions, `private` makes one file-local.

One thing is exempt from the member check entirely: **constructors**. `new C(...)` never goes through member-access resolution, so `_init` has no meaningful `public`/`private` distinction to apply.

### Private free functions

```go
private int func helper(int x) { return x + 1; }
```

`private` on a free function means *file-local*, implemented as per-file name mangling. Two different files may each declare `private int func helper(int)` with no clash whatsoever; they are different functions with different emitted names. Declaring the same private signature twice in one file is `G003`.

Within a file, a private free function **takes priority over an imported public one of the same name**. That is a useful behaviour and a dangerous one, so it is reported:

```go
// lib.g
int func Clamp(int v) { return v; }

// main.g
import "lib.g";
private int func Clamp(int v) { return v + 1; }    // warning[G057]
```

`G057` fires because every call to `Clamp(...)` in `main.g` now means something different from the same call in the file next to it. That is a real cost, and the warning exists to make sure it was intentional.

The imported function has not disappeared — it remains reachable through its file qualifier (Chapter 31) — and if the displacement *was* intentional, the `@shadows` annotation says so and silences the warning:

```go
import "lib.g";

@shadows
private int func Clamp(int v) { return v + 1; }

realm kernel {
    entry func Main() {
        let int a = Clamp(1);        // this file's, returns 2
        let int b = lib.Clamp(1);    // the imported one, returns 1
    }
}
```

The warning is reported **once**, at the declaration, however many overloads share the name and however many calls there are — because it is one decision, made in one place, not a problem with each call site.

And `@shadows` on a private function that displaces nothing is `G088`, exactly as it is everywhere else the annotation appears (Chapter 30). The annotation is never decoration.

With declarations and visibility settled, the next part covers the four things you can declare that create types.


# Part V: User-Defined Types

Four declarations shape a program: `class` for state with behaviour attached, `module` for behaviour with no state, `enum` for a closed set of names, and `union` for a value that is one of several shapes. Each chapter here covers one, and the order is deliberate — modules are defined in terms of classes, and unions in terms of enums.

## 17. Classes

A class is Gata's unit of structured, reference-counted state with behaviour attached. If you are coming from C, think "struct with methods, an automatic destructor, and no manual `malloc`/`free` for the common case". The automatic part — reference counting — is Chapter 35's subject; this chapter is about declaring the shape.

```go
class Point {
    public int x;
    public int y;

    func _init(int x, int y) { self.x = x; self.y = y; }

    public int func SumOf() { return self.x + self.y; }
}

realm kernel {
    entry func Main() {
        let Point p = new Point(3, 4);
        let int s = p.SumOf();
    }
}
```

Three structural rules:

- **Classes cannot nest.** A class inside a class is `G051`. Neither can a module inside a class, or any other declaration that would create a second layer of type namespace.
- **A class may be declared at the top level, inside a realm, or inside a process.** Where it is declared decides its *scope*, which Chapter 30 covers.
- **A duplicate type name in the build is `G003`.** Top-level type names are global to the whole program — see Chapter 31 for what to do when two libraries both want `Node`.

There is no inheritance, no interfaces, and no virtual dispatch. A class is exactly its own members, and a class-typed variable holds exactly that class. When you need one of several shapes behind one name, that is a `union` (Chapter 20); when you need behaviour chosen at runtime, that is a function-pointer field (Chapter 12).

### Fields

There are three spellings:

```go
class C {
    int a;              // a declared type, no initializer
    int b = 5;          // a declared type plus an initializer
    c = 7;              // the type is INFERRED — literals only
}
```

The third form works only for a **literal** initializer: an integer, float, bool, char, or string literal, optionally under a unary minus. Anything else is `G054`:

```go
class D {
    e = Compute();      // error[G054] — give it an explicit type
}
```

The restriction is a consequence of the pass order (Chapter 3). A field's type has to be known before any expression in the program is resolved, because other declarations' resolution depends on it. A literal's type is known from the token itself; a call's type is not known until resolution, which is too late.

Field rules:

- **Field initializers run as part of construction, before `_init`.** So `_init` sees the initialized values and may overwrite them.
- **A field and a method may not share a name** — `G003`.
- **Fields are private by default** (Chapter 16). `public` opts one out.
- **A field may hold a function pointer**, and calling it dispatches indirectly:

  ```go
  class Handler {
      public func(int) -> int cb;
  }
  // h.cb(3) is an indirect call
  ```

### Lifecycle: `_init` and `_deinit`

These are the only two methods the compiler itself ever calls.

```go
class Buffer {
    char* data;

    func _init() { self.data = null; }
    func _deinit() {
        unsafe { if (self.data != null) { free(self.data); } }
    }
}
```

`_init` is the constructor. It runs after allocation and after the object's reference-counting header has been stamped, and its parameters are the arguments to `new`. There is no separate constructor syntax — `_init` is an ordinary private method with a reserved name, which means it can be overloaded like any other method to give a class several constructors.

`_deinit` is the destructor. It runs when the reference count reaches zero, *before* the object's managed fields are released and before the memory is freed. That ordering is what makes it safe for `_deinit` to read those fields.

Neither may be `throws` (`G067`). The code that calls them is generated — the allocator and the release path — and neither has anywhere to put a failure. A constructor that can fail should be a `throws` static factory method instead:

```go
class Conn {
    func _init() { }
    public throws static Conn func Open(String addr) {
        let Conn c = new Conn();
        if (!c.Dial(addr)) { throw; }
        return c;
    }
}
```

>[!IMPORTANT]
> **`new` assumes allocation succeeds.** Allocation failure is not a condition the language models: `new` is not `throws`, does not return an `Optional[T]`, and there is no syntax for handling it. The emitted allocator initialises the object unconditionally, so a failed allocation faults *there* — at the allocation that failed, which is the one place a backtrace is worth having.
>
> That is a deliberate choice over the alternative. The allocator could guard each step with a null check and return null instead; it did once. But the caller has no way to ask, so it dereferences that pointer at the first field access anyway — the same crash, moved further from its cause, paid for with a branch per field on every construction in the program.
>
> The practical consequence is that your environment's `_env_alloc` (Chapter 34) is the only place a policy can live. On a hosted build it is `malloc`, and running out of memory ends the process. On a kernel, wire it to panic — an allocator that returns null to a language with no way to ask is strictly worse than one that stops.

### Methods

```go
class Vec {
    int n;
    public int func Length() { return self.n; }
    public static Vec func Zero() { return new Vec(); }
    public void func Scale(ref int factor) { }
    public int func At(int i) { return i; }
    public int func At(int i, int j) { return i + j; }   // an overload
}
```

The signature shape is the same as a free function's, plus modifiers:

```
[annotations] [modifiers] [entry] [throws] [returntype] func Name [generics] (params) body
```

- Omitting the return type means `void`, exactly as for a free function.
- **`entry` is never valid on a method** — `G053`. Entry points are free functions in a realm, or thread entries.
- Overloads differ by parameter types; same name and same parameter types is `G003`.
- **`self` exists in instance methods only.** In a static method it is `G005`, because there is nothing for the name to resolve to.

Two calling mistakes get their own diagnostics rather than a generic one, because both are common and both have an obvious fix:

- Calling a **static** method through an instance is `G014`.
- Calling an **instance** method through the class name is `G013`.

And calling a sibling instance method from inside the class without a receiver is an error whose message names the fix: write `self.M(...)`. Gata has no implicit `this`, in either direction — `self.n` and `self.M()` are always spelled out. That costs five characters and buys a guarantee that a bare name in a method body is always a local or a parameter, never a field you forgot about.

### `fields { }`: raw C members

```go
class Ring {
    fields {
        volatile uint32_t head;
        volatile uint32_t tail;
    }
    public int func Depth() native {
        return (int)(self->head - self->tail);
    }
}
```

A `fields { }` block injects raw C struct members verbatim into the emitted struct. It is how a class stores something the Gata type system cannot spell — a `volatile` word, a C union, a bitfield, an aligned buffer.

A class containing one is treated as having **opaque fields**: unknown member accesses on it are no longer reported, because the compiler cannot see what the C declared. That is the same trade as `native type` (Chapter 15) — the checking moves down a layer to the C compiler.

`libgata`'s `Sync` module is the flagship use: `SpinLock` and `AtomicInt` are each a `fields { }`-declared `volatile` word plus native methods over the compiler's atomic builtins — state whose type and operations live entirely below what Gata models, wrapped in an ordinary Gata class with an ordinary Gata API.

### Native method bodies

Put `native { ... }` where the body would go, and the body is raw C with `self` available as the C pointer:

```go
class Bits {
    public int func Popcount(uint v) native {
        int n = 0;
        while (v) { n += v & 1u; v >>= 1; }
        return n;
    }
}
```

Free functions take the same form:

```go
private void func blit(void* d, void* s, usize n) native { /* C */ }
```

The rule from Chapter 15 applies here too and is the one that catches people: **a native body is invisible to flow analysis.** A `return` inside a `native { }` *statement* spliced into an otherwise-Gata body does not satisfy `G027`. Make the whole body native instead of mixing the two.

## 18. Modules

Sometimes you want a related group of functions with no per-instance state at all — `Console.PrintLine`, `Math.Sqrt`. A `module` is Gata's purpose-built shape for exactly that, rather than forcing you to fake a singleton class.

**A module is a class whose members are all implicitly static, and which may hold no state.**

```go
module MathUtil {
    public static int func Square(int x) { return x * x; }
    public int func Cube(int x) { return x * x * x; }   // `static` is implied
}

realm kernel {
    entry func Main() {
        let int a = MathUtil.Square(4);
    }
}
```

Writing `static` is allowed and redundant; omitting it changes nothing. Members are called as `Module.Func(args)` and default to `private` exactly like a class's, so `public` is required to reach one from outside.

Four rules follow from "may hold no state":

- **A module may not declare a field** — `G063`, whose message is "modules are stateless; use a class for instance state". This is the third leg of the no-global-state argument from Chapter 16: no global `let`, no static fields, no module fields.
- **`new ModuleName()` is `G011`.** There is nothing to construct.
- **A module type cannot be stored.** A union variant field of module type is `G004`. A module name is a namespace, not a type.
- **There is no `self`.** There is no receiver for one to mean.

Modules cannot be generic — no `[T]` on the declaration — but **their methods can be** (Chapter 21). That combination is exactly what `libgata`'s `Algorithms` module is: a non-generic namespace full of independently-generic functions.

Every module in the standard library — `Console`, `Math`, `Mem`, `Sys`, `Int`, `Char`, `Format`, `Algorithms` — is this shape. Chapter 37 inventories them.

## 19. Enums

When a value can only be one of a small, fixed set of named integers, spelling them out as plain `int` constants throws away the type safety and the self-documentation an enum gives you for nothing.

```go
enum Dir { North, East, South, West }

enum Flags {
    None  = 0,
    Read  = 1,
    Write = 1 << 1,
    Both  = Read | Write,
    Next                       // 4 — continues from the previous value
}

realm kernel {
    entry func Main() {
        let Dir d = Dir.North;
        let int n = d as int;          // enum -> int
        let Dir e = 2 as Dir;          // int  -> enum
    }
}
```

An enum is integer-backed and is a value type: no header, no allocation, no reference counting.

### Values

Members with no explicit value take the previous member's value plus one, starting at zero. An explicit value is a **constant integer expression**, which specifically means:

- integer and character literals,
- earlier members of the same enum, written bare or as `Enum.Member`,
- the operators `+ - * / % << >> & | ^ ~` and unary `-`.

Anything else — a function call, a `sizeof`, a member of a *different* enum — is `G004`. Values are read as `int`, and a value outside `int`'s range is `G004`.

That vocabulary is deliberately just large enough for the two things enums are actually used for: sequential tags, and bit flags. `Write = 1 << 1` and `Both = Read | Write` above are the whole motivating case.

### Rules

- An enum with **no members** is `G053`. An empty closed set is a type with no values, which is never what was meant.
- A duplicate member name is `G003`.
- A **trailing comma** after the last member is `G052`.
- Enums are valid `switch` scrutinees and valid array indices.

### Comparison

`==` and `!=` work between two values of the same enum type. **Relational operators do not:**

```go
if (a < b) { }                          // error[G004] on two enums
if (a as int < b as int) { }            // the fix, which the hint names
```

This is not an oversight. `North < East` has no meaning unless the enum's numbering was intended as an ordering, and most enums' numbering is an implementation detail — inserting a member in the middle silently changes every comparison. Requiring the cast makes the claim "I am ordering these by their numeric values" explicit at the point where it is being made.

### Trailing-comma rigidity

`G052` deserves a word, because most modern languages allow a trailing comma and Gata does not, here or in a union's variant list.

The reason is that an enum member's value can be *omitted*, and an omitted value means "the previous one, plus one". A trailing comma is therefore visually indistinguishable from a member whose name you forgot to type — and the compiler would have to choose between a silently different enum and an error. It chooses the error, one token earlier.

## 20. Unions and Pattern Matching

An `enum` can only ever be a bare tag; it cannot carry a circle's radius differently from a rectangle's width and height. A `union` is Gata's **tagged union**: each variant may carry its own typed payload, and `match` forces you to handle every variant, so adding a new one later surfaces every place that needs updating.

```go
union Shape {
    Circle(double r),
    Rect(double w, double h),
    Point                            // no payload
}

realm kernel {
    entry func Main() {
        let Shape a = Shape.Circle(1.0);
        let Shape b = Shape.Rect(2.0, 3.0);
        let Shape c = Shape.Point();     // still a CALL, even with no payload
    }
}
```

A union value is a tag plus a payload struct, and it is a **value type** — assigning one copies it.

Construction is always a call on the union type, naming the variant. Even a payload-less variant needs its parentheses:

```go
let Shape c = Shape.Point;       // error[G005], with a hint to call it
let Shape c = Shape.Point();     // correct
```

The parentheses are required so that a variant name reads identically whether or not it has a payload, which matters when a variant *gains* one later. And `new Shape(...)` is `G011`: a union value is one of its variants, so there is no whole-union thing to construct.

Other rules:

- Variants are comma-separated; a **trailing comma is `G052`**, for the same reason as an enum's.
- Payload fields are named and typed like parameters.
- A union with **no variants** is `G053`.
- A duplicate variant name, or a duplicate field name within a variant, is `G003`.

### The containment restriction

A union **cannot contain itself by value**, directly or through another union:

```go
union Tree { Leaf, Node(Tree left, Tree right) }   // error[G004]
```

The reason is arithmetic rather than philosophical: a union's size is the size of its largest variant, and `Node`'s size would be defined in terms of `Tree`'s, which is defined in terms of `Node`'s. There is no finite answer.

Holding it *indirectly* is fine, because a reference has a fixed size:

```go
union Ok { Leaf, Node(List[Ok] kids) }             // fine
```

This is the standard shape for recursive data in Gata: put the recursion behind a container or a class reference.

### `match`

```go
void func Describe(Shape s) {
    match (s) {
        case Circle(r)   { }
        case Rect(w, h)  { }
        case Point       { }
    }
}
```

`case Variant(a, b)` binds the variant's payload fields **positionally** to fresh locals scoped to that arm's block. The binding count must equal the field count, or `G008`.

Positional rather than named bindings is a small decision with a real payoff: an arm reads as a destructuring, the names are yours rather than the union author's, and there is no second vocabulary of field names to keep in sync.

The rules that make `match` worth using:

- **A `match` with no `default` must cover every variant.** Otherwise `G039`, naming the ones you missed. This is the whole point of the construct: adding a variant to a union turns every incomplete `match` in the program into a compile error, so nothing is silently skipped.
- **A `default` when all variants are already covered is `G077`**, a warning, whose message is "remove the `default` so a new variant becomes a compile error". A redundant `default` is not harmless — it is the thing that would swallow that future error.
- Matching the same variant twice is `G003`; an unknown variant name is `G005`.
- `match` on a non-union is `G004`. It is not a general pattern-matching construct; `switch` (Chapter 25) handles integers and enums.

Underneath, `match` lowers to a scrutinee temporary plus a tag-comparison if/else chain. There is no jump table and no runtime dispatch machinery.

### Equality

`==` and `!=` between two values of the **same** union type compile to a generated structural comparison: first the tag, then the live variant's fields.

```go
if (a == b) { }
```

That is usually what you want, and occasionally it is subtly not, so two warnings guard it:

- **`G083`** — a payload field is a class with no `==` operator, so it is compared **by identity**, not by value.
- **`G084`** — a payload field is `float` or `double`, so it is compared with floating-point `==`.

Both are reported at the **comparison site**, not at the union's declaration. That placement is the useful part: a union that nobody ever compares stays completely silent, and the warning appears in the code that is actually making the assumption.

### Generic unions

Unions may be generic, with the same rules as generic classes (Chapter 21):

```go
union Optional[V] { Some(V v), None }
union Result[T, E] { Ok(T v), Err(E e) }

let Optional[int] m = Optional.Some(3);
let Optional[int] n = Optional[int].None();   // explicit instantiation
```

`Optional[V]` is in `libgata` and is the idiomatic "a value or nothing" type.

Note the two spellings above. When you name the base type alone — `Optional.Some(3)` — the compiler has to work out *which* instantiation you meant, and it does so in two steps:

1. From the **argument types**, when exactly one existing instantiation accepts them.
2. Otherwise, from the **expected type** of the enclosing `let` or `return`.

If neither settles it, that is `G054`, and the message lists the candidates it was choosing between. Writing `Optional[int].None()` is always available and always unambiguous — reach for it in the cases where the payload gives no clue, which in practice means the no-payload variants.

With the four type-forming declarations covered, the next part generalises three of them over their element types.


# Part VI: Generic Programming

A `List[int]` and a `List[String]` need the same logic and different storage. Writing that logic twice, or boxing every element behind a pointer to fake genericity, are both worse than what this part covers.

## 21. Generics and Monomorphization

Gata generics are **monomorphized**: the compiler stamps out one real, fully concrete copy per distinct set of type arguments actually used. There is no boxing, no type erasure, and no runtime type information anywhere in the language.

```go
class Box[T] {
    public T v;
    func _init() { }
    public T func Get() { return self.v; }
}

realm kernel {
    entry func Main() {
        let Box[int] b = new Box[int]();
        let int v = b.Get();
    }
}
```

`Box[int]` and `Box[String]` become two separate concrete classes, each with its own copy of every member. `Box` itself is a *template*, not a type — you cannot declare a `let Box b;`, because there is no such thing.

The cost is generated code: every instantiation is real code in the image. The benefit is that a generic class behaves exactly like a hand-written one — `Box[int]` stores a real `int32_t`, not a pointer to a boxed one; `b.Get()` is a direct call, not a virtual one. For a language whose output is a kernel image measured in tens of kilobytes, that trade is the right way round: you pay for the instantiations you use, and you pay nothing for dispatch.

The instance is mangled internally as `Box_int`, but **diagnostics always show `Box[int]`.** You will never have to read a mangled name to understand an error message.

### There are no constraints

There is no `T : Comparable`, no `where` clause, no bounds of any kind. A generic template is checked **only through its stamped instances**.

That has a precise and initially surprising consequence: a generic body may use any operation at all on `T`, and nothing complains until some instantiation makes it concrete. `T func Max[T](T a, T b) { if (a > b) ... }` is accepted as written; `Max(3, 7)` stamps a version where `>` is integer comparison and compiles; `Max(myList, myOtherList)` stamps a version where `>` does not exist and fails.

When that failure happens, it is reported **once**, with a hint naming the instantiation that caused it — so you get "in `Max[List[int]]`, no `>` operator on `List[int]`" rather than an unexplained error inside a template you did not write.

This is duck typing, deferred to compile time. It is less expressive than a real constraint system and considerably simpler, and it fits the language's scale: a program whose generic instantiations are all visible in one build does not need a way to state contracts across compilation boundaries that do not exist.

### Generic classes and unions

```go
class Map[K, V] { }
union Result[T, E] { Ok(T v), Err(E e) }
```

Multiple parameters are comma-separated. Type parameters are **plain names** — `class Foo[Bar[Baz]]` is `G053` — and a duplicate parameter name is `G003`.

Chapter 20 covers the one rule specific to generic unions: how the compiler picks an instantiation when you write `Optional.Some(3)` rather than `Optional[int].Some(3)`.

### Generic functions and methods

Free functions and methods may be generic, with their own type parameters independent of any enclosing class's:

```go
T func Max[T](T a, T b) { if (a > b) { return a; } return b; }

class Bag {
    public T func Echo[T](T x) { return x; }
}

module Algorithms {
    public T func Min[T](T a, T b) { if (a < b) { return a; } return b; }
}
```

**Type arguments are always inferred from the argument types.** There is no explicit form, and writing one is `G097`:

```go
let int a = Max(3, 7);                    // T = int, inferred
let int64 b = Max(10L, 4L);               // T = int64
let int c = Max[int](3, 7);               // error[G097]
```

`G097`'s existence rather than a silent parse failure is deliberate: `f[T](x)` looks so much like other languages that it needs an error that says *why* it is not one. `[...]` after a name means "generic type arguments on a type", and a function is not a type. When inference cannot see enough to decide, the fix is to give an argument the type you mean, not to annotate the call.

### What inference can bind

Inference unifies a parameter against an argument in exactly three shapes:

- a **bare** parameter of type `T`, against any argument;
- a **`T*`** parameter, against a pointer argument;
- a **`Box[T]`** parameter, against a `Box[int]` argument — structurally, and **one level deep only**.

```go
T func First[T](List[T] xs) { return xs.Get(0); }

let int x = First(myIntList);   // T = int, from the List[int]-ness of the argument
```

Two failure modes:

- **A type parameter that appears in no parameter position cannot be inferred** — `G007`. There is nothing to infer it from. A function like `T func Zero[T]()` is not writable; use `default(T)` inside a function that has a `T` somewhere in its parameters, or take the type from a parameter you already have.
- **Two arguments binding the same parameter to different types** is `G009`. `Max(3, 4L)` does not silently widen the `int` — it reports that `T` cannot be both.

That second rule is worth appreciating. Overload resolution (Chapter 15) is happy to widen an argument; generic inference is not. The difference is that a widening in overload resolution picks between functions you wrote, while a widening in inference would *invent* an instantiation you did not ask for, and pick which of your two arguments to reinterpret. Writing `Max(3L, 4L)` costs one character and says which you meant.

### The stamping-order limit

This is the one place where the pass order from Chapter 3 becomes visible in ordinary code, so it is worth understanding rather than memorising.

Generic **types** are monomorphized early, in a pass over the syntax tree. Generic **functions and methods** are stamped later, during resolution, once inference has decided what `T` is.

A generic function body may therefore name a generic type over its *own* type parameter — and that instantiation only becomes concrete after the pass that would have created it has already run:

```go
T func Wrap[T](T x) {
    let Box[T] b = new Box[T](x);   // error[G007]: 'Box[Widget]' is never instantiated
    return b.Get();
}
```

The diagnostic says exactly this and names the fix: name the instantiation once, anywhere outside a generic function, and it is created normally, after which the generic body finds it.

```go
let Box[Widget] _seed = new Box[Widget](new Widget());   // now Wrap(new Widget()) compiles
```

The same body inside a generic *class* has no such problem, because both stampers are then the early one.

In practice this bites when writing a generic helper that uses a container internally. The seeding line is the workaround; giving the helper a concrete parameter type is the other.

### Why `libgata`'s algorithms are a separate module

The distinction between a *method's own* generic parameters and a *class's* generic parameters matters for one specific risk, and it explains a piece of the standard library's shape.

**Every member of a generic class is stamped unconditionally for every instantiation of that class.** So giving `List[T]` a `Sort()` method that used `<` directly on the class's own `T` would break `List[List[int]]` — there is no `<` on `List[int]` — and every other non-comparable `T`, *even though nobody ever called `Sort` on one*.

A method's own, independently generic parameters do not have this problem: they are stamped lazily, per call site, exactly like a free function. So `Algorithms.Sort[T](List[T] xs)` is only ever stamped for the `T`s you actually sort.

`libgata` keeps its sorting and searching in an `Algorithms` module for a related but distinct reason — keeping `T`-agnostic algorithms decoupled from any one container — but the stamping asymmetry above is why the naive alternative would not have worked anyway.

### Other limits

- **Type arguments nest at most 6 deep** for on-demand instantiation, which is the resolution loop's round limit from Chapter 3 showing through. `List[List[List[List[List[List[int]]]]]]` is where you find it, and nothing real does.
- **A generic type and a non-generic type of the same name collide** — `G003`. `Box` and `Box[T]` in one scope are two meanings of one name, and Chapter 30's "one meaning per name per scope" rule applies to them as it does to everything else.

### Ambiguity across files

A bare call to a generic free function always wins over an equally-named sibling method or free function elsewhere in scope. Rather than resolve that silently, the compiler reports `G069` and tells you how to qualify:

```go
// Sorting.g
T func Find[T](List[T] xs, T target) { /* ... */ }

// Searching.g
T func Find[T](List[T] xs, T target) { /* ... */ }

// main.g
import "Sorting.g";
import "Searching.g";

let int a = Sorting.Find(myList, 5);     // qualified: unambiguous
let int b = Searching.Find(myList, 5);   // qualified: unambiguous
```

Qualify through whichever mechanism fits: `Module.Name(...)` for a real module or class, `self.Name(...)` for a sibling instance method, or the file-namespaced form `FileName.Name(...)` — Chapter 31 covers that last one, which works for any free function, generic or not.

With generics covered, the next part leaves the language proper and takes up the thing Gata exists for: the execution topology of the program.


# Part VII: Realms, Processes, and Threads

Chapter 2 told you, without proof, that `realm kernel { }` and `realm userspace { }` are genuinely different execution worlds, and that the difference is load-bearing enough to be syntax rather than convention. This part makes good on that. It covers the three levels of Gata's topology — realm, process, thread — and the one kind of storage that outlives a function.

Everything here is *declaration structure*, not logic. A realm holds no code of its own, a process holds no logic of its own, and a thread holds exactly one function. What they do is decide where declarations are emitted, what runs them, and who can see them.

## 22. Realms

There are exactly two realms, `kernel` and `userspace`. A realm block groups declarations belonging to one execution environment, and it decides the **translation unit** they are emitted into.

```go
realm kernel {
    entry func Main() { }
}

realm userspace {
    int func Helper() { return 1; }
}
```

A GatOS program genuinely runs two different kinds of code: kernel code, privileged and running as part of the boot sequence with direct hardware access; and user-space code, scheduled, sandboxed, and organised into processes and threads the way a normal OS would be. The two are compiled into separate C files and linked differently. Making the split syntax rather than convention means it is structurally impossible to write user-space logic that ends up in the kernel, or vice versa — not because a linter caught it, but because the declaration was never in that translation unit to begin with.

### The rules

- **Realm blocks cannot nest** — `G051`. There is no `realm kernel { realm userspace { } }`.
- **`kernel` without `realm` is `G085`**, with a hint. Writing `kernel { }` is a natural mistake and gets a specific message rather than a parse error.
- **Any other word after `realm` is `G086`**, with a "did you mean" hint. There are two realms and there will not be a third.

### A realm is one namespace, however many blocks

This is the rule most worth internalising, and the one most commonly assumed backwards.

**Several blocks may open the same realm** — in the same file, or across files — and they are **one scope**. Opening `realm kernel { }` in twenty files does not create twenty kernels; it describes one kernel in twenty places.

```go
// mm.g
realm kernel { class PageTable { public int root; } }

// sched.g
realm kernel { int func Tick() { return 1; } }

// main.g
realm kernel { entry func Main() { let PageTable p = new PageTable(); } }
```

`main.g` sees `PageTable` because both declarations are in the kernel realm's scope, not because of any import relationship between the blocks.

This is what makes a kernel of any real size writable. Without it, every kernel-realm declaration in the program would have to live in one physical block in one file, or leave the realm scope entirely. Chapter 30 covers the scope semantics; the structural point here is that **what stays singular is the entry point, not the block** (Chapter 4).

### What may go in a realm block

A realm block may hold:

```
classes, modules, enums, unions
native blocks, native types, @extern declarations
free functions
processes
@environment
```

It may **not** hold:

- **imports** — `G001`. Imports are file-level, not scope-level.
- **other realms** — `G051`.
- **threads** — `G001`. A thread belongs to a process.
- **`let`** — there are no realm variables. Only processes have storage.

### Which realms a build has

You do not declare which realms exist; the **environment file** does, by which `@preamble` targets it contains (Chapter 34). A GatOS environment normally provides both realms; a Hosted environment provides only the user one.

The structural rules from Chapter 4 follow from that:

- A **GatOS** build has a `realm kernel` with exactly one `entry func` (`G002` for none, `G059` for more than one), and any number of `realm userspace` blocks whose entry points are thread entries — a free `entry func` there is `G068`.
- A **Hosted** build has **no** `realm kernel` block at all (`G055`), and a `realm userspace` with exactly one `entry func` (`G058` for none, `G059` for more than one), which becomes the generated C `main()`.

## 23. Processes and Threads

### Processes

A **process** is pure deployment topology: a named bag of threads, plus its own declarations and state. It holds no logic itself.

```go
realm userspace {
    foreground process App {
        thread Ui     { entry func Run() { } }
        thread Worker { entry func Run() { } }
    }
    background process Daemon {
        thread Loop { entry func Run() { } }
    }
}
```

Underneath, a process maps to a genuine GatOS process: its own address space, its own TTY handle if it is a foreground process, and a thread group.

**The mode is written before `process`, and it is mandatory.**

```go
foreground process App { }        // correct
background process Daemon { }     // correct
process App { }                   // error[G060] — the mode is mandatory
process App : foreground { }      // error[G060] — the mode goes before 'process'
```

The second error message exists because `:` is such a natural thing to reach for. In Gata, `:` belongs to the conditional operator and to nothing else in a declaration, so a declaration reaching for it is told where the mode actually goes rather than left with a syntax error about a `{` that never arrived.

`foreground` owns TTY focus; `background` is hidden, and the generated launcher calls the environment's proc-hide binding for it (Chapter 34). All threads of a process share its console and its visibility — which is why the mode belongs to the process and not to a thread.

Process rules:

- **A process must be inside a realm.** At the top level it is `G001`.
- **Processes cannot nest** — `G051`.
- **A process with no threads is `G091`.** It would be created at boot, do nothing, and never be reclaimed. If a process has no thread, it should not exist.
- **Two processes of the same name in one realm is `G003`.** In *different* realms is fine — they are different scopes (Chapter 30).
- **An `entry func` in a process body, rather than in a thread, is `G068`.** A process's entry points are its threads.

A process body may hold: threads, classes, modules, enums, unions, native blocks, native types, `@extern` declarations, free functions, and `let` process variables. Not: imports, realms, or other processes.

### Kernel processes

A process may be declared in **either** realm, and the realm decides what its threads are.

```go
realm userspace {
    foreground process App { thread Ui { entry func Run() { } } }
}

realm kernel {
    background process DiskDriver { thread Loop { entry func Run() { } } }
}
```

A process in `realm userspace` compiles into the user translation unit and its threads are spawned as sandboxed user-space threads. A process in `realm kernel` compiles into the kernel translation unit and its threads are spawned as **genuine kernel threads**, with kernel privileges. The generated launcher passes a user/kernel flag per thread, and that flag is the whole difference at the spawn site.

This is how you write a driver: a background kernel process with a loop thread, sharing the kernel's address space, invisible to the user.

### Threads

```go
thread Worker {
    entry func Run() { }
}
```

**A thread body contains exactly one `entry func` and nothing else** — `G053` otherwise. No helper methods, no fields, no second entry, no nested declarations.

That is a stronger restriction than it first appears, and it is worth defending. A thread is not a scope, not a type, and not a namespace; it is a name attached to a start routine. Everything a thread needs beyond its own code belongs one level up, in the process — which is exactly where the shared state lives (Chapter 24) and where the process's own helper functions and types go.

The entry function's rules:

- **Its name is documentation only.** The *thread* is what names it. `Run` is the convention; nothing depends on it.
- **It takes no parameters** — `G061` — and **has no return type** — `G053`. The runtime dispatches it through a fixed `void(*)(void*)` ABI, so there is nothing to pass in and nothing to receive back. This is why threads need process variables to communicate at all.
- **It cannot be `throws`** — `G061`. There is no caller to receive the error. Handle failure inside the thread.
- **Access and storage modifiers on it are `G053`.**

And on the thread declaration itself:

- **`foreground`/`background` on a thread is `G043`.** Only a process has a mode.
- **Threads cannot nest** — `G051` — and a **thread outside a process is `G001`**.

### Entry functions in general

`entry` marks a function as invoked by the boot sequence or the scheduler, never by your code. **Calling an `entry` function directly, or taking its address, is `G030`** (Chapter 12).

There are exactly two shapes: a free `entry func` at a realm's top level (the kernel's boot entry on GatOS, or `main` on Hosted), and a thread's `entry func`. Chapter 4 covers how many of each a build may have.

## 24. Process Variables

Threads in one process share an address space, and the scheduler preempts them on timer interrupts — which means two threads touching the same data is both possible and, done naively, a genuine data race. `x = x + 1` compiles to a load, an add, and a store; preempt between the load and the store and another thread's update is silently overwritten. The compiler and CPU are also free to reorder plain memory accesses, so even "I set a flag, then you read it" is broken without explicit ordering.

`libgata`'s `Sync` module (Chapter 37) is the floor for both problems: `AtomicInt`, a 64-bit counter whose every operation is a single indivisible instruction, and `SpinLock`, a test-and-set lock that yields the CPU between failed attempts so a contended lock does not starve its holder on a single core.

That leaves one structural question. Thread entry functions take no parameters, and Gata has no global variables — so how do two threads reach the *same* `AtomicInt`?

### The answer

A `let` written **directly in a process body** declares one variable belonging to the process: a single instance, shared by every thread of that process, initialised once before any thread is spawned, and living as long as the process.

```go
realm userspace {
    foreground process Demo {
        // One of each, shared by both threads below. Reference counted like any
        // other value — these are ordinary Gata objects, not raw pointers.
        let AtomicInt hits = new AtomicInt();
        let SpinLock  lk   = new SpinLock();
        let int       half = 100000;

        thread Boss {
            entry func Run() {
                for (let int i = 0; i < half; i = i + 1) { hits.Increment(); }
                while (hits.Get() < ((half * 2) as int64)) { Sys.Yield(); }
                Console.PrintLong(hits.Get());   // exactly 200000 — no lost updates
                Console.NewLine();
            }
        }
        thread Worker {
            entry func Run() {
                for (let int i = 0; i < half; i = i + 1) { hits.Increment(); }
            }
        }
    }
}
```

Both threads hammer the counter 100,000 times concurrently, and the printed total is exactly `200000`. With a plain `int`, preemption would eat some of those updates and the count would come up short.

### The rules

**The type is mandatory, and so is the initializer** (`G100`). Unlike a local `let`, neither may be omitted.

This is the rule with the most reasoning behind it. A process variable is read by threads that never ran the line declaring it, so there is no point in the program at which a later assignment could be *known* to have happened first. Definite-assignment analysis, which catches an uninitialised local (`G098`, Chapter 25), cannot be established here at all — there is no single control-flow path to analyse. So the declaration has to carry the value.

**Initialisers run in declaration order**, and an initializer may only read the variables above it (`G098`):

```go
background process P {
    let int a = b + 1;   // error[G098] — process variable 'b' is read before it is initialised
    let int b = 2;
    let int c = c;       // error[G098] — process variable 'c' is read by its own initialiser
}
```

They run as one generated function, top to bottom, so a variable further down still holds nothing — zero for a primitive, `null` for a class. This is an *ordering* mistake rather than a scope error: the name resolves fine, it just has no value yet, and the diagnostic says so. Reading the variable being declared gets its own tailored message.

**A `catch` handler on one must end in `assign`** (`G100`). A throwing initializer is allowed with a handler, under the same "every path supplies a value" rule a local declaration gets (`G082`, Chapter 29). What a handler here may *not* do is `return`: the only function to return from is the generated initialiser, so returning would abandon this variable *and every one declared below it* while the gate still reports the state as ready. `break`, `continue`, and `throw` are already rejected by the rules that cover them elsewhere.

**They belong to their process.** Code outside cannot see one, and naming the path explicitly does not help: `kernel.P.n` is `G089`, because a scope qualifier disambiguates between *enclosing* scopes and a process is not one of those from outside it (Chapter 30). Everything inside can see it — the threads, and any function the process declares.

**Each process gets its own.** Two processes may use the same name; they are separate storage.

**They are never released.** A process variable holds its value for the life of the image; nothing runs a destructor on one. That is what makes it safe to read from any thread at any time, and it means a managed process variable is a deliberate, permanent allocation rather than something to churn.

**A local of the same name shadows it, and warns** (`G070`). That direction is the dangerous one: without the warning, a thread would read and write its own copy while believing it shared one.

**Duplicate names are `G003`, and annotations on one are rejected.**

### Why this and nothing else

A process variable is the only storage in Gata that outlives a scope, and that is deliberate.

A process is the one construct where "one of these, shared by everything inside it" has an unambiguous meaning: its threads already share an address space, and the scope tree already makes its declarations visible to exactly them. A module-level variable or a `static` class field would have no such boundary — it would be a global with extra steps. Both are rejected (Chapter 16).

Underneath, each variable becomes a file-scope static in its realm's translation unit, and the initialisers become one generated function. Every thread of the process calls a gate before its own first statement; exactly one thread runs the initialiser and the rest wait for it, so "initialised before first read" holds by construction rather than by scheduling luck.

### Sharing across processes

Process variables stop at the process boundary, which is the right default — two userspace processes have separate address spaces, so a shared instance between them is not a thing that can exist.

When you do need a bridge *within one realm* (kernel-realm processes share the kernel's address space), the fallback is a native static (Chapter 33), published once with release/acquire ordering:

```go
realm kernel {
    native {
        static void* g_hits;
        static volatile int g_ready;
    }

    void func Publish(AtomicInt hits) native {
        // Counted by hand: the slot is a raw pointer reference counting cannot see,
        // so without this the object dies with the scope that made it.
        __atomic_add_fetch(&((gata_obj*)hits)->__rc, 1, __ATOMIC_RELAXED);
        g_hits = hits;
        __atomic_store_n(&g_ready, 1, __ATOMIC_RELEASE);
    }
    AtomicInt func SharedHits() native {
        void* p = g_hits;
        if (p) __atomic_add_fetch(&((gata_obj*)p)->__rc, 1, __ATOMIC_RELAXED);
        return p;   // returned at +1: the caller's scope will release it
    }
    bool func Ready() native { return __atomic_load_n(&g_ready, __ATOMIC_ACQUIRE) != 0; }
}
```

Two things about that accessor are easy to get wrong. A native body handing back a managed reference must return it at **+1**, because the caller's scope releases what it was given — return it at +0 and every call quietly decrements the count until the object is freed out from under its users. And `retain(x);` as a *statement* is not the way to pin the slot: `retain` returns the reference it counted rather than marking an object in place, so discarding that result is a no-op the compiler rejects outright (`G099`, Chapter 35).

### Three idioms worth internalising

Every threaded Gata program ends up using these:

- **Reach for a process variable first.** It is checked, reference counted, and scoped to exactly the threads that should see it. The native bridge is for crossing a process boundary, not for ordinary sharing.
- **A native slot is hand-counted.** Reference counting cannot see a raw pointer, so anything stored in one has to be counted by hand on the way in and handed back at +1 on the way out.
- **Atomics coordinate phases; locks protect invariants.** An `AtomicInt` is right for counters and done-flags — single-word facts. A `SpinLock` is right when a *multi-step* mutation has to appear indivisible: appending to a shared `List[T]`, for instance, is a length check, a possible grow, a store, and a length bump, and no atomic covers all four. Wrap it in `lk.Lock()` / `lk.Unlock()` instead.

The same `Sync` types work in kernel-realm processes and on Hosted unchanged; only the yield underneath them differs — a scheduler call, a syscall, or a host yield, all behind Chapter 34's `_env_yield`.

With the topology settled, the next part goes back inside a function body and covers what can actually be written there.


# Part VIII: Statements and Expressions

Everything so far has been about *declarations* — what a program is made of. This part is about what runs: the statement forms that make up a function body, and the expression forms that make up a statement.

Two of Gata's most consequential decisions live here, and both are subtractions. **Assignment is a statement, not an expression**, so `if (x = 1)` cannot compile. And **conditions must be `bool`**, so there is no truthiness to reason about. Between them they remove the two largest sources of "it compiled and did the wrong thing" in the C family.

## 25. Statements

### Blocks and declarations

```go
{
    let int a = 1;         // typed
    let b = 2;             // inferred (Chapter 14)
    let int c;             // declared, unassigned
    c = 3;
}
```

A bare block introduces a scope. An **empty block body** on a control statement is `G025`, a warning — an `if (x) { }` is almost always either a leftover or a missing `!`.

The declaration rules:

- **Redeclaring a name in the same scope is `G003`.**
- **A local with the same name as a parameter of the same function is `G003`**, even though they are lexically different scopes. They share one C scope in the emitted output, so the compiler reports it rather than emitting a shadow you cannot see. Shadowing inside a *nested* block is fine.
- **A local shadowing an outer-scope local is `G070`**, a warning.
- **A name beginning with two underscores is `G003`** (Chapter 5).

```go
void func F(int p) {
    let int p = 1;           // error[G003] — parameter and top-level local share one scope
    { let int p = 2; }       // fine, and warns G070 — a nested block
}
```

Bindings are introduced by `let`, by parameters, by `for x in`, by `match` case bindings, and by a `for (let ...)` init clause. All five follow the same rules.

### Read before assignment

A `let` without an initializer stores nothing. For a class or `String` that means `null`; for a primitive it means whatever the memory already held. Reading one before assigning it is `G098`:

```go
let int x;
let int y = x + 1;          // error[G098]: 'x' is read before it is assigned
```

The check is deliberately **one-sided**. A branch counts as assigning if *any* arm does, a loop counts before its body runs, and passing `ref n` or taking `&n` counts:

```go
let int n;
if (ready) { n = 1; }
Use(n);                     // accepted
```

That is not an oversight. A definite-assignment analysis that is exactly right requires either whole-program path analysis or a rule that rejects correct programs, and rejecting correct programs is how a check becomes something people work around. This one reports only the reads that **no store could possibly have preceded** — it catches the read that is certainly wrong and stays out of the way of the ones that merely might be.

Managed locals are exempt entirely: they start as `null`, which is a defined value.

### Assignment

**Assignment is a statement, never an expression.**

```go
x = 1;
x += 2;  x -= 2;  x *= 2;  x /= 2;  x %= 2;
x &= 3;  x |= 3;  x ^= 3;  x <<= 1;  x >>= 1;
```

```go
if (x = 1) { }             // error[G045], hint: did you mean '=='?
while (x = f()) { }        // error[G045]
let int y = (x = 1);       // error[G045]
```

This is the single largest safety win in the language for the smallest cost. The `if (x = 1)` bug is not caught by a warning that can be suppressed or a convention that can be forgotten; the grammar has no production for it. What you give up is the assignment chain `a = b = c` and the `while ((n = read()) > 0)` idiom, both of which have two-line replacements.

Rules:

- **The target must be an lvalue**: a variable, a field, an element, or a dereference. Otherwise `G034`.
- Compound **bitwise and shift** forms require integer operands; the **arithmetic** forms require numeric ones. Otherwise `G004`.
- **`a op= b` on a class uses that class's `op` operator overload** if one exists (Chapter 27). There is no separate `+=` to declare.
- **Assigning a value to itself is `G071`**, a warning. `x = x` compiles and does nothing.

### `if` / `else`

```go
if (cond) { }
if (cond) { } else { }
if (a) { } else if (b) { } else { }
if (cond) doIt();           // a single statement, no braces
```

**The condition must be `bool`** — `G029`. There is no truthiness: `if (n)` on an integer, `if (p)` on a pointer, and `if (s)` on a string are all errors. Write `n != 0`, `p != null`, `s != null`.

Two warnings live here. A **constant condition** is `G073` — `if (true)` is either debugging residue or a mistake. And **comparing a value with itself** is `G078`.

### `while`

```go
while (i < 10) { i++; }
while (true) { break; }     // a constant condition is fine here
```

Loop conditions are exempt from `G073`: `while (true)` and `for (;;)` are the idiomatic infinite loops, and warning about them would be noise.

### C-style `for`

```go
for (let int i = 0; i < 10; i++) { }
for (i = 0; i < 5; i++) { }             // the init may be a plain assignment
for (let int j = 0; j < 100; j += 7) { }
for (let int k = 64; k > 0; k >>= 1) { }
for (;;) { break; }                      // all three clauses are optional
```

- **The body must be a block.** No brace-less `for`.
- **The step clause may not declare a variable** — `G044`.
- Everything declared in the init clause is scoped to the loop.

### `for..in`

The structural loop. No parentheses, and the body must be a block:

```go
let [3]int a = [1, 2, 3];
for x in a { }

let List[int] xs = new List[int]();
for v in xs { }
```

**Iterable means one of exactly two things:**

- a fixed array, or
- any class with **both** `Length()` returning an integer **and** `Get(int)`.

That is the entire protocol. There is no interface to implement, no trait to derive, and no iterator object — a class that has those two methods is iterable, structurally, whether or not its author intended it. Anything else is `G032`, and the message names *which half* is missing, which is nearly always the actionable part.

```go
for x in 5 { }              // error[G032]
for (x in xs) { }           // error[G044] — a for..in loop takes no parentheses
```

The `Length()`/`Get(int)` shape is chosen over a `Next()`-style iterator because it needs no allocation and no state object: the loop lowers to an index counter and two direct calls, which monomorphize away to nothing for a container like `List[T]`.

### `switch`

```go
switch (n) {
    case 0, 1 { }           // several labels per arm
    case 2    { }
    default   { }
}
```

- **The scrutinee must be an integer or an enum** — `G004`. For a union, use `match` (Chapter 20).
- **Each arm is a block. There is no fallthrough**, and no `break` is needed to prevent it.
- **`break` and `continue` inside a case target the enclosing loop**, not the switch. This follows directly from there being no fallthrough — `break` has no switch-related job left to do, so it keeps its loop meaning, and a `switch` inside a loop reads the way you would want.
- Labels must be comparable to the scrutinee — `G004`.
- A duplicate constant label is `G003`; two `default` arms are `G003`.
- **`default` is optional, and there is no exhaustiveness requirement.** This is the deliberate difference from `match`: an integer switch cannot be exhaustive in any meaningful sense, and an enum's value set is open at the boundary (an `int` can be cast into it), so demanding exhaustiveness would be demanding a lie.

### `break` and `continue`

```go
while (true) { if (done) { break; } continue; }
```

Outside a loop, either is `G022`. Inside a `defer` body, either is `G062`.

### `return`

```go
void func A() { return; }
int  func B() { return 1; }
```

Covered in Chapter 15: every path of a non-`void` function must return (`G027`), mixing the two forms is `G010`, and a trailing `return;` at the end of a `void` function is `G026`. Inside a `defer` body, `return` is `G062`.

### `unsafe`

```go
unsafe {
    let int n = 1;
    let int* p = &n;
    *p = 2;
    let int* q = p + 1;
}
```

Everything that requires an `unsafe` block, all `G033` outside one:

- address-of, `&x`
- dereference, `*p`
- pointer indexing, `p[i]`
- pointer arithmetic, `p + n` and `p - n`
- `p++` / `p--` on a pointer
- pointer casts
- calling the retain/release ARC intrinsics

And here is the part that is not about pointers at all, and that catches people:

> **`unsafe` also suppresses automatic reference counting for the whole block.** No owning stores, no consume-retains, no scope releases.

Inside an `unsafe` block you are the memory manager, for *everything* in it, not just for the pointers. That is the correct semantics — a block that is hand-managing an object's count cannot also have the compiler managing it — but it means an `unsafe` block should be as small as the operation that needed it. `G093` warns when an unsafe block allocates a managed value that it therefore never releases.

Chapter 35 covers the ownership model this is opting out of.

What deliberately does *not* require `unsafe`: `ref` parameters (Chapter 26), which are compiler-checked rather than raw; array indexing, where no pointer is involved; field access; calling a method whose own body uses `unsafe` internally, since unsafety does not propagate through a call boundary; and writing or comparing against the `null` literal.

### `defer`

The deferred statement runs on **every** exit from the enclosing block, in LIFO order with other defers.

```go
unsafe {
    let buf = alloc(1024 as usize) as char*;
    defer free(buf);
    // ... every path from here frees buf
}

defer { a(); b(); }         // a block works too
```

"Every exit" means: falling off the end, `return`, `break`, `continue`, and the error-unwind path out of a `throws` function (Chapter 29). Multiple defers in one block run last-written-first, the same convention as Go and Swift.

One ordering guarantee is worth knowing: **a deferred statement runs before its block's owned-local releases** (Chapter 35), so it can still safely reference and use those locals.

The restrictions, all `G062` (or `G072` for the last):

- **A defer body cannot transfer control**: no `return`, `break`, `continue`, `throw`, or `assign`. A deferred action runs on paths that are already leaving; there is no sensible target for it to jump to.
- **A defer body cannot itself `defer`.**
- **A defer body cannot be a declaration.** `defer let x = 1;` would declare a variable that goes out of scope immediately.

### The `native` statement

```go
realm kernel {
    entry func Main() {
        native { /* raw C, inline here */ }
    }
}
```

Raw C spliced into the middle of a Gata function body. Remember from Chapter 15 that it is invisible to flow analysis — a `return` inside one does not satisfy `G027`.

### `debug` and `panic`

Two first-class diagnostic statements:

```go
debug "reached here";      // routed to the environment's debug binding
panic "unrecoverable";     // routed to the environment's panic binding
```

- **Both take a string literal only** — `G044` otherwise. Not an interpolated string, not an expression, not a variable.
- **Both are `G036` in a Release build**, with the message "remove it before shipping".
- **`panic` is valid only in the kernel realm** — `G031` elsewhere.

Each of those is doing real work.

*Literal-only* is what makes these statements rather than library calls. A `debug` that took an expression would need string conversion, which needs an allocator, which a kernel's early boot may not have yet. A literal is a pointer into the image, available at every point in the boot sequence.

Because of that, the working idiom for "log a computed value" is to assert in Gata and emit a fixed marker:

```go
if (hits.Get() == (200000 as int64)) { debug "count-ok"; }
```

A missing marker in the log *is* the failure report — grep-able, deterministic, and with no formatting code in the hot path.

*Rejected in Release* rather than compiled away means there is no quiet "your logging just vanished" behaviour to trip over. A shipping Release kernel does not carry the diagnostic floor at all, and the compiler tells you at build time rather than at 3am.

*Kernel-only `panic`* is a privilege statement: halting the machine is not something a sandboxed user process should be able to do directly.

On GatOS, each realm has its own debug serial channel, and `appa run` captures both into your project: `artifacts/debug.log` for the kernel (plus GatOS's own boot logging) and `artifacts/user-debug.log` for userspace. On Hosted it typically goes to stderr, depending on the environment's wiring.

### Expression statements

```go
DoWork();
x++;
```

An expression used as a statement for its side effects. **`G072` fires when the expression computes a pure value and throws it away**, including the classic `a == b;` where `a = b;` was meant — which gets a tailored hint rather than the generic message.

Note the exemption: a *call* is never treated as side-effect-free, so ignoring a return value stays silent. Gata has no `[[nodiscard]]`, and a function called for its effects is the normal case.

## 26. Expressions

### Precedence, lowest to highest

| Level | Operators | Notes |
|---|---|---|
| 1 | `?:` | ternary, right-associative |
| 2 | `\|\|` | |
| 3 | `&&` | |
| 4 | `\|` | |
| 5 | `^` | |
| 6 | `&` | |
| 7 | `==` `!=` | |
| 8 | `<` `>` `<=` `>=` | |
| 9 | `<<` `>>` | |
| 10 | `+` `-` | |
| 11 | `*` `/` `%` | |
| 12 | `as` | binds **tighter** than `*`, **looser** than unary |
| 13 | `!` `~` `-` `&` `*` | prefix unary |
| 14 | `++` `--` `.` `[]` `()` `catch` | postfix |
| 15 | primary | |

**Assignment does not appear on this table**, because it is a statement.

Four consequences worth knowing before they bite:

```go
x * y as T       ==  x * (y as T)
-x as T          ==  (-x) as T
a < b == c < d   ==  (a < b) == (c < d)
a & b == c       ==  a & (b == c)        // C's precedence, and C's trap
```

The last one is inherited deliberately. Gata's precedence table matches C's wherever C has one, because the alternative — a *slightly* different table — is worse than either matching or diverging visibly. `&` binding looser than `==` is a genuine C wart, and the fix is the same in both languages: parenthesise.

`as`'s position is the one real divergence, and it exists because `as` takes a *type* on its right, so there is no expression for it to compete with. Sitting between unary and multiplicative makes `-x as int` mean `(-x) as int` and `x.Field as int` mean `(x.Field) as int`, both of which are what you would want.

### Primary expressions

```
42  0xFF  1.5  2.5f  'a'  "text"  $"x={x}"  true  false  null
identifier
self
(expr)
[1, 2, 3]                  array literal
new T(...)                 object construction
sizeof(T)
default(T)
::Name  kernel.Name  userspace.Name      scope-qualified names (Chapter 30)
```

### Calls

Every call shape in the language:

```go
f(1, 2);                   // a free function
obj.Method(1);             // an instance method
Class.Static(1);           // a static method
Module.Func(1);            // a module function
self.Helper();             // a sibling instance method
fp(1);                     // through a function-pointer variable or field
File.func(1);              // file-namespaced (Chapter 31)
Union.Variant(1);          // union construction (Chapter 20)
```

### Member access and indexing

```go
p.x                        // a field load
Color.Red                  // an enum constant
a[0]                       // a fixed array or pointer element
list[0]                    // a class's [] operator
list[0] = v;               // a class's []= operator
```

Indexing something that is neither an array, a pointer, nor a class with `[]` is `G012`. A non-integer index is `G004`.

Assigning through `[]` when only a getter exists is `G038`. And using a *compound* assignment when only a setter exists is `G038` too — `xs[i] += v` needs both halves, since it reads through `[]`, applies the operator, and writes through `[]=`.

### `new`

```go
let Point p = new Point(3, 4);
let List[int] a = new List[int]();
```

A **collection initializer** may follow, in either brace or bracket form. It desugars to repeated `Add` calls, and requires a one-argument `Add` method on the class (`G006`/`G008` otherwise):

```go
let List[int] xs = new List[int]() { 1, 2, 3 };
let List[int] ys = new List[int]() [ 1, 2, 3 ];
let List[int] zs = new List[int] { 1, 2, 3 };     // constructor args are optional
```

`new` on anything that is not a class is `G011`, and the message names the right move each time: on a **module**, on a **primitive** ("use `let`"), on a **union** ("construct a variant"), on an **enum** ("name a member"), or on a class not in scope ("import its module").

### Array literals

```go
let [3]int a = [1, 2, 3];
let b = [1, 2];                 // infers [2]int
```

The element type is **the first element's type**, and every subsequent element must be assignable to it (`G004`). `[]` alone has no element type and is `G004` — write the type on the declaration and the elements will follow.

### The ternary

```go
let int m = a > b ? a : b;
let int band = a < 2 ? 0 : (a < 5 ? 1 : 2);
```

- **The condition must be `bool`** — `G029`, same as `if`.
- **The two arms are unified** by a specific rule: identical types; numeric widening to the wider type; `String` against `String`; pointer covariance including `void*`; or `null` against a class or pointer arm.
- Anything else is `G004`, and `null : null` in particular cannot be unified — there is no type to give the result.

Remember the lexical trap from Chapter 8: a `::`-qualified branch needs a space after the `:`.

### Unary operators

```go
!flag                      // bool only         (G004 otherwise)
-n                         // numeric, non-bool (G004 otherwise)
~bits                      // integer           (G004 otherwise)
&x                         // address-of, unsafe only
*p                         // dereference, unsafe only
```

`!`, `~`, and unary `-` dispatch to a class's zero-parameter operator overload when one exists (Chapter 27).

### Postfix `++` and `--`

```go
i++;  i--;
```

- The operand must be an **lvalue** (`G034`) and **numeric** (`G004`), or a pointer inside `unsafe`.
- On a class, they dispatch to the zero-parameter `++`/`--` overload, which **mutates in place and must return `void`**.
- **There is no prefix form.** `++i` does not parse as an increment (Chapter 8).

### `sizeof` and `default`

```go
let usize n = sizeof(int);
let usize m = sizeof(Point);
let int    z = default(int);        // 0
let Point  p = default(Point);      // null
let T      t = default(T);          // the zero value of a generic parameter
```

`sizeof` always yields `usize`. `default(T)` yields `T`, and is the answer to "I need a `T` and I have nothing" inside a generic body — which, given there are no constraints and therefore no way to require a constructor, comes up more than you would expect.

### `ref` arguments

`ref` gives a callee direct read/write access to your variable, with no copy and no reference-counting churn — and without a raw pointer or the `unsafe` block one would require.

```go
void func Bump(ref int n) { n = n + 1; }

realm kernel {
    entry func Main() {
        let int x = 1;
        Bump(ref x);            // fine
        Bump(x);                // error[G037] — the parameter is 'ref'
    }
}

void func Take(int n) { }
Take(ref x);                    // error[G037] — the parameter is not 'ref'
```

**`ref` is written at both the declaration and the call site**, and a mismatch in either direction is `G037`. That symmetry is the entire ergonomic point: unlike C++'s silent reference parameters, a `ref` argument is always visually obvious at the call site, so you can see which calls can modify your locals by reading the call.

The rules:

- **`ref` is legal only as a direct call argument** matching a `ref` parameter. It is not a type, not a local modifier, and not a return form.
- **The argument must be an lvalue** — `G034`.
- **Its type must match exactly.** No conversion applies, not even widening. `Bump(ref myShort)` against `ref int` is `G037`, because a conversion would need a temporary, and writing back into a temporary would silently do nothing.
- **`ref` cannot be used in an indirect call** through a function pointer (`G037`), and a function with a `ref` parameter cannot be used as a function-pointer value (`G004`) — the type cannot express `ref` (Chapter 12).

For a *managed* value, `ref` means the callee operates on the caller's own reference rather than receiving a new owned one, so no extra retain/release happens:

```go
func Swap[T](ref T a, ref T b) {
    let tmp = a;
    a = b;
    b = tmp;
}

let String s1 = "hi";
let String s2 = "there";
Swap(ref s1, ref s2);       // aliases correctly, with no reference-counting churn
```

That is why `ref` does not require `unsafe`: it is a compiler-checked, reference-counting-correct aliasing mechanism, not a hole in the type system.

With statements and expressions covered, the next part takes up the two ways a type customises how those expressions behave on it: operator overloading, and conversion.


# Part IX: Operators and Conversions

Two mechanisms let a user-defined type behave like a built-in one: operator overloading, which gives a class meaning under `+`, `==`, `[]` and the rest; and conversion, which decides when one type's value may stand in for another's. They are related — one of the overloadable "operators" is the conversion itself — so they belong together.

## 27. Operator Overloading

Without operator overloading, every value-like type — a `Money`, a `Vec`, `libgata`'s own `String` — would need named methods where an operator reads better. Gata supports a fixed, deliberately small set: enough to make value-like classes feel native, without opening the door to arbitrary operator soup.

### Syntax

```
[modifiers] operator [ReturnType] func <symbol> ( params ) { body }
```

The return type goes **after `operator` and before `func`**, mirroring how every other function leads with its type. Omitting it takes the default for that operator.

```go
class Money {
    int cents;

    public operator Money func +(Money other) {
        let Money m = new Money();
        m.cents = self.cents + other.cents;
        return m;
    }
    public operator bool func ==(Money other) { return self.cents == other.cents; }
}
```

Operators are **class members only** — never on a module, never as a free function. They follow the same private-by-default rule as every other member: an unmarked operator used from outside its class is `G035`.

### The complete overloadable set

| Symbol | Params | Default return | Constraint |
|---|---|---|---|
| `+` | 1 | the class | |
| `-` | 1 | the class | binary subtraction |
| `-` | 0 | the class | unary negation — same symbol, arity decides |
| `*` | 1 | the class | |
| `/` | 1 | the class | |
| `%` | 1 | the class | |
| `<` | 1 | `bool` | must return `bool` |
| `>` | 1 | `bool` | must return `bool` |
| `<=` | 1 | `bool` | must return `bool` |
| `>=` | 1 | `bool` | must return `bool` |
| `==` | 1 | `bool` | must return `bool` |
| `!=` | 1 | `bool` | must return `bool` |
| `&` | 1 | the class | |
| `\|` | 1 | the class | |
| `^` | 1 | the class | |
| `<<` | 1 | the class | |
| `>>` | 1 | the class | |
| `!` | 0 | `bool` | must return `bool` |
| `~` | 0 | the class | |
| `++` | 0 | `void` | must return `void`; mutates in place |
| `--` | 0 | `void` | must return `void`; mutates in place |
| `[]` | 1 | the class | index getter |
| `[]=` | 2 | `void` | index setter |
| `as` | 1 | the class | conversion **into** this class; implicitly static |

**Not overloadable:** `&&`, `||`, `=`, every compound assignment, and the ternary.

The exclusions are principled rather than arbitrary. `&&` and `||` short-circuit, and an overload would be a function call whose arguments are both evaluated — the operator would silently stop meaning what it says. Compound assignments do not need to be overloadable because they *compose*: `a += b` uses the class's `+` automatically. And `=` is not an operator at all in Gata (Chapter 25).

### Every shape, in one class

```go
class Vec {
    public int x;

    public operator Vec  func +(Vec o)   { return self; }   // binary
    public operator Vec  func %(Vec o)   { return self; }
    public operator Vec  func -()        { return self; }   // unary negate
    public operator Vec  func -(Vec o)   { return self; }   // binary subtract
    public operator bool func !()        { return self.x == 0; }
    public operator Vec  func ~()        { return self; }
    public operator func ++()            { self.x = self.x + 1; }
    public operator func --()            { self.x = self.x - 1; }
    public operator bool func ==(Vec o)  { return self.x == o.x; }
    public operator bool func <(Vec o)   { return self.x < o.x; }
    public operator bool func >(Vec o)   { return self.x > o.x; }
    public operator int  func [](int i)  { return self.x; }
    public operator func []=(int i, int v) { self.x = v; }
    public operator Vec  func <<(int n)  { return self; }
}
```

Unary `-` (zero parameters) and binary `-` (one parameter) coexist on one class; the arity decides which is meant, at both the declaration and the use.

### Semantics and diagnostics

**Dispatch is on the left operand's class.** `money + money` finds `Money.+`; `int + money` does not. There is no reversed-operand lookup and no "friend" declaration, which means an operator between two unrelated types has exactly one home: the left one.

**Wrong parameter count is `G008`.** A wrong return type on a comparison, `!`, `++`/`--`, or `as` is `G004`.

**`==` and `!=` derive from each other.** Declaring only `==` makes `a != b` compile as `!(a == b)`, and vice versa. A class can declare both, but one spelling can never silently fall back to pointer identity while the other compares values.

**Relational operators do *not* derive from each other.** Declaring `<` but not `>` is `G092`, a warning, and using the missing one is `G004` with a hint naming the ones the class does have. The asymmetry with `==`/`!=` is intentional: `!=` is exactly the negation of `==`, but `>` is *not* the negation of `<` — `!(a < b)` includes equality. Deriving it would be silently wrong for every type with a partial order.

**Compound assignment composes.** `a += b` uses the class's `+`. And `xs[i] += v` reads through `[]`, applies the *element type's* operator, and writes back through `[]=` — which is why a get-only indexer rejects compound assignment (`G038`, Chapter 26).

**`+` with a `String` on either side is always concatenation.** The other side is stringified by the rules in Chapter 28, and a user `+` overload does **not** intercept it. This is a deliberate carve-out: `"count: " + n` has one obvious meaning, and letting a class hijack it would make string building depend on which operand happened to be on the left.

**Comparison against the `null` literal never reaches an operator.** `x == null` and `null != x` always compile to a raw pointer-identity check, even when the class declares `operator ==`.

That last rule is what makes value equality safe to write at all. An `operator ==` body can open with `if (other == null) { return false; }` without recursing into itself, and a null check stays a one-instruction test rather than a method call. `libgata`'s `String` is the canonical case: `a == b` compares *contents*, `a == null` compares the pointer.

### Conversion operators (`as`)

The last overloadable "operator" is not a symbol at all. A class may declare how to convert *other* types into itself, and `value as ClassName` invokes it.

The declaration lives on the **destination** class, takes the source value as its one parameter, and returns an instance of the declaring class. It is implicitly **static** — there is no `self` — so it is a factory in operator clothing:

```go
@builtin(String)
class String {
    public operator String func as(char c)   { return String.FromChar(c); }
    public operator String func as(int n)    { return Int.ToString(n); }
    public operator String func as(bool b)   { return b ? "true" : "false"; }
    public operator String func as(char* r)  { return String.FromRaw(r); }
}

let String s = 42 as String;
```

`as` is the **only** operator that may be declared more than once on a class — one per source type. A second `as` from the same source type is `G003`. If the return type is written at all, it must be the declaring class (`G004`).

**Conversions never chain.** If `A` converts to `B` and `B` converts to `C`, `a as C` does not compile. Chaining would make the set of legal conversions depend on the whole program's declarations, and a conversion two hops away from where you are reading is exactly the kind of implicit behaviour this language avoids.

Conversions also only ever point **inward** — a class converting other things into itself. Converting a class *outward* to a primitive is what an ordinary named method is for, and the invalid-cast diagnostic (`G028`) says so.

## 28. Conversions and Casts

### Implicit conversions

These happen without a cast, and this list is exhaustive:

- **Numeric widening only**, by promotion rank (Chapter 9): `int → int64`, `short → int64`, `int → double`. Narrowing is `G004`.
- **An integer literal into any numeric type it fits in.**
- **A float literal into a float type.**
- **`null` into any class reference, pointer, or function pointer.**
- **`String` into `String`.**
- **Pointer covariance** where the pointees match or either side is `void*`.

```go
let int64 a = 5;           // an int literal, widened
let int64 b = someInt;     // widening
let int   c = someInt64;   // error[G004] — narrowing needs a cast
let byte  d = 300;         // error[G004] — the literal does not fit
```

That last diagnostic is worth noting for its message: it tells you **what would be stored and by how much the value overflows**, rather than only that it does not fit. `300` into a `byte` reports that it would become `44`.

### Explicit casts

There are two forms, and they are **not interchangeable**:

```go
(PrimType) expr            // C-style — PRIMITIVES ONLY
expr as Type               // the general form
```

```go
let int    n = (int) 3.9;
let int    m = someInt64 as int;
let char   c = 65 as char;
let int    e = Dir.North as int;      // enum -> int
let Dir    d = 1 as Dir;              // int  -> enum
let String s = 42 as String;          // a user-defined `as` operator
```

Why two forms exist: `(UserType) x` would be syntactically ambiguous with a parenthesised expression followed by a variable. Restricting the parenthesised form to primitive *keywords* — which can never be an expression — resolves it without lookahead. In practice, prefer `as` everywhere; the C-style form exists so that C-shaped numeric code transliterates cleanly.

**What a cast may do**, exhaustively:

- numeric ↔ numeric
- enum ↔ integer
- pointer ↔ pointer, and pointer ↔ integer (both `unsafe` only, `G033`)
- `null` → a class reference or pointer
- anything → a class that declares a matching `as` operator

Everything else is `G028`. In particular you **cannot cast a class out to a primitive**, and the diagnostic suggests writing a named conversion method instead. Casting to or from `void` is `G028`.

**`G074`** is a warning for a cast to the type the value already has — *except* on a literal, where it is accepted as deliberate width pinning. `0x00100000 as int` is not redundant; it is a statement about how wide that constant is meant to be, and the language treats it as one.

### Arithmetic result types

A binary arithmetic or bitwise expression **resolves at the higher-ranked operand type**, and **both operands are converted into it before the operation runs**. Shifts are the exception: they resolve at the *left* operand's type, and the count is not converted into it.

The result type is the real one, not an approximation of it. `byte + byte` is a `byte` everywhere, not only when you store it back into one:

```go
let byte a = 200;
let byte b = 200;
let byte r = a + b;                     // 144
Console.PrintLine($"{a + b}");          // also 144 — not 400
if (a + b == 144) { }                   // taken
```

This is the concrete meaning of the promise in Chapter 9: a value's width and signedness mean the same thing in every position, so an expression cannot be worth one thing in a variable and another thing in an argument. C's integer promotions do the opposite — they widen everything to `int` behind your back — and the resulting "it works until it doesn't" arithmetic is exactly what fixed widths exist to prevent.

### The signedness guard

Mixing a signed operand with an unsigned one is where that promise runs out.

For `+`, `-`, `*`, `&`, `|`, `^`, `<<`, `==`, and `!=` it does not matter: the answer is the same bit pattern whichever type wins.

For `/`, `%`, `<`, `<=`, `>`, and `>=` it **decides the answer**. If the operand being converted cannot be represented in the type it converts to, the conversion changes what the value means: a `uint` of 4000000000 read as an `int` is negative, and an `sbyte` of −1 read as a `ushort` is 65535. Rather than pick for you, Gata rejects it with **`G095`** and asks which domain you meant — the hint names which side to cast:

```go
let int  a = -10;
let uint b = 3;
let int  bad        = a / b;                // error[G095]
let int  asSigned   = a / (b as int);       // -3
let uint asUnsigned = (a as uint) / b;      // 1431655762
```

The direction that loses nothing stays silent: an unsigned operand widening into a strictly larger signed type keeps every value it had, so `int64 / uint` is fine. A signed operand that is a non-negative constant is also fine, which is why `hx >= 0x40862E42` against an unsigned `hx` needs no cast.

### The other arithmetic guards

- **`G079`** — a *literal* shift count outside `[0, width)`. The bound follows the left operand's own width, so `32` is illegal for `int` and fine for `int64`. Both cases are undefined behaviour in the emitted C.
- **`G075`** — integer division or remainder by a **literal zero**. This traps at runtime on every target. Float division is defined (infinity) and is not reported.
- **`G004`** — `%` on floating-point operands. C's `%` is integer-only, and silently routing to `fmod` would hide an allocation-free operation becoming a library call. Use the `Math` module's function.
- **`G096`** — a warning on `'a' + 'b'`. That adds codepoints; it does not join text. Convert a side with `as String` to concatenate.

### Conversion to `String`

Where a `String` is required — the parts of an interpolation, and the non-`String` side of a `+` with a `String` — the compiler converts using this list, in order:

| Source | Converted by |
|---|---|
| `float` / `double` | `@intrinsic(stringify_float)` |
| `char` | `@intrinsic(stringify_char)` |
| `bool` | `String`'s `as(bool)` operator |
| unsigned integer | `@intrinsic(stringify_uint)` |
| other numeric | `@intrinsic(stringify_int)`, or `stringify_long` above 32 bits |
| a class | its `String func ToString()` method |

A class with **no `ToString`** used in an interpolation is `G004`, and the message names exactly that signature so the fix is a copy-paste:

```go
class P {
    public int n;
    public String func ToString() { return "P"; }
}

let String s = $"{new P()}";      // fine
```

Note the mix of mechanisms in that table: the numeric conversions go through `@intrinsic` roles (Chapter 32), so the compiler never hardcodes a runtime function name, while `bool` goes through an ordinary user-visible `as` operator and classes go through an ordinary method. That is not inconsistency — it is the same principle applied at three levels. Anything the compiler *generates* is bound by role; anything you can write yourself is written yourself.

With conversion covered, the next part handles the one remaining way an expression can fail to produce a value.


# Part X: Handling Failure

A function can fail. This part is about the one mechanism Gata offers for saying so, and the three places a failure may be handled.

## 29. Error Handling: `throws`, `throw`, `try`, `catch`, `assign`

### The model

**There are no exceptions.** No stack unwinding through arbitrary frames, no catch-by-type, no exception objects, no `finally`.

A `throws` function returns a generated `Result_T` struct — conceptually `{ T value; bool has_error; }` — and the compiler generates the check after every call. Failure is a plain signal: **`throw;` carries no payload.**

```go
throws int func Parse(String s) {
    if (s == null) { throw; }
    return 7;
}
```

The absence of a payload is the design decision that everything else follows from, so it is worth defending before the syntax. An error payload needs a type, and a type that every failure in the program can be described by is either an allocation (an exception object, in a kernel that may be out of memory precisely when things are failing) or an enumeration that every library must agree on. Gata declines both. A `throws` function says *this can fail*; if it needs to say *how*, it returns a `union` (Chapter 20) — `Result[T, E]` is three lines of ordinary Gata — and the caller matches on it.

What `throws` buys over returning a union is that **the failure cannot be ignored**. A union's `Err` case can be dropped on the floor; a `throws` call that is not handled is a compile error.

### Declaring one

`throws` goes **before the return type**:

```go
throws int func F() { }
throws void func G() { }
throws func H() { }              // identical to G
```

`throws void func F()` and the return-type-less `throws func F()` are two spellings of one thing: the call can fail, and on success it produces no value. They behave identically everywhere, `return;` included.

Rules:

- **`throw;` takes no operand.** There is nothing to give it.
- **`throw` outside a `throws` function or a `try` block is `G021`.**
- **A `throws` function cannot return a pointer, a fixed array, or a function pointer** — `G066`. Legal returns are `void`, primitives, enums, unions, `String`, and classes. The excluded three are the types the generated `Result_T` struct cannot wrap cleanly.
- **`_init` and `_deinit` cannot be `throws`** (`G067`, Chapter 17), and neither can an `entry func` or a thread entry (`G061`, Chapter 23). In each case the caller is generated code with nowhere to put the failure.

### The three legal positions

A call to a `throws` function must be in **one of exactly three places**, or it is `G021`.

**(a) Inside a `try` block:**

```go
try {
    let int v = Parse(s);
} catch {
    // runs when anything in the try block threw
}
```

**(b) Inside another `throws` function**, where the failure propagates automatically:

```go
throws int func Outer(String s) {
    let int v = Parse(s);      // propagates on failure; no syntax needed
    return v;
}
```

**(c) With its own inline `catch` handler:**

```go
let int v = Parse(s) catch { assign 0; };
```

Note what (b) means in practice: inside a `throws` function, calling another `throws` function looks like an ordinary call. There is no `?` operator, no `try` keyword at the call site, and no explicit propagation. The signature already said this function can fail; repeating it at every call would be noise.

### `try` / `catch` as a statement

```go
try { Risky(); } catch { Recover(); }
```

- Both parts are **blocks**.
- **`catch` binds no error variable.** `catch (e) { }` does not exist, and writing it is `G044`. There is no error object to bind, because `throw` carries no payload.
- **`try` introduces a scope**, so a variable declared inside it is not visible after.
- **`break` inside a catch handler exits the enclosing loop.**

That third point is the one that makes `try` the wrong shape for the most common case of all — reading one value and carrying on:

```go
try {
    let String name = Console.InputLine();
    // everything that uses `name` is now trapped in here,
    // because `name` dies at the closing brace
} catch {
    Console.PrintLine("read failed");
}
```

Which is exactly what the third position exists to fix.

### The inline `catch` handler and `assign`

A `catch` block may be attached **directly to a call**. The declaration stays in the enclosing scope, and the handler supplies a replacement value with `assign`:

```go
let String name = Console.InputLine() catch { assign "anonymous"; };
Console.PrintLine($"hello, {name}");     // still in scope — no nesting
```

```go
let int v = Parse(s) catch { assign 0; };
v = Parse(s) catch { assign -1; };
```

`assign <expr>;` supplies the value for the declaration or assignment the handler is attached to, and then **execution continues in the same scope**. Unlike `try`, no new scope is introduced. That is the whole feature: `f() catch { … }` counts as handling the failure, exactly like wrapping the call in a `try`, but without stranding the value inside a block.

`assign` is its own keyword rather than a reuse of `return` for one reason: inside a handler, `return` still means "return from the enclosing function", and the two need to stay visibly different.

### The handler rules

**A handler must cover a whole declaration or a whole plain assignment.** It cannot sit on a call nested inside a larger expression (`G021`), nor on a compound assignment or an index-setter assignment (`G021`).

**Every path out of a handler must either `assign` a value or leave through `return`, `throw`, `break`, or `continue`.** Otherwise `G082` — a path that fell out of the bottom would leave the variable declared but unset.

```go
let int port = Parse(s) catch {
    if (IsEmpty(s)) { assign 8080; }
    else            { assign 0; }        // both arms assign: fine
};
```

```go
int func ReadPort(String s) {
    let int port = Parse(s) catch { return -1; };   // give up on the whole function
    return port;
}

throws int func ReadPortOrFail(String s) {
    let int port = Parse(s) catch { throw; };       // propagate to our own caller
    return port;
}

while (true) {
    let int c = Parse(s) catch { break; };
}
```

Handlers nest, and each `assign` belongs to its own declaration:

```go
let int x = Parse(a) catch {
    let int fallback = Parse(b) catch { assign 0; };   // assigns `fallback`
    assign fallback;                                   // assigns `x`
};
```

**`assign` outside a catch handler is `G081`** — including inside a `try` block or a plain `catch { }` block, neither of which has a declaration to assign to. And `assign` inside a `defer` body is `G062` (Chapter 25).

**`catch` after a call that cannot fail is `G021`**, with the message "remove the catch block". A handler that outlived its reason to exist gets reported rather than silently ignored — which matters when a function *stops* being `throws` and you want to know where the now-dead handlers are.

**`catch` after something that is not a call at all is `G044`.**

**The assigned value must be assignable to the target type** — `G004`.

### Statement position

A handler may go on a call whose result you are discarding. There is no declaration behind it, so the handler is pure control flow:

```go
throws void func Flush() { throw; }

Flush() catch { Recover(); };
```

And because there is nothing to supply, `assign` there is `G081`:

```go
Parse(s) catch { assign 0; };            // error[G081]
```

For a `throws void` function specifically, `G081`'s message says exactly why: "this call produces no value, so there is nothing for `assign` to supply."

### The nesting restriction

A throwing call may **never appear inside a larger expression**:

```go
let int v = Parse(a) + Parse(b);        // error[G021]
let int w = f(Parse(a));                // error[G021]
let int z = c ? Parse(a) : 0;           // error[G021]
let String s = "n=" + Parse(a);         // error[G021]
v += Parse(a);                          // error[G021]
```

```go
// do this instead
let int p = Parse(a) catch { assign 0; };
let int q = Parse(b) catch { assign 0; };
let int v = p + q;
```

The reason is mechanical and worth understanding, because it explains why the rule cannot simply be relaxed. A throwing call's error branch has to **unwind the current frame** — release its owned locals, run its pending defers, and either jump to a handler or return a failure `Result`. There is no sensible place to put that unwinding halfway through evaluating a bigger expression, where some subexpressions have been computed into temporaries and others have not.

Two related notes follow:

- **`catch` binds tighter than any operator**, so `a + f() catch { … }` groups as `a + (f() catch { … })`. But the rule above still applies, so that example is rejected anyway. Bind it to a local first.
- **A handler does not cover the call's arguments.** In `Outer(Inner())`, `Inner` fails before `Outer` is ever entered, so `Outer(Inner()) catch { … }` leaves `Inner`'s failure unhandled and reports `G021`.

### What happens on the way out

When a `throw` fires, three things happen before control leaves, in this order:

1. Pending `defer` actions in the block run, LIFO (Chapter 25).
2. The block's owned locals are released (Chapter 35).
3. The function's `Result` is set to the failure state, or control transfers to the enclosing `try`'s handler.

Steps 1 and 2 happen at *every* scope the unwind passes through, not just the innermost one. This is what makes `defer` a genuine cleanup mechanism rather than a convenience for the happy path: a `defer free(buf);` runs whether the function returned normally, broke out of a loop, or threw.

The next part goes back to names, and covers how a program with more than one file keeps them straight.


# Part XI: Names Across Scopes and Files

Gata has two independent name systems, and most confusion about names comes from conflating them. This part separates them, covers the annotation that makes shadowing explicit, the qualifier syntax that reaches past a shadow, and the rules that govern names spread across files.

## 30. Scoping, Shadowing, and Scope Qualifiers

### The two axes

**Local scopes** are ordinary lexical nesting: blocks, function parameters, loop variables, `match` bindings. They behave the way you expect from any C-family language.

**Declaration scopes** are the scope *tree*: the root (the top level of the build), each realm, and each process. A declaration in one of these is a distinct, globally unique name.

These are genuinely separate systems. A local is in no declaration scope at all — which is why a scope qualifier can reach *past* a local of the same name, as you will see below.

### Local scoping

```go
realm kernel {
    entry func Main() {
        let int a = 1;
        {
            let int a = 2;       // warning[G070] — shadows the outer 'a'
        }
        let int a = 3;           // error[G003] — same scope
    }
}
```

The rules were covered in Chapter 25; the summary is that same-scope redeclaration is an error, nested shadowing is a warning, and a parameter shares a scope with the function's top-level locals.

### The scope tree

```text
root
 |- kernel                    (realm)
 |    |- P                    (process inside kernel)
 |- userspace                 (realm)
      |- App                  (process inside userspace)
```

A declaration written inside a realm or a process belongs to that scope. What may be scoped: **classes, modules, enums, unions, native types, free functions, and process variables.** Anything else — a native block, an import — is not a name and holds no scope slot.

Two processes may declare identical names with no collision whatsoever, because they are different scopes:

```go
realm userspace {
    foreground process One {
        class Shared { public int ticks; }
        thread T { entry func Run() { } }
    }
    background process Two {
        class Shared { public int frames; }    // a different type entirely
        thread T { entry func Run() { } }
    }
}
```

And, as Chapter 22 established, **a realm is one namespace however many blocks open it**, in one file or across files:

```go
// a.g
realm userspace { int func Step() { return 2; } }

// b.g
realm userspace {
    foreground process P {
        thread T { entry func R() { let int v = Step(); } }   // finds a.g's Step
    }
}
```

### Name lookup

An unqualified name is looked up **outward**: the current process, then its realm, then root. The innermost match wins.

That is one sentence, and it is the whole rule. There is no "using" directive, no search of sibling scopes, and no fallback to a file's imports beyond what root already contains.

### Shadowing is legal but never silent: `@shadows`

Because lookup goes outward and the innermost match wins, an inner declaration can quietly take a name away from an outer one. Gata does not allow that to happen silently.

**Displacing a name from an enclosing scope requires the `@shadows` annotation.** It is `G088` without it, and `G088` to write it when nothing is displaced.

```go
int func Step() { return 1; }

realm kernel {
    @shadows int func Step() { return 2; }         // deliberate
    foreground process P {
        @shadows int func Step() { return 3; }     // deliberate
        thread T { entry func R() { let int z = Step(); } }   // -> 3
    }
    entry func Main() { }
}

realm userspace {
    int func Step() { return 9; }        // error[G088] — unmarked shadow
    @shadows int func Never() { }        // error[G088] — shadows nothing
}
```

The two-directional check is what makes the annotation worth having. If it were only required when shadowing, it would be noise you learn to add reflexively. Because writing it where nothing is displaced is *also* an error, `@shadows` in a file is always a true statement about the program, and removing the outer declaration turns every stale annotation into a compile error rather than leaving it as a lie.

`@shadows` also counts a name declared at the top level of **this file**, and one reachable through this file's imports.

There is one displacement outside the scope tree that takes the same annotation: a `private` free function displacing an imported public one (Chapter 16). That one is a **warning** (`G057`) rather than an error, because a file-local helper is not making a statement about the program's structure, and the imported name stays reachable through its file qualifier.

Everywhere else, `@shadows` may only go on a **class, module, enum, union, native type, or free function** inside a realm or process. Anywhere it can displace nothing — a thread, a process, a realm, an import, a class member, an `entry func` — is `G088`.

### One meaning per name per scope

Within one scope, a name means exactly one **kind** of thing.

Two functions of one name are overloads. Two types of one name are the ordinary duplicate error. But a **type and a function** of the same name in one scope is `G003`:

```go
realm kernel {
    class Job { public int n; }
    int func Job() { return 1; }         // error[G003]
}
```

The reason is that a scoped declaration takes over the *whole* name for lookup purposes — so if both existed, the outer meaning of that name could never be reached from inside.

A generic template counts as its own kind, so `Box` and `Box[T]` in one scope also collide (Chapter 21).

### Scope qualifiers: reaching past a shadow

`@shadows` declares the displacement. A **scope qualifier** reaches past it.

```text
::Name              the root scope — the top level of the build
kernel.Name         the kernel realm
userspace.Name      the userspace realm
kernel.P.Name       a process inside a realm
```

Qualifiers work in **expression position and in type position**, which matters because five of the six shadowable forms are types:

```go
class Cargo { public int root; }

realm kernel {
    @shadows class Cargo { public int inr; }

    class Holder { public ::Cargo held; }              // a field type
    ::Cargo func Make(::Cargo c) { return c; }         // parameter + return type
    void func Take(Box[::Cargo] b) { }                 // a generic argument

    entry func Main() {
        let ::Cargo      a = new ::Cargo();       let int p = a.root;
        let kernel.Cargo b = new kernel.Cargo();  let int q = b.inr;
        let Cargo        c = new Cargo();         let int r = c.inr;
    }
}
```

A qualifier may be followed by member access, and the compiler splits the dotted run for you — **the longest prefix that names scopes wins**:

```go
module Algo { public static int func Min(int a, int b) { return a; } }

realm kernel {
    @shadows class Algo { public int Min; }
    foreground process P {
        module M { public static int func G() { return 3; } }
        thread T {
            entry func R() {
                let int a = kernel.P.M.G() + ::Algo.Min(1, 2);
            }
        }
    }
    entry func Main() { }
}
```

### The qualifier rules

**Outward only.** A qualifier may name a scope this code is *inside* — an enclosing process, an enclosing realm, or root. Naming a sibling realm or a sibling process is `G089`. A qualifier is a disambiguator, not a new visibility rule; reaching sideways is exactly what scopes exist to prevent.

**One exact scope, and it stops there.** `kernel.Step` means the kernel realm's `Step` and nothing else. If the realm does not declare that name, that is `G090` — not a quiet walk further out to root.

**A realm exists as a scope whether or not a block opens it.** So `userspace.X` from inside the kernel is `G089` (sideways), not "unknown scope". The tree is fixed by the language, not by your program's blocks.

**A process name is a scope segment, not a value.** `kernel.P()` is `G090`.

**A qualifier reaches past a local of the same name**, because a local is in no declaration scope:

```go
realm kernel {
    @shadows int func Step() { return 2; }
    entry func Main() {
        let int Step = 9;
        let int a = Step;                   // the local, 9
        let int b = ::Step() + kernel.Step();
    }
}
```

**A qualifier does not excuse an unmarked shadow.** `G088` still fires. One says the displacement is deliberate; the other reaches past it. They are not substitutes.

**A rejected qualifier reports exactly once**, and poisons the expression so no second error is invented about the bare name.

**A scope qualifier outside any realm or process is meaningless** — `G089`. At the top level there is nothing to disambiguate against.

A qualifier costs nothing at runtime: it picks a symbol at compile time, exactly as an unqualified name does.

### Reporting a name that exists somewhere else

Three diagnostics distinguish the three ways a name can exist and still be unreachable, and the distinction is the useful part:

| Code | Means |
|---|---|
| `G087` | The name is declared inside a scope you are not in — and the message names the scope. |
| `G090` | The qualified scope exists, but declares no such name. |
| `G089` | The scope does not exist, or does not enclose this code. |

And a name declared in a scope as a **different kind** reports "`X` is a function here, not a type" rather than "unknown type".

That last one is worth calling out as a pattern rather than a detail. Gata's diagnostics consistently try to answer "what did I actually find?" rather than "what did I fail to find". An "unknown type `X`" when `X` is right there as a function sends you looking for a missing import that does not exist.

## 31. Files, Imports, and Cross-File Names

### What a file can see

Itself, plus the **transitive closure of its imports**. Nothing else, even if it is in the build and even if it compiled fine.

That was covered in Chapter 15; this chapter is about what happens when two files want the same name.

### Name collisions across files

**Top-level type names are global to the build.** Two files declaring `class Widget` is `G003`, whether or not either imports the other.

This is a real constraint and worth designing around. `libgata` does, deliberately: its types are named for their module — `Optional` rather than `Maybe`, `PriorityQueue` rather than `Heap` — precisely so that a library claiming a common name does not take it away from every program that imports `List` or `Map`. Do the same in your own code: a type named `Node` in a program with two tree implementations is a collision waiting to happen, and `AstNode` and `HeapNode` cost nothing.

**Free functions may overload by parameter types across files.** Two files declaring `int func Clamp(int)` and `int func Clamp(double)` is fine, and both are visible to a file importing both. Identical signatures in two files is `G003`.

**Two imported files each declaring a public generic function of one name is `G069`**, and the message tells you to qualify.

### File-namespaced calls

The escape hatch for a collision that cannot be qualified through a class or a module: **prefix with the file's basename.**

```go
// util.g
int func Compute() { return 1; }

// main.g
import "util.g";
let int n = util.Compute();
```

The basename is the file's name without its `.g` extension, and this form works:

- for **public functions in an in-scope file**, and
- for a **private function in the current file**.

It is also how a file reaches past its own file-local function to the imported one that function displaced (Chapter 16):

```go
import "lib.g";

@shadows
private int func Clamp(int v) { return v + 1; }

let int a = Clamp(1);        // this file's
let int b = lib.Clamp(1);    // the one it displaced
```

Note that this is a *third* namespacing mechanism, distinct from the scope tree of Chapter 30 and from class/module qualification. It exists because the other two do not cover the case: two unrelated files each declaring a free function of one name are in the same scope (root) and belong to no type. The file is the only thing that distinguishes them, so the file is what you name.

### Ambiguity diagnostics

| Code | Fires when |
|---|---|
| `G069` | A bare call is ambiguous between a generic function in one file and a free function, method, or private function elsewhere. The message spells out each candidate and the qualification to use. |
| `G015` | Two overloads tie on the same conversion cost (Chapter 15). |
| `G016` | No overload matches the argument types. |

`G069`'s existence is a policy choice worth naming. A bare call to a generic free function *does* win over an equally-named sibling method — the precedence is defined, not undefined. The compiler still refuses to use it, because resolving that particular ambiguity silently means a call's meaning depends on which files happen to be imported, which changes when someone adds an unrelated `import` three files away.

With names settled, the next part goes underneath the language: the annotations that wire it to the compiler, the interop that wires it to C, and the code generation that turns it into an image.


# Part XII: The Machine Underneath

Everything up to here has been the language. This part is the seam between the language and the machine: the seven annotations that wire declarations to the compiler, the five ways to reach C, the environment file that binds a build to a real platform, the reference-counting model that runs underneath every object, and what the compiler does to your program on the way to an image.

None of it is optional reading if you intend to write a kernel. Most of it is optional if you intend to write ordinary programs — a Gata program that never says `native` never needs any of it.

## 32. Annotations

Gata has **exactly seven** annotations. Not seven that are documented; seven that exist. An unknown `@word` is `G048`, and the diagnostic lists all seven.

```
@environment   @extern   @intrinsic(role)   @preamble(target)   @keep   @builtin(name)   @shadows
```

A closed vocabulary is unusual and deliberate. Annotations in most languages are an extension point, which means their meaning lives outside the language and a reader has to know the framework to know what a program does. Gata's seven are all *compiler* facts — where a symbol goes, what role it plays, what it displaces — and there is no mechanism for adding an eighth.

### `@environment`

```go
@environment
```

Top level of a file, no argument, exactly one per build. Marks the file that provides the platform floor. Zero or two is `G000`; inside a realm block is `G064`. Covered in Chapter 15, and used in Chapter 34.

### `@extern`

```go
@extern void func _env_yield();
```

Declares that a C function exists, with no Gata body. Covered fully in Chapter 15, including the known gap: **appa emits no C prototype for one**, so the build must supply the declaration itself.

### `@intrinsic(role)`

Binds a Gata declaration to a named **compiler role**. This is the mechanism that keeps the compiler from hardcoding any runtime name at all:

```go
@intrinsic(alloc)
void* func alloc(usize n) { return _env_alloc(n); }
```

The compiler generates a call to "whatever carries the `alloc` role", not to a function named `alloc`. Rename it, move it, reimplement it — the generated code follows, because it never knew the name.

The role vocabulary is **closed**. These are all of them:

**Memory and ARC.** All five are *required* once any class survives to code generation — `G019` otherwise:

| Role | Purpose |
|---|---|
| `alloc` | raw allocation |
| `retain` | +1 a reference; returns it |
| `release` | −1 a reference; runs the destructor at zero |
| `obj_header` | the per-object ARC header type |
| `obj_init` | stamp a fresh object's header |

In practice this means: a program that declares **any** class must import `libgata`'s `Runtime` (for retain/release/obj_header/obj_init) and `Mem` (for alloc). Importing anything higher-level — `String`, `List` — pulls in both, so you will rarely hit `G019` in real code.

**Stringification**, used by interpolation and by `+` with a `String` (Chapter 28):

```
stringify_int   stringify_long   stringify_uint   stringify_float   stringify_char
```

**Environment floor.** These are optional; an unbound one falls back to a canonical C name:

| Role | Default symbol |
|---|---|
| `env_debug` | `_env_dbg` |
| `env_panic` | `_env_panic` |
| `env_proc_create` | `_env_proc_create` |
| `env_proc_hide` | `_env_proc_hide` |
| `env_thread_spawn` | `_env_thread_spawn` |
| `env_read` | `_env_read` |
| `env_alloc` | `_env_alloc` |
| `env_time` | `_env_time_ns` |

Where `@intrinsic` is valid: a free function, a class method, an `@extern` declaration, a native type, or a declaration inside a native block. An unknown role is `G017`; binding one role twice is `G018`; `@intrinsic` on a native **block** is `G041`, since only `@preamble` is valid there.

>[!CAUTION]
> `@intrinsic` and `@builtin` exist so that `libgata` can be a library rather than a compiler built-in. In a normal program you will never write either, and writing one by accident will produce `G018` against the standard library's own binding.

### `@preamble(target)`

Marks a native block as a **preamble**, emitted before all other generated output for that translation unit:

```go
@preamble(kernel)
native { #include <kernel/tty.h> }

@preamble(user)
native { #include <stdio.h> }

@preamble(boot)
native { /* the boot section, kernel visibility */ }
```

The three targets are `boot`, `kernel`, and `user`; anything else is `G042`. It is valid **only on a native block** (`G041` elsewhere), and more than one per block is `G041`.

Chapter 34 covers what each target means for output layout, and the important structural fact that **which preambles the environment declares is what decides which realms the build has.**

### `@keep`

Exempts a class or a free function from dead-code elimination **and** from dense renaming (Chapter 36):

```go
native { void call_it(void) { gata_helper(); } }

@keep
void func helper() { }
```

Both passes work by walking reachability from the entry points, and neither can read C. If your native code calls a Gata function by its mangled name, the analysis cannot see that reference — so the function gets deleted, or renamed out from under the C that calls it. `@keep` is how you tell it.

Valid on a **class and a free function only**. On a method it is `G041`; on an enum it is `G048`; on a native block, `G041`.

### `@builtin(name)`

Binds a class or a native type to a compiler builtin slot, so the compiler resolves that type from the declaration rather than by name:

```go
@builtin(String)         class String { /* ... */ }
@builtin(StringBuilder)  class StringBuilder { /* ... */ }
@builtin(Process)        native type Process { void* _opaque; }
@builtin(Thread)         native type Thread { void* _opaque; }
```

Four slots, and only four: `String`, `StringBuilder`, `Process`, `Thread` (Chapter 13). An unknown slot is `G017`; double-binding is `G018`; anywhere but a class or native type is `G041`.

### `@shadows`

Declares a deliberate shadow — of an enclosing scope's name (Chapter 30), or of an imported public function that a file-local one displaces (Chapter 16). It is `G088` when it displaces nothing.

### Where annotations are rejected outright

- on an **import** — `G048`
- on a **field** — `G048`
- on an **operator** — `G048`
- on a **thread, a process, a realm, or a process variable** — `G048`
- on an **enum or a union**, except `@shadows` — `G048`
- an **unknown `@word`** at all — `G048`, listing the seven
- **`@intrinsic` / `@builtin` / `@preamble` without a parenthesised name** — `G048`

## 33. Native Interop

Gata compiles to C, and when you are building an operating system you inevitably need to escape the language: to write a hardware register, lay out an ABI-compatible struct, or hand a function to a scheduler that expects a raw C pointer.

There are **five distinct ways** to reach C, and the distinctions matter — reaching for the wrong one is the most common native-interop mistake.

### 33.1 `native { }` — a raw C block

```go
native {
    void* make_handle(void) {
        return (void*)1;
    }
}
```

Legal at the top level, inside a realm, inside a process, and as a statement inside a function body. The C is captured verbatim and spliced into the emitted output.

**Placement decides the translation unit.** Top level is shared; inside `realm kernel` goes to the kernel unit; inside `realm userspace` to the user unit.

This is what makes per-realm implementations possible without a per-realm Gata declaration. When a function's implementation must genuinely differ by privilege level, give it one Gata declaration and put a same-named C helper in each realm's own block:

```go
realm kernel    { native { void* platform_alloc(usize n) { return kmalloc(n); } } }
realm userspace { native { void* platform_alloc(usize n) { return malloc(n);  } } }

public void* func Alloc(usize n) native {
    return platform_alloc(n);
}
```

The one Gata function's native body is spliced into every unit the declaration is visible from, and in each unit `platform_alloc` resolves to that unit's own definition.

### 33.2 `@preamble(...) native { }` — a raw C block, emitted first

The same block, moved to the top of its translation unit. Chapters 32 and 34.

### 33.3 `native type Name { }` — a C struct as a Gata type

```go
native type Handle {
    int   id;
    void* ptr;
}
```

Registers `Name` as a Gata type and emits the body verbatim as the struct body. **Its fields are invisible to Gata** — it is an opaque struct, so member access and method lookup on it are silently allowed rather than reported, because the compiler cannot see inside (Chapter 15).

### 33.4 `fields { }` — raw C members inside a Gata class

```go
class Box {
    public int tag;                  // an ordinary Gata field
    fields { volatile int raw; }     // a raw C member merged into the struct

    public void func SetRaw(int v) native { self->raw = v; }
    public int  func GetRaw()      native { return self->raw; }
}
```

The C members are merged into the generated class struct, and the class becomes **opaque-fielded**: unknown member accesses on it are no longer reported. Chapter 17.

The distinction from `native type` is worth stating plainly: a `native type` is *entirely* C, with no Gata members, no methods, and no reference counting. A class with `fields { }` is a full, reference-counted Gata class that happens to have some C storage in it. Use the first for handles the runtime owns; use the second when you want a real Gata API over C-shaped state.

### 33.5 `<signature> native { }` — a native function or method body

```go
class Bits {
    public int func Popcount(uint v) native {
        int n = 0;
        while (v) { n += v & 1u; v >>= 1; }
        return n;
    }
}
```

`self` is available as the C pointer. The body is **not seen by flow analysis** (Chapters 15 and 17), so a `return` inside a native *statement* in an otherwise-Gata body does not satisfy `G027`.

Plus `@extern` (Chapter 15) to name a C function — remembering that appa does not emit its prototype.

### What native code sees

Four facts you need before writing C against Gata's output:

**Class types are emitted as `gata_<Name>*` pointers with the ARC header first**, so any managed pointer aliases its own header at offset 0. That is what makes the hand-counting idiom in Chapter 24 possible: `((gata_obj*)p)->__rc` is valid for *any* managed pointer.

**Type parameters are substituted textually inside a native body of a generic.** This is the one place in the entire compiler where substitution is textual rather than structural:

```go
class Box[T] {
    T v;
    public usize func Size() native { return sizeof(T); }
}
// stamped as Box[int]: `sizeof(T)` becomes `sizeof(int32_t)`
```

Whole-word substitution, so a `T` inside an identifier like `TOTAL` is untouched. It is textual because the compiler cannot parse the C to find the type positions — and it works because that is exactly what you want here.

**Fixed arrays are emitted as a boxed struct** (Chapter 11), so a Gata `[N]T` is *not* a bare C array. C code reaching into one must go through the struct.

**The compiler scans native blocks for struct and typedef names** and treats them as already defined, so it does not re-emit them.

### Two C-name safety nets

**`G003` fires when two declarations would be emitted under the same C name.** Readable manglings join their parts with `_`, and `_` is legal inside each part, so `class A_B { M }` and `class A { B_M }` both spell `gata_A_B_M`. The collision is caught in `appa` rather than surfacing as a confusing C error.

**The generated process launcher is named `uapps`**, and it is reserved against a declaration that would take it over.

## 34. The Environment: Preambles and Floor Binds

Gata's language and standard library are platform-agnostic: the same `Console.PrintLine` call works whether you are booting bare metal or running under Linux. But *something* has to actually implement "write these bytes to the screen" differently in each case.

Rather than hiding that difference inside the compiler, Gata makes it an explicit, readable file: the **environment**, conventionally `env.g`.

### The environment declares which realms exist

An environment file carries `@environment`, and then one `@preamble`-marked native block per realm it provides:

```go
@environment

@preamble(kernel) native { /* raw C, kernel translation unit */ }
@preamble(user)   native { /* raw C, user translation unit */ }
@preamble(boot)   native { /* raw C, after every Gata function; kernel_main lives here */ }
```

**Which preamble targets are present is what decides which realms the build has.** A GatOS environment normally provides all three; a Hosted environment provides `user` only. If a realm's preamble is absent, that realm is not transpiled at all, and the structural rules from Chapter 4 follow directly:

- A **GatOS** build has a `realm kernel` with exactly one `entry func`, and any number of `realm userspace` blocks whose entry points are threads.
- A **Hosted** build must contain **no** `realm kernel` block at all (`G055`), and has a `realm userspace` with exactly one `entry func`, which becomes the C `main()`.

### Where each preamble is emitted

| Target | Emitted |
|---|---|
| `@preamble(kernel)` | at the very top of the kernel translation unit (`kmain.c`) |
| `@preamble(user)` | at the very top of the user translation unit (`uproc.c` or `program.c`) |
| `@preamble(boot)` | at the very **end** of the kernel unit, after every Gata type and function — GatOS only |

The `kernel` and `user` preambles must include `shared.h` themselves, at the end of the block, to expose Gata's generated class and type structures to the rest of the preamble.

`boot` is the odd one and its position is the point: it is emitted *after* all the generated code, which is exactly what a boot sequence needs. `kernel_main()` lives there, and it can call every Gata function in the image because every Gata function is already defined above it.

### The floor

Inside those blocks, the environment defines a small, fixed set of plain C functions — the **floor** — that the compiler and `libgata` assume exist regardless of platform. `libgata`'s `Console`, `Mem`, `Sys`, and the rest are thin Gata wrappers over these. If the environment is missing one that your program transitively needs, the build fails with `G020` rather than a linker error.

| Floor bind | Purpose | Required by |
|---|---|---|
| `_env_alloc(size_t) -> void*` | heap allocation | `Mem.Alloc`, all managed allocation |
| `_env_free(void*) -> void` | heap free | `Mem.Free`, ARC release |
| `_env_write(const char*, int) -> void` | raw byte-buffer output | `Console` |
| `_env_read(char*, int) -> int` | raw line input | `Console.InputLine` |
| `_env_tty_clear()` / `_env_tty_cursor(int)` / `_env_tty_color(int, int)` / `_env_tty_dims() -> int64` | TTY control | `Console` |
| `_env_yield() -> void` | cooperative yield | `Sys.Yield`, `SpinLock` backoff |
| `_env_sleep(int) -> void` | sleep | `Sys.Sleep` |
| `_env_exit() -> void` | process exit (a no-op on a GatOS kernel) | `Sys.Exit` |
| `_env_shutdown() / _env_reboot()` | machine power control | `Sys.Shutdown`, `Sys.Reboot` |
| `_env_time_ns() -> int64` | monotonic nanoseconds since boot/start | `Time.Nanos`, `Time.Millis`, `Random`'s clock seeding |
| `_env_dbg(const char*) -> void` | the `debug` statement's sink (Chapter 25) | `debug` |
| `_env_panic(const char*) -> void` | the `panic` statement's sink | `panic` |
| `_env_format(...)` | numeric→string formatting | `Format`, `Int.ToString` |
| `_env_proc_create` / `_env_proc_hide` / `_env_thread_spawn` | process and thread spawning (kernel only) | the `process`/`thread` topology (Chapter 23) |

Not every bind is required of every environment. `_env_panic` and the three process/thread binds are kernel-only, so a Hosted environment simply does not define them, and that is expected rather than a missing-floor-bind error.

### The floor drives capability discovery

The floor binds are also what capability discovery watches (Chapter 36):

- reaching `_env_alloc` marks the build as needing the **memory** subsystem,
- `_env_read` the **input** subsystem,
- the process/thread binds the **threading** subsystem,
- `_env_time_ns` the **timer** subsystem.

On GatOS the timer subsystem rides on the interrupt machinery, so a program that calls `Time.Nanos()` — or just constructs a `new Random()`, which seeds from the clock — pulls timers into the build. A program that touches none of it pays for none of it.

### The shipped environments

`envs/env.GatOS.g` and `envs/env.hosted.g`. You normally never edit them: they are the contract every `libgata` module is written against, and you would only touch one if you were porting Gata to a genuinely new platform.

`appa build` discovers the environment file by scanning for the `@environment` marker, or you pin it explicitly with `--env` (Chapter 2).

It is worth appreciating what this architecture buys. Porting Gata to a new platform is an edit to one file: define the floor in C, declare which preambles exist, and every `libgata` module and every Gata program compiles against it unchanged. Nothing in the compiler and nothing in the standard library names a platform.


## 35. The Memory Model

Manual `malloc`/`free` in C is a constant source of leaks and double-frees. A garbage collector solves that at the cost of unpredictable pauses and a collector thread a kernel may have no way to run. Gata's compromise is **automatic reference counting**: deterministic, no pauses, no collector, and no runtime you did not compile.

The compiler, not you, inserts every retain and release.

### 35.1 What is counted

Every **class instance** is heap-allocated with an ARC header — a reference count plus a destructor function pointer — at **offset 0**. That offset is a guarantee native code can rely on (Chapter 33).

What is **not** reference counted:

- primitives, enums, pointers, and function pointers
- **unions**, which are value types — though their *payloads* may be counted (below)
- **fixed arrays**, which are raw storage with no destructor (`G094`, Chapter 11)
- **modules**, which have no instances
- anything inside `unsafe`

### 35.2 What the compiler inserts

The ownership pass walks every block and applies four rules:

- **A producer hands back a +1 reference.** `new`, a call returning a managed value, a string literal's value.
- **Storing into a local, field, element, or process variable takes ownership**, releasing whatever the target held first — and doing so *through a temporary*, so self-assignment is safe.
- **Every scope exit releases the locals it owns, on every path**: falling off the end, `return`, `break`, `continue`, and `throw`. In LIFO order, mirroring declaration order.
- **At zero, `_deinit` runs**, then the object's managed fields are released, then the memory is freed.

```go
void func Demo() {
    let String s = new String("hi");   // owned: +1
    Console.PrintLine(s);
    // s is released here automatically, on every exit path from this block
}
```

A managed value passed as an **argument** is *borrowed*, not transferred — no retain happens for the call itself. The callee retains only if it actually stores the value somewhere that outlives the call. This is what makes passing objects around cheap: an argument-passing convention that retained every call would make reference counting cost proportional to call depth rather than to storage.

>[!NOTE]
> `defer` actions are spliced in **before** a block's owned-local releases (Chapter 25), so a deferred statement can still safely reference that block's locals.

### 35.3 String literals are static

A string literal's object carries a **sentinel refcount**. Retain and release both check for it and leave it alone, and its destructor never runs.

That is why a literal costs nothing (Chapter 6), and why returning one from a function that also returns freshly allocated strings is safe — the caller releases what it was given, and for a literal that release is a no-op.

### 35.4 Unions and ARC

A union whose variants can hold a managed value gets **generated retain and release functions of its own**, which switch on the tag and act on the live variant's fields. They compose exactly like the class ones, so a `List[Optional[String]]` counts correctly all the way down without anyone writing a line of it.

### 35.5 Opting out: `unsafe`

Inside an `unsafe` block, reference counting is **off for the whole block**: no owning stores, no consume-retains, no scope releases. You call the ARC intrinsics yourself.

```go
public void func Set(int i, T v) {
    unsafe {
        release(self.data[i]);
        self.data[i] = retain(v);
    }
}
```

That is `libgata`'s container idiom, and it is the shape to copy when you write your own.

Three things to know:

- **`retain(x)` returns the reference it counted.** Discarding that return value as a statement is `G099` — the +1 would land on a temporary that the same scope releases again, so the statement compiles to nothing. Store what it returns.
- **Exits still release owners from the enclosing *safe* frames.** `unsafe` turns off counting for its own block, not for the function around it.
- **`G093`** warns when an unsafe block allocates a managed value it therefore never releases. It stays silent when the block names `retain` or `release`, which is the signal that the counting is being done by hand deliberately.

### 35.6 Reference cycles

Reference counting's one genuine failure mode: two objects that keep each other alive.

The compiler detects this statically, with **Tarjan's strongly-connected-components algorithm over the class field graph**, including self-loops, and reports `G101`:

```go
class Node { public Node next; }              // warning[G101] — self-loop

class A { public B b; }
class B { public A a; }                       // warning[G101] — cycle A,B
```

Each object keeps the next one's count above zero, so none reaches zero and none is destroyed. The hint states the fix: make one field a raw pointer inside `unsafe`, which counts nothing, or restructure so ownership runs one way.

This is a warning rather than an error because a cycle is not always a leak in practice — a structure that lives for the life of the image never needed to be collected. It is promoted by `--werror` like any other warning, and reported against a declaration in your own source.

### 35.7 Manual memory

`alloc` and `free` are ordinary `libgata` functions (in `Mem.g`), bound to the `alloc` and `env_alloc` roles (Chapter 32). Combined with `defer`, manual allocation is about as safe as manual allocation gets:

```go
unsafe {
    let p = alloc(1024 as usize) as char*;
    defer free(p);
    // every path from here frees p
}
```

### 35.8 What none of this looks like

Everything in this chapter is invisible in the source. There is no `retain` you write, no ownership annotation, no lifetime parameter, and no borrow checker. There is also no GC.

If you want to *see* it, build with `appa build --pure-transpile` and read the emitted C (Chapter 2). This is genuinely worth doing once: the generated retain/release pairs are readable, and seeing them makes the rest of this chapter concrete in a way that prose does not.

## 36. Dead Code, Capability Discovery, and Output Layout

### Reachability

After resolution, the compiler walks the program from **every entry point** — `entry func`s, thread entries, and process-state initialisers — and eliminates everything it cannot reach. Then it **densifies** the surviving names, renaming them to short identifiers.

`@keep` (Chapter 32) opts a class or a free function out of both passes.

This is why an unused `libgata` module costs nothing. You can `import List;` and never construct one, and no `List` code reaches the image.

### Capability discovery

**The same walk** infers which platform capabilities the image needs — `MEM`, `INPUT`, `THREADS`, `TIME` — by watching which floor binds are reachable (Chapter 34). GatOS then builds an image carrying only those subsystems.

That is the mechanism behind the number in the foreword: a hello-world image at ~70KB against a full GatOS build at ~200KB, with nothing configured by hand.

`<CapabilityDiscovery>Off</CapabilityDiscovery>` in the manifest assumes all of them. It is the escape valve for a raw native body that reaches a subsystem through no Gata-visible call — the analysis cannot read C, so if your native code calls the timer directly, the inference will not see it.

### Emitted files

| Realms present | Files emitted |
|---|---|
| kernel + user | `shared.h`, `kmain.c`, `uproc.c`, `uproc.h`, `umain.c` |
| user only (Hosted) | `shared.h`, `program.c` — with a generated `main()` calling the validated entry func |
| kernel only | `shared.h`, `kmain.c` |

`umain.c` holds the generated launcher, `uapps()`. It creates each process through the environment's proc-create binding, hides the `background` ones, and spawns each thread with a user/kernel flag.

**No C name is hardcoded in it.** Every symbol it calls comes from an `@intrinsic` binding, which is the concrete payoff of Chapter 32's indirection: porting the OS is an edit to `env.*.g`, not a change to the compiler.

`--emit-sourcemap` (Chapter 2) writes `sourcemap.json`, mapping the densifier's renamed output names back to your original source names. It is what makes reading the emitted C practical after the renaming pass has been through it.

## 37. The Standard Library: `libgata`

The standard library is `libgata`, and you import from it **à la carte**: a program names the specific modules it uses at the top of a file.

```go
import Console;
import List;
import Math;
```

There is no umbrella import that pulls in "everything". A module you never name is not parsed and not compiled into your program at all, so unused parts of the library cost you nothing — before dead-code elimination has even run.

Each module declares its own dependencies, so importing one transitively brings in what it is built on: `import Console;` is enough to also reach `String` and `Int`, because `Console` imports them. As a matter of style, still import what you directly reference rather than leaning on another module's dependency list, which may change.

`libgata` is itself **ordinary Gata**. There is no hidden compiler magic in it beyond the handful of `@intrinsic` and `@builtin` bindings from Chapter 32 — every container, every algorithm, and `String` itself are written in the language this book describes, using only features you have now seen. Reading it is the best available answer to "how is this supposed to be used".

Its exact method names and signatures are still actively changing, so rather than print a table that would go stale within a few releases, the full current surface of every module is kept in a separate `libgata` reference document. In broad terms:

- **`Runtime`** — the reference-counting runtime itself: the object header, retain, release (Chapters 32 and 35).
- **`Mem`** — raw heap allocation and low-level buffer operations: `Copy`, `Fill`, `Compare`, and the overlap-safe `Move`, all of which work word-at-a-time rather than byte-at-a-time on aligned data.
- **`String` and `Char`** — the managed string type, and character classification and conversion helpers. `String` declares content-comparing `==`/`!=` (null comparisons stay pointer identity, Chapter 27), conversion operators so `42 as String` / `true as String` / `2.5 as String` just work, and a growable `StringBuilder` companion that interpolation lowers onto (Chapter 7).
- **`Int`, `Long`** — text conversion and parsing for the `int` and `int64` primitives, one module and one import each. `bool` gets no module: its only stdlib-visible behaviour is a two-branch conversion, so it lives directly as `String.as(bool)`.
- **`Math`, `Format`** — the usual math functions, and printf-style value formatting (Chapter 7).
- **`Console`** — console and TTY input and output. Output is batched: one `Print` is one write to the environment, whatever the string's length.
- **`Sys`** — yielding, sleeping, process exit, shutdown, and reboot.
- **`Time`** — the monotonic clock: `Time.Nanos()` and `Time.Millis()` over the `_env_time_ns` floor bind. On GatOS this is nanoseconds since boot, and using it is what pulls the timer subsystem into the build (Chapter 36).
- **`Sync`** — the thread-synchronisation floor: `SpinLock` and `AtomicInt`, built on `fields { }` and the compiler's atomic builtins, so the same types work in kernel, user, and Hosted code. Chapter 24 shows the sharing pattern they exist for.
- **`Random`** — a fast, statistically solid PRNG (`xoshiro256**`). `new Random()` seeds from the clock; `Reseed(seed)` gives a deterministic, reproducible sequence. Explicitly *not* for keys or tokens.
- **`Misc`** — boot and startup niceties, like the `Misc.PrintBanner()` from Chapter 2.
- **`Optional`** — `Optional[V]`, the "a value or nothing" tagged union (Chapter 20), plus its helpers. Named for its module rather than the shorter `Maybe`, for the reason in Chapter 31: type names are global, so a library claiming a common one takes it from every program that imports `List` or `Map`.
- **The container family** — `List` (`List[T]`), `Stack`, `Queue`, `Map` (`Map[K,V]` and `StringMap[V]`), `Set` (`Set[T]` and `StringSet`), and `PriorityQueue`, each its own import. Where an operation has a natural operator reading, the type declares the operator alongside its named method: `List[T]` declares `<<` as chainable sugar for `Add`, and `Set[T]` declares `+` and `&` for `Union` and `Intersect`.
- **`Hash`** — the hashing primitives (`Hash.Mix`, `Hash.HashString`) that the hash-table containers share. `Map` and `Set` import it; you will rarely import it directly.
- **`Algorithms`** — generic algorithms over the containers, kept separate from the collection classes for the stamping reason in Chapter 21. `Sort` / `IsSorted` / `BinarySearch` / `Min` / `Max` are duck-typed over `operator <`; alongside them sits a comparator family — `SortBy`, `MinBy`, `MaxBy` — taking a `func(T, T) -> bool` "less" function (Chapter 12), for ordering types with no `<` or ordering them differently.

### Two conventions worth copying

**Don't make a module just to back one conversion.** If a primitive's only stdlib-visible behaviour is "turn it into or out of a `String`", that is an `as` operator on `String` (Chapter 27), not a standalone module with a `ToString`/`Parse` pair. A module earns its own file when it has real, non-conversion behaviour — `Int` and `Long` still justify theirs because they own parsing *and* arbitrary-radix, overflow-checked formatting beyond a single ternary. `bool`'s conversion is a two-branch ternary, so it lives as `String.as(bool)` with no module at all.

**Prefer an operator over a same-named method** when the method already matches one of Chapter 27's overloadable shapes and a sibling type in the same family already uses the operator form for the same concept. But do not manufacture an operator for a method with no natural operator reading — `Contains`, `Length`, and friends stay named methods.


# Part XIII: Reference

The chapters in this part are lookup material. Chapter 38 is worth reading once, start to finish, because an absence is harder to discover than a feature. The rest are tables — keep them bookmarked.

## 38. What Gata Does Not Have

Stated explicitly, because every absence here is a design choice rather than an unfinished feature, and because each one is a frequent question.

**Type system and dispatch**

- no **inheritance**, no **interfaces**, no **virtual dispatch** — a class is exactly its own members, and behaviour chosen at runtime is a function-pointer field (Chapter 12) or a union (Chapter 20)
- no **generic constraints or bounds** — a template is checked through its stamped instances (Chapter 21)
- no **explicit type arguments at a call site** — `G097`
- no **runtime type information** of any kind
- no **`const`**

**Memory**

- no **garbage collector** — reference counting, inserted by the compiler (Chapter 35)
- no **global variables** — process variables are the only shared state (Chapter 24)
- no **static fields**, no **module fields**

**Functions**

- no **closures or lambdas** — function pointers only, with no captures
- no **varargs**
- no **default parameter values**
- no **named arguments**
- no **constructors other than `_init`**, no **destructors other than `_deinit`**

**Control flow and expressions**

- no **exceptions** — failure is a `Result`, and `throw` carries no payload (Chapter 29)
- no **error variable in `catch`**
- no **assignment as an expression** (Chapter 25)
- no **truthiness** — conditions must be `bool`
- no **implicit narrowing**
- no **switch fallthrough**
- no **prefix `++`/`--`**
- no user-overloadable **`&&`**, **`||`**, or compound assignment (Chapter 27)

**Structure**

- no **nested classes, nested functions, nested realms, nested processes, or nested threads**
- no **`for..in` over a user-defined iterator protocol** other than `Length()` + `Get(int)`

**Lexical**

- no **Unicode identifiers**
- no **nested block comments**

Read as a list it looks austere, and it is worth being clear about what the austerity is buying. Every item above is either something a freestanding kernel genuinely cannot afford (a collector, unwinding, RTTI), or something whose absence removes an entire category of "it compiled and did the wrong thing" (truthiness, implicit narrowing, assignment-as-expression, fallthrough). None of them is on the list because it was hard.

## 39. Diagnostics Reference (G000–G101)

Every error and warning `appa` produces carries a stable code, so you can search this table — or the compiler source — for exactly what triggered it, rather than parsing prose alone.

Codes are assigned **sequentially in declaration order**. There is no category-block numbering scheme, no "G0xx = structural" convention reserving room; a new diagnostic is simply the next integer. Severity is a property of the diagnostic, not of its range: the warnings are marked *(warning)* below, and everything else is an error.

Warnings never stop a build on their own. Pass `--werror` to promote them.

**Warnings are reported only for files you wrote.** A diagnostic landing inside `libgata` is neither printed nor promoted by `--werror`, the way a C compiler leaves its system headers alone — because you cannot act on it, and because putting one of your own types into a container drags the library's internals into analyses aimed at your code. `List[MyUnion]` would otherwise report `G093` against every `retain` into `List`'s raw storage, which is the standard library's own correct idiom, and `G083` against its generated `==`, at lines in a file you do not own. **Errors** inside `libgata` are still reported in full — an error there is a real failure — and when your own file has one too, yours is shown first.

Suggestions are never folded into the message text. A diagnostic carries zero or more *hints*, and the renderer prints each on its own `= help:` line beneath the source snippet, after the caret:

```
warn.g:15:20: error[G075]: integer division by a literal zero
   |
15 |         return y / 0;
   |                    ^
   |
   = help: this traps at runtime; guard the divisor or use a non-zero constant
```

| Code | Fires when |
|---|---|
| G000 | A file- or project-level problem: a missing file, a missing or duplicated `@environment`, a missing library module (Ch. 15). |
| G001 | Topology declared outside its realm or process: a `process` at the top level, a `thread` outside a process, an `import` inside a realm, process, or class (Ch. 15, Ch. 22, Ch. 23). |
| G002 | A GatOS build's kernel realm declares no entry point (Ch. 4). |
| G003 | A duplicate name: a type, a member, a parameter, an overload signature, a case label, a union variant, a C-name collision, or a reserved `__`-prefixed local (Ch. 5, Ch. 30, Ch. 33). |
| G004 | A type mismatch, in any expression or statement position. |
| G005 | An undefined variable or name — including `self` outside an instance method (Ch. 5). |
| G006 | An undefined method on the receiver's type. |
| G007 | An undefined type, an uninferrable type argument, or `void` used where a value type is required (Ch. 9, Ch. 21). |
| G008 | The wrong number of arguments for the chosen overload, or the wrong binding count in a `match` arm (Ch. 15, Ch. 20). |
| G009 | An argument's type does not convert to the matched parameter's type; also two arguments binding one type parameter to different types (Ch. 21). |
| G010 | A `return` value's type does not match the declared return type, or `return;`/`return v;` used in the wrong kind of function (Ch. 15). |
| G011 | `new` applied to something that is not a class — a module, a primitive, a union, an enum, or a class not in scope. The message names the right move for each (Ch. 26). |
| G012 | Indexing something with no `operator []`, no array type, and no pointer type (Ch. 26). |
| G013 | An instance member reached through the type name (Ch. 17). |
| G014 | A static member reached through an instance (Ch. 17). |
| G015 | An ambiguous overload: two candidates tie on conversion cost (Ch. 15). |
| G016 | No overload matches the argument types (Ch. 15). |
| G017 | `@intrinsic(role)` names an unknown role, or `@builtin(name)` an unknown slot (Ch. 32). |
| G018 | That role or slot is already bound by another declaration (Ch. 32). |
| G019 | A required intrinsic is not bound anywhere in the build — in practice, a program declaring a class without `libgata`'s `Runtime` and `Mem` (Ch. 32). |
| G020 | The environment preamble provides no definition of a floor symbol the program needs (Ch. 34). |
| G021 | A throwing call outside `try`, outside a `throws` function, and without a `catch` handler — or one nested inside a larger expression. Also `throw` outside either, and `catch` on a call that cannot fail (Ch. 29). |
| G022 | `break` or `continue` outside a loop (Ch. 25). |
| G023 | *(warning)* A local is declared and never read. Prefix the name with `_` to opt out (Ch. 5). |
| G024 | *(warning)* A statement can never execute — for instance, after an unconditional `return`. |
| G025 | *(warning)* An `if`/`else`/`while`/`for` body is empty (Ch. 25). |
| G026 | *(warning)* A redundant trailing `return;` at the end of a `void` function (Ch. 15). |
| G027 | A non-`void` function has a path that falls off the end without returning. A `return` inside an embedded `native { }` statement does not count (Ch. 15). |
| G028 | An invalid cast: between incompatible types, out of a class to a primitive, or to/from `void` (Ch. 28). |
| G029 | A condition is not `bool` — in `if`, `while`, or a ternary. There is no truthiness (Ch. 25, Ch. 26). |
| G030 | A direct call to, or the address of, an `entry` function. Only the boot sequence or the scheduler may invoke one (Ch. 23). |
| G031 | `panic` used outside the kernel realm (Ch. 25). |
| G032 | `for x in expr` where `expr` is neither a fixed array nor a class with both `Length()` and `Get(int)`. The message names which half is missing (Ch. 25). |
| G033 | A pointer operation — dereference, arithmetic, address-of, cast, index, `++`/`--` — or an ARC intrinsic call, outside an `unsafe` block (Ch. 10, Ch. 25). |
| G034 | An assignment target, `ref` argument, or `++`/`--` operand is not an lvalue (Ch. 25, Ch. 26). |
| G035 | A private class or module member accessed from outside its declaring type (Ch. 16). |
| G036 | `debug` or `panic` used in a Release build (Ch. 25). |
| G037 | A `ref` mismatch: `ref` at the call site but not the declaration or vice versa, an inexact argument type, or `ref` in an indirect call (Ch. 26). |
| G038 | `expr[i] = v` where the type has no `operator []=`, or a compound assignment through an index where only a setter exists (Ch. 26, Ch. 27). |
| G039 | A `match` on a union is missing a `case` for some variant and has no `default`. The message names the missing variants (Ch. 20). |
| G040 | `static` on a free function (Ch. 16). |
| G041 | An annotation attached to a kind of declaration it cannot apply to (Ch. 32). |
| G042 | `@preamble(x)` where `x` is not `boot`, `kernel`, or `user` (Ch. 32). |
| G043 | `foreground` or `background` on a thread. Only a process has a mode (Ch. 23). |
| G044 | The general parse error: any syntax problem with no more specific code below. |
| G045 | Assignment used where an expression is required, such as `if (x = 1)`. Assignment is a statement in Gata (Ch. 25). |
| G046 | An unterminated literal, block comment, `native { }` block, or `{` inside an interpolated string; also an empty or multi-character char literal (Ch. 5, Ch. 6). |
| G047 | An unrecognised escape sequence in a string, char, or interpolated literal (Ch. 6). |
| G048 | A bad or unknown annotation: an unknown `@word`, a missing parenthesised argument, or an annotation on an import, field, operator, thread, process, realm, process variable, enum, or union (Ch. 32). |
| G049 | A malformed numeric literal: `0x` with no digits, or an invalid character or suffix (Ch. 6). |
| G050 | A statement that reads like a declaration with its `let` missing (Ch. 25). |
| G051 | Invalid nesting: a class in a class, a realm in a realm, a process in a process, or a thread in a thread (Ch. 17, Ch. 22, Ch. 23). |
| G052 | A trailing comma after the last enum member or union variant (Ch. 19, Ch. 20). |
| G053 | A bad declaration header: a return type written after the parameter list, `static` on an operator or a field, `public` on a free function or a type declaration, `entry` on a method, an enum or union with no members, a thread body that is not exactly one `entry func`, a generic parameter that is not a plain name (Ch. 15, Ch. 16, Ch. 23). |
| G054 | Type inference has nothing to work with: `let x;`, `let x = null;`, a `void`-typed initializer, a computed field initializer with no explicit type, or an unresolvable generic-union instantiation (Ch. 14, Ch. 17, Ch. 20). |
| G055 | A `realm kernel` block in a Hosted build (Ch. 4, Ch. 34). |
| G056 | A Hosted build with no `realm userspace` at all (Ch. 4). |
| G057 | *(warning)* A file-local `private` free function displaces an imported one of the same name. Silenced with `@shadows` (Ch. 16). |
| G058 | A Hosted build's userspace realm declares no `entry func` (Ch. 4). |
| G059 | The realm declares more than one `entry func` (Ch. 4). |
| G060 | A `process` declaration is missing its mode, or writes the mode after the name instead of before `process` (Ch. 23). |
| G061 | A bad entry signature: parameters, a return type, or `throws` on an `entry func` or a thread entry (Ch. 23). |
| G062 | A `defer` body transfers control — `return`, `break`, `continue`, `throw`, or `assign` — or nests another `defer` (Ch. 25). |
| G063 | A module declares a field. Modules are stateless; use a class for instance state (Ch. 18). |
| G064 | `@environment` inside a realm block (Ch. 15). |
| G065 | Conflicting or duplicated modifiers — a repeat, or `public private` together (Ch. 16). |
| G066 | A `throws` function returning a pointer, a fixed array, or a function pointer (Ch. 29). |
| G067 | `_init` or `_deinit` declared `throws` (Ch. 17). |
| G068 | An `entry func` outside a realm block, inside a process body, or inside `realm userspace` in a GatOS build (Ch. 4, Ch. 23). |
| G069 | An ambiguous call across files, between a generic function and an equally plausible candidate elsewhere. The message spells out each candidate and the qualification to use (Ch. 21, Ch. 31). |
| G070 | *(warning)* A `let` shadows a name in an enclosing scope, or shadows a process variable. Redeclaring in the *same* scope is `G003` (Ch. 24, Ch. 25). |
| G071 | *(warning)* A self-assignment: the target and the value denote the same storage. It compiles and does nothing (Ch. 25). |
| G072 | *(warning)* An expression statement with no effect — a pure value computed and discarded, including `a == b;` where `a = b;` was meant. A call is never treated as pure (Ch. 25). |
| G073 | *(warning)* A constant `if` or ternary condition. Loop conditions are exempt: `while (true)` and `for (;;)` are idiomatic (Ch. 25). |
| G074 | *(warning)* A cast to the type the value already has. A cast on a *literal* is exempt, since it pins that literal's width deliberately (Ch. 28). |
| G075 | Integer `/` or `%` by a literal zero, which traps at runtime on every target. Float division is defined and not reported (Ch. 28). |
| G076 | *(warning)* A parameter the body never reads. Prefix the name with `_` to opt out; `native` bodies are exempt, since raw C may reference anything by name (Ch. 5). |
| G077 | *(warning)* A `default` arm on a `match` whose cases already cover every variant. Dropping it makes a newly added variant a `G039` error instead of a silent fall-through (Ch. 20). |
| G078 | *(warning)* A comparison whose two sides denote the same storage, making the result constant. Reported in loop conditions too (Ch. 25). |
| G079 | A literal `<<` or `>>` count that is negative, or at least as wide as the left operand's type — undefined behaviour in the emitted C. The bound follows the operand's own width (Ch. 28). |
| G080 | *(warning)* A plain string literal containing `{name}` where `name` is a variable in scope — the signature of a dropped `$`. Only fires when the name resolves (Ch. 7). |
| G081 | `assign` outside a `catch` handler attached to a declaration or assignment — including inside a `try` block, a plain `catch { }`, or a handler on a call whose value is discarded (Ch. 29). |
| G082 | A `catch` handler on a declaration has a path reaching its end without an `assign` and without leaving through `return`, `throw`, `break`, or `continue` (Ch. 29). |
| G083 | *(warning)* A union comparison that compares a payload by identity rather than by value, because that payload's class declares no `==`. Reported at the comparison site (Ch. 20). |
| G084 | *(warning)* A union comparison whose payload is `float` or `double`, and so is compared with floating-point `==` (Ch. 20). |
| G085 | `kernel` written without `realm` (Ch. 22). |
| G086 | `realm` followed by anything but `kernel` or `userspace`, with a "did you mean" hint (Ch. 22). |
| G087 | A name that exists, but only inside a realm or process this code is not in. The message names the scope (Ch. 30). |
| G088 | An unmarked shadow, or `@shadows` that displaces nothing, or `@shadows` on a declaration that holds no scope slot (Ch. 30). |
| G089 | A scope qualifier naming a sibling realm or process, a scope this code is not inside, or used outside any realm or process (Ch. 30). |
| G090 | A scope qualifier naming a scope that declares no such name — including a process name used as a value (Ch. 30). |
| G091 | A `process` declaring no threads. It would be created at boot, never run, and never be reclaimed (Ch. 23). |
| G092 | *(warning)* A partial relational operator set — `<` declared without `>`, or any other half of a pair. Relational operators never derive from one another (Ch. 27). |
| G093 | *(warning)* An `unsafe` block builds a managed value it never releases. Silent when the block names `retain`/`release`, which is hand-managed counting (Ch. 35). |
| G094 | *(warning)* A fixed array of a managed element type leaks its contents at scope exit. Stores into one are counted, so it leaks but never dangles (Ch. 11). |
| G095 | `/`, `%`, `<`, `<=`, `>` or `>=` mixing a signed operand with an unsigned one where the conversion would change the answer. The hint names which side to cast (Ch. 28). |
| G096 | *(warning)* `+` on two `char` values, which adds their codepoints rather than joining them into text (Ch. 28). |
| G097 | Explicit type arguments on a call, `f[T](x)`. A function is not a generic type; its parameters are inferred (Ch. 21). |
| G098 | A read before assignment: a primitive local read before any store to it can have happened, or a process variable's initializer reading itself or one declared below it (Ch. 24, Ch. 25). |
| G099 | A discarded `retain`. It returns the reference it counted rather than marking an object in place, so as a statement it counts a temporary the same scope releases again. Store what it returns (Ch. 35). |
| G100 | A process variable with no type or no initial value, or a `catch` handler on one that ends in `return` (Ch. 24). |
| G101 | *(warning)* A reference cycle: classes whose managed fields reach one another in a loop, or a class holding a reference to itself. Break it with a raw pointer field inside `unsafe`, or restructure so ownership runs one way (Ch. 35). |

## 40. Grammar Summary

The whole language, as productions.

**Top level**

```text
program        := toplevel*

toplevel       := import | environment | nativeblock | nativetype | externdecl
                | enumdecl | uniondecl | classdecl | moduledecl | funcdecl
                | realmdecl

import         := 'import' ( ident | strlit ) ';'
environment    := '@environment'
nativeblock    := preamble? 'native' '{' rawC '}'
nativetype     := ann* 'native' 'type' ident '{' rawC '}'
externdecl     := ann* '@extern' type? 'func' ident '(' params ')' ';'
```

**Type declarations**

```text
enumdecl       := 'enum' ident '{' [ enummember (',' enummember)* ] '}'
enummember     := ident [ '=' constexpr ]

uniondecl      := ann* 'union' ident generics? '{' [ variant (',' variant)* ] '}'
variant        := ident [ '(' param (',' param)* ')' ]

classdecl      := ann* 'class' ident generics? '{' member* '}'
moduledecl     := ann* 'module' ident '{' member* '}'
member         := fieldsblock | fielddecl | methoddecl | operatordecl
fieldsblock    := 'fields' '{' rawC '}'
fielddecl      := mods? ( type ident | ident ) [ '=' expr ] ';'
methoddecl     := ann* mods? 'entry'? 'throws'? type? 'func' ident generics?
                  '(' params ')' body
operatordecl   := mods? 'operator' type? 'func' opsym '(' params ')' body
opsym          := '+' | '-' | '*' | '/' | '%' | '<' | '>' | '==' | '!='
                | '<=' | '>=' | '&' | '|' | '^' | '<<' | '>>' | '!' | '~'
                | '++' | '--' | '[' ']' | '[' ']' '=' | 'as'

funcdecl       := ann* mods? 'entry'? 'throws'? type? 'func' ident generics?
                  '(' params ')' body
body           := block | 'native' '{' rawC '}'
```

**Topology**

```text
realmdecl      := 'realm' ( 'kernel' | 'userspace' ) '{' realmitem* '}'
realmitem      := toplevel-minus-import-minus-realm | processdecl
processdecl    := ( 'foreground' | 'background' ) 'process' ident
                  '{' ( threaddecl | processitem )* '}'
processitem    := realmitem-minus-process | processvar
processvar     := 'let' type ident '=' expr ';'
threaddecl     := 'thread' ident '{' entryfunc '}'
entryfunc      := 'entry' 'func' ident? '(' ')' block
```

**Shared pieces**

```text
generics       := '[' ident (',' ident)* ']'
params         := [ param (',' param)* ]
param          := 'ref'? type ident
mods           := ( 'static' | 'public' | 'private' )+
ann            := '@intrinsic' '(' ident ')' | '@preamble' '(' ident ')'
                | '@keep' | '@builtin' '(' ident ')' | '@shadows'
```

**Types**

```text
type           := ( '[' intlit ']' )* ( functype | typename ) '*'*
functype       := 'func' '(' [ type (',' type)* ] ')' '->' type
typename       := scopequal? ident ('.' ident)* [ '[' type (',' type)* ']' ]
                | primitive
scopequal      := '::' | 'kernel' '.' | 'userspace' '.'
```

**Statements**

```text
block          := '{' stmt* '}'
stmt           := block | letstmt | assignstmt | exprstmt | ifstmt | whilestmt
                | forstmt | forinstmt | switchstmt | matchstmt | trycatch
                | unsafeblock | deferstmt | returnstmt | 'break' ';'
                | 'continue' ';' | 'throw' ';' | assignvalue | debugstmt
                | panicstmt | nativestmt

letstmt        := 'let' type? ident [ '=' expr ] ';'
assignstmt     := expr assignop expr ';'
assignop       := '=' | '+=' | '-=' | '*=' | '/=' | '%=' | '&=' | '|=' | '^='
                | '<<=' | '>>='
ifstmt         := 'if' '(' expr ')' stmt [ 'else' stmt ]
whilestmt      := 'while' '(' expr ')' stmt
forstmt        := 'for' '(' [ letstmt-nosemi | forclause ] ';' [ expr ] ';'
                  [ forclause ] ')' block
forinstmt      := 'for' ident 'in' expr block
switchstmt     := 'switch' '(' expr ')' '{' ( case | default )* '}'
case           := 'case' expr (',' expr)* block
matchstmt      := 'match' '(' expr ')' '{' ( matchcase | default )* '}'
matchcase      := 'case' ident [ '(' ident (',' ident)* ')' ] block
default        := 'default' block
trycatch       := 'try' block 'catch' block
unsafeblock    := 'unsafe' block
deferstmt      := 'defer' stmt
returnstmt     := 'return' [ expr ] ';'
assignvalue    := 'assign' expr ';'
debugstmt      := 'debug' strlit ';'
panicstmt      := 'panic' strlit ';'
nativestmt     := 'native' '{' rawC '}'
```

**Expressions**

```text
expr           := ternary
ternary        := or [ '?' expr ':' ternary ]
or             := and ( '||' and )*
and            := bitor ( '&&' bitor )*
bitor          := bitxor ( '|' bitxor )*
bitxor         := bitand ( '^' bitand )*
bitand         := equality ( '&' equality )*
equality       := relational ( ( '==' | '!=' ) relational )*
relational     := shift ( ( '<' | '>' | '<=' | '>=' ) shift )*
shift          := additive ( ( '<<' | '>>' ) additive )*
additive       := multiplicative ( ( '+' | '-' ) multiplicative )*
multiplicative := ascast ( ( '*' | '/' | '%' ) ascast )*
ascast         := unary ( 'as' type )*
unary          := ( '!' | '~' | '-' | '&' | '*' ) unary | postfix
postfix        := primary ( '++' | '--' | '.' ident | '[' expr ']'
                          | '(' args ')' | 'catch' block )*
args           := [ arg (',' arg)* ]
arg            := 'ref'? expr
primary        := intlit | floatlit | charlit | strlit | interpstr | boollit
                | 'null' | ident | scopedname | '(' expr ')'
                | '(' primtype ')' unary
                | 'new' type [ '(' args ')' ] [ collectioninit ]
                | 'sizeof' '(' type ')' | 'default' '(' type ')'
                | '[' [ expr (',' expr)* ] ']'
collectioninit := '{' [ expr (',' expr)* ] '}' | '[' [ expr (',' expr)* ] ']'
scopedname     := scopequal ident ('.' ident)*
```

## 41. Appendix: Keywords and Operator Precedence

### Reserved words

These cannot be used as identifiers anywhere:

```
import realm kernel userspace foreground background
class enum module union func static public private entry throws operator as
fields ref return if else while for in switch case break continue
debug panic try catch new let null unsafe throw sizeof default defer match
assign
bool int char float double short void
int64 uint uint64 ushort byte sbyte usize uintptr
true false
```

### Contextual keywords

`process`, `thread`, and `native` carry meaning only in declaration position and remain usable as ordinary identifiers everywhere else (Chapter 5). `self` is not a keyword either — it is a name the compiler binds inside an instance method.

### Annotations

Lexed as one `@word` token each. These seven spellings are the only valid ones; any other `@word` is `G048`:

```
@intrinsic  @preamble  @extern  @environment  @keep  @builtin  @shadows
```

### Names the compiler owns

Two name spaces belong to the compiler.

**The `__` prefix** is reserved for the compiler's own temporaries. Declaring a name that starts with two underscores is `G003` (Chapter 5).

**The `_g` prefix** is reserved for the dense tokens the Densifier hands out. Declaring one is legal — the compiler simply picks a different token.

A handful of symbols the backend emits itself cannot be taken over at all: the process launcher `uapps`, the kernel entry symbol, each thread's entry, and the typedef synthesised for a function-pointer or fixed-array type. A declaration that would be emitted under one of those names is `G003`. Raw C inside a `native { }` block is the one exception — it is emitted verbatim, so defining one of those symbols there is caught by the C compiler rather than by `appa`.

### Operator precedence

Lowest to highest:

| Level | Operators | Associativity |
|---|---|---|
| 1 (lowest) | `?:` | right |
| 2 | `\|\|` | left |
| 3 | `&&` | left |
| 4 | `\|` | left |
| 5 | `^` | left |
| 6 | `&` | left |
| 7 | `==` `!=` | left |
| 8 | `<` `>` `<=` `>=` | left |
| 9 | `<<` `>>` | left |
| 10 | `+` `-` | left |
| 11 | `*` `/` `%` | left |
| 12 | `as` | left |
| 13 | `!` `~` `-` `&` `*` (unary) | right (prefix) |
| 14 (highest) | `++` `--` `.` `[]` `()` `catch` (postfix) | left |

Assignment does not appear: it is a statement (Chapter 25).

`as` sits in an unusual position relative to most C-family languages — looser than the unary prefix operators but tighter than the multiplicative operators — so `-x as int` parses as `(-x) as int` and `x.Field as int` parses as `(x.Field) as int` (Chapter 26).

### The overloadable set

Binary `+` `-` `*` `/` `%` `&` `|` `^` `<<` `>>`; comparisons `==` `!=` `<` `>` `<=` `>=`; unary `!` `~` `-`; postfix `++` `--`; the indexer pair `[]` and `[]=`; and the conversion form `as`.

Not overloadable: `&&`, `||`, assignment, every compound assignment, and the ternary (Chapter 27).

## 42. A Program Using Most of the Language

One program, exercising nearly every feature in this book. Read it as a final review: every construct in it has a chapter behind it.

```go
import Console;
import String;
import List;
import Optional;

// --- an enum ---------------------------------------------------------------
enum Level { Low = 1, Mid, High = Mid * 2 }

// --- a tagged union --------------------------------------------------------
union Reading { Ok(int v), Failed(String why), Absent }

// --- a generic class with operators and lifecycle --------------------------
class Pair[A, B] {
    public A first;
    public B second;

    func _init() { }
    func _deinit() { }

    public A func First() { return self.first; }
    public operator bool func ==(Pair[A, B] o) { return self.first == o.first; }
    public operator bool func !=(Pair[A, B] o) { return self.first != o.first; }
}

// --- a module --------------------------------------------------------------
module Fmt {
    public static String func Describe(Level l) {
        switch (l) {
            case Level.Low  { return "low"; }
            case Level.Mid  { return "mid"; }
            default         { return "high"; }
        }
    }
}

// --- a generic free function (type argument inferred) ----------------------
T func Max[T](T a, T b) { if (a > b) { return a; } return b; }

// --- a throwing function ---------------------------------------------------
throws int func Halve(int n) {
    if (n % 2 != 0) { throw; }
    return n / 2;
}

// --- a file-local helper ---------------------------------------------------
private void func Trace(String s) { Console.PrintLine(s); }

// --- a root-scope name that a realm will deliberately displace -------------
int func Ping() { return 1; }

// --- native interop --------------------------------------------------------
native { static int c_double(int n) { return n * 2; } }
@extern int func c_double(int n);

realm kernel {
    entry func Main() {
        // inference, literals, interpolation
        let int    n     = Max(3, 9);
        let Level  lvl   = Level.High;
        let String label = $"n={n} level={Fmt.Describe(lvl)}";
        Trace(label);

        // an inline catch handler — no new scope
        let int half = Halve(n) catch { assign 0; };

        // a union plus an exhaustive match
        let Reading r = half > 0 ? Reading.Ok(half) : Reading.Absent();
        match (r) {
            case Ok(v)      { Trace($"ok {v}"); }
            case Failed(w)  { Trace(w); }
            case Absent     { Trace("absent"); }
        }

        // generics, a collection initializer, for..in, operator []
        let List[int] xs = new List[int]() { 1, 2, 3 };
        xs << 4;
        for x in xs { Trace($"{x}"); }
        let int third = xs[2];

        // a generic class plus operator ==
        let Pair[int, String] p = new Pair[int, String]();
        p.first = 1;
        if (p == p) { }

        // a fixed array, a cast, an extern call
        let [3]int fixed = [1, 2, 3];
        let int64 wide = fixed[0] as int64;
        let int   dbl  = c_double(n);

        // unsafe plus defer
        unsafe {
            let buf = alloc(64 as usize) as char*;
            defer free(buf);
            buf[0] = 'x';
        }
    }
}

realm userspace {
    @shadows int func Ping() { return 2; }   // displaces the root-scope Ping

    foreground process App {
        let int ticks = 0;                  // a process variable, shared by the threads

        class Job { public int id; }        // a process-scoped type

        thread Worker {
            entry func Run() {
                ticks = ticks + 1;
                let Job j = new Job();
                let int outer = ::Max(1, 2);   // reach past the realm to root
            }
        }
    }

    background process Daemon {
        class Job { public String tag; }    // a different Job entirely
        thread Loop { entry func Run() { } }
    }
}
```

That is the language. Every rule in this book is visible somewhere in those hundred lines: a realm with one entry point, a second realm whose entry points are threads, one process variable shared by a thread group, two `Job` types that do not collide, a deliberate shadow and a qualifier that reaches past it, a failure handled in place without a nested scope, an exhaustive match, a monomorphized generic, and a handful of C at the bottom of it all.

Go build something.



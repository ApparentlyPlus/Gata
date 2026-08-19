# Appa, written in Gata

This folder contains the Gata compiler (Appa), written in Gata. It reads `.g` files, type-checks them,
lowers them, and emits C. It produces the same C the real `appa` emits, byte for byte.

> [!CAUTION]
> This is **not** a replacement for `appa`. You still need the real compiler installed to build anything here, including this. Besides, this is a pinned port of Appa 2.2.0, and **will not be maintained.**
>
> It was merely built as a demonstration, and the rest of this file is me being honest about what it demonstrates and what it doesn't.

## Table of Contents

- [Why](#why)
- [What it proves](#what-it-proves)
- [What it does *not* prove](#what-it-does-not-prove)
- [Building it and watching it eat itself](#building-it-and-watching-it-eat-itself)
- [What's in here](#whats-in-here)
- [Performance](#performance)
- [Known gaps](#known-gaps)

## Why

Gata was designed for one job: writing an operating system that boots on bare metal. Every feature
in it had to survive the question *"can this run at boot, on a machine with no OS underneath it?"*
That question shaped everything — no GC, no exceptions, no hidden allocation, no virtual dispatch.

A compiler is the opposite of that. It is a long-running batch program that allocates constantly,
builds enormous recursive data structures, keeps half of them alive for the entire run, and does
essentially nothing a kernel does. It wants hash maps and string builders and deep trees. It is,
more or less, the least kernel-shaped program I could think of.

So I wrote one in Gata. Not because anyone needs a second `appa`, but because if a language built
exclusively for kernels can also be pushed through *that*, it says something about how the language
is put together. And if it couldn't, I wanted to know which part gave out first.

Also I wanted to know whether it would be fast. It is. Sort of. There's a whole document about that.

## What it proves

**That the language is modular enough for this to even be on the table.** Nothing in Gata is
special-cased for kernels. `realm kernel` and `realm userspace` are the *only* places the language
knows what a kernel is, and a Hosted build simply doesn't use one. Everything else — generics,
unions, ARC, operator overloading, the `throws`/`catch` model — is target-agnostic because it was
built that way, not because I retrofitted it. The port never once needed a language change. Not one.
The only thing I added to the whole toolchain while writing it was an `isatty` bind in the
environment file, which is a data file, which is the entire point of the environment file.

**That it survives the most adversarial input I could hand it.** ~32,000 lines. 40 files. A 5 MB
single-translation-unit C output. Recursive tagged unions with managed payloads nested six deep.
Generic containers instantiated dozens of ways. A symbol table that lives for the whole run. If
there were a soundness hole in monomorphization, or a leak in the ARC insertion, or an ordering bug
in the lowering passes, a program this size would find it. It did find several — all of them in the
port, none in the language.

**That it takes a comparable amount of code.** The C# original is 23,770 lines; the Gata port is
32,053. That's 1.35×, and most of the difference is things C# gets from a standard library that
Gata doesn't have yet (LINQ, `Dictionary` iteration order, `XDocument`, SHA-256, `System.Random`)
plus the fact that Gata has no closures, so every lambda became a named function. It is not 3×. It
is not "you'd never write a real program in this."

**That it does what it says on the tin.** You get control C doesn't give you — exhaustive `match`
that fails to compile when you add a union variant, ARC that inserts every release on every path
including `throw`, generics that monomorphize with no boxing, a reference-cycle warning computed
with Tarjan's SCC — and you pay C's price for it, because it *is* C by the time GCC sees it. The
emitted C does the actual compilation work in **24% fewer instructions** than the same compiler
published as .NET NativeAOT. The abstractions aren't costing you anything. The memory model is (see
[Benchmark.md](Benchmark.md)), but that's a different sentence.

## What it does *not* prove

Let me get ahead of some things.

**That Gata is a general-purpose language.** It isn't, and I'm not claiming it is. It has no
closures, no interfaces, no inheritance, no reflection, no async, no package manager, no varargs, no
default arguments. Writing this compiler in it was frequently annoying in ways that would be
unacceptable for a language competing for general use. A compiler happens to be a domain that
tolerates those absences well — it's mostly data structures and pattern matching, which Gata is
genuinely good at. Pick a different domain and the missing pieces would bite much harder.

**That Gata is fast because it transpiles to C.** This is the one I expect people to get wrong.
"Transpiles to C" is not a performance claim. You can emit terrible C. What the benchmark actually
shows is that the *generated code* is good — and that the shipping self-hosted compiler is still
**1.37× slower** than the .NET version, because reference counting costs 104 million operations per
run and a tracing GC amortises that work far better. Transpiling to C bought a good instruction
stream. It did not buy a free lunch. Different program, different answer.

**That it's production ready.** It is not. It cannot `appa install`, `appa new`, or `appa run`,
because those need process spawning and HTTPS and the environment floor binds neither. It leaks in
one measurement configuration on purpose. It has had approximately one user, who wrote it.

**That self-hosting means the language is finished.** Self-hosting is a milestone, not a
certificate. It means one large program works. Rust self-hosted long before it was pleasant to use.

**That any of this is a good idea.** See the root README, section "Are you crazy?"

## Building it and watching it eat itself

You need the real `appa` installed and a C compiler. From this folder:

```sh
# 1. Build the port with the installed appa. This emits C into transpilation/.
appa build

# 2. Compile that C. It's one big translation unit; -O2 is plenty, -O0 works and is 3x slower.
#    It goes one folder up so it doesn't sit inside the project it's about to compile.
cc -O2 -o ../appa-selfhost transpilation/program.c

# 3. Now use the compiler you just built to compile its own source. Still from this folder,
#    because that's where the .gconf is.
rm -rf transpilation
../appa-selfhost build
```

That last command is the whole point. A compiler written in Gata, compiled by a compiler written in
C#, reading the Gata source of itself and emitting the C for itself. It takes about half a second.

If you want to confirm it actually did the job rather than merely appearing to:

```sh
rm -rf transpilation && appa build             && md5sum transpilation/*
rm -rf transpilation && ../appa-selfhost build && md5sum transpilation/*
```

The hashes match. Not "the same warnings", not "close enough" — the same bytes, decorative header
comments included, which meant reproducing .NET's seeded `System.Random` and a SHA-256 exactly. You
can go further and compile *that* output into an `appa-selfhost-2` and check it against the first
one; it's a fixpoint, so it stops changing.

`../appa-selfhost --help` lists every command the real compiler has. The ones it can't carry out say
so and tell you why.

## What's in here

| Path | What it is |
|------|-----------|
| `src/` | The compiler. Mirrors `Appa/src/` file for file — `Syntax/`, `Semantics/`, `Lowering/`, `Backend/`, `CLI/`. |
| `selfhostlib/` | A local copy of libgata plus what the port needed on top: `Paths.g`, `Sha256.g`, `NetRandom.g`, `File.g`, `Dir.g`, `Args.g`. |
| `env.selfhost.g` | The environment. Cross-platform C floor — POSIX and Win32, no external libraries. |
| `selfhost.gconf` | Hosted target. It builds an executable, not an ISO. |
| `Benchmark.md` | Why it performs the way it does, measured rather than guessed. |

There are no tests in here and no test flag. The self-compile *is* the test, and a better one than
anything I'd have written by hand: it runs every pass over 32,000 lines and compares 5 MB of emitted
C against a reference implementation byte for byte. A pass that silently dropped a node would change
that output. A hand-written assertion suite would not have caught half of what this does.

## Performance

Short version: the shipping build is **1.37× slower** than appa-in-.NET, entirely because of
reference counting, and with ARC removed plus an arena on huge pages it is **1.82× faster**.

The interesting part is that both compilers spend about the same fraction of their time on memory
management — roughly 45% each. The difference is *how the bill is paid*: .NET pays in a few dozen
bulk collections, ARC pays 104 million separate times, at 15.25 refcount operations per allocated
object. A compiler is close to the worst case for that ratio.

[Benchmark.md](Benchmark.md) has the full thing: the instruction-level ablation, the profiles, why
a bump arena on its own is a *pessimisation* until you add one `madvise` call, and what I'd do about
it.

## Known gaps

- **`appa install`, `appa update`, `appa new`, `appa run`, and GatOS image builds** are accepted as
  commands and refuse with an explanation. They need HTTPS, zip extraction, and process spawning;
  the floor binds none of those yet. Everything on the transpile path works.
- **`WarnReferenceCycles` (G101) is not ported.** It's a warning, and porting it would have meant
  approximating where C# points the diagnostic. I'd rather it be absent than wrong. The real `appa`
  still reports it, including over this port's own source.
- **The port has found real bugs in itself** and will probably find more. Every one so far surfaced
  as a byte difference against the C# output, which is exactly the property this folder exists to
  have.

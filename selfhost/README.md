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
- [For the love of the game](#for-the-love-of-the-game)
- [Known gaps](#known-gaps)

## Why

Gata was designed for one job: writing an operating system that boots on bare metal. Every feature in it had to survive the question *"can this run at boot, on a machine with no OS underneath it?"* That question shaped every decision: no GC, no exceptions, no hidden allocation, no virtual dispatch.

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
knows what a kernel is, and a Hosted build simply doesn't use one. Everything else, including generics,
unions, ARC, operator overloading, the `throws`/`catch` model, is target-agnostic because it was
built that way, not because I retrofitted it. The port never once needed a language change. Not one.
The only thing I added to the whole toolchain while writing it was an `isatty` bind in the
environment file, which is a data file, which is the entire point of the environment file.

**That it survives the most adversarial input I could hand it.** ~32,000 lines. 40 files. A 5 MB
single-translation-unit C output. Recursive tagged unions with managed payloads nested six deep.
Generic containers instantiated dozens of ways. A symbol table that lives for the whole run. If
there were a soundness hole in monomorphization, or a leak in the ARC insertion, or an ordering bug
in the lowering passes, a program this size would find it. It did find several, but all of them were in the
port, and none were in the language.

**That it takes a comparable amount of code.** The C# original is 23,770 lines. The Gata port is
32,053. That's 1.35×, and most of the difference is things C# gets from a standard library that
Gata doesn't have yet (LINQ, `Dictionary` iteration order, `XDocument`, SHA-256, `System.Random`)
plus the fact that Gata has no closures, so every lambda became a named function. It is not 3×. It
is not "you'd never write a real program in this."

**That it does what it says on the tin.** You get control C doesn't give you. Exhaustive `match`
that fails to compile when you add a union variant, ARC that inserts every release on every path
including `throw`, generics that monomorphize with no boxing, a reference-cycle warning computed
with Tarjan's SCC. You pay C's price for it, because it *is* C by the time GCC sees it. The
emitted C does the actual compilation work in **24% fewer instructions** than the same compiler
published as .NET NativeAOT. The abstractions aren't costing you anything. The memory model is (see
[Benchmark.md](Benchmark.md)), but that's a different sentence.

## What it does *not* prove

Let me get ahead of some things.

**That Gata is a general-purpose language.** It isn't, and I'm not claiming it is. It has no
closures, no interfaces, no inheritance, no reflection, no async, no package manager, no varargs, no
default arguments. Writing this compiler in it was frequently annoying in ways that would be
unacceptable for a language competing for general use. A compiler happens to be a domain that
tolerates those absences well since it's mostly data structures and pattern matching, which Gata is
genuinely good at. Pick a different domain and the missing pieces would bite much harder.

**That Gata is fast because it transpiles to C.** This is the one I expect people to get wrong.
"Transpiles to C" is not a performance claim. You can emit terrible C. What the benchmark actually
shows is that the *generated code* is good, and that the shipping self-hosted compiler is still
**1.37× slower** than the .NET version, because reference counting costs 104 million operations per
run and a tracing GC amortises that work far better. Transpiling to C bought a good instruction
stream. It did not buy a free lunch. Different program, different answer.

**That it's production ready.** It is not. It has no `appa install`, `appa new`, or `appa run`,
because those need process spawning and HTTPS and the environment floor binds neither. It leaks in
one measurement configuration on purpose. It has had approximately one user, who wrote it.

**That self-hosting means the language is finished.** Self-hosting is a milestone, not a
certificate. It means one large program works. Rust self-hosted long before it was pleasant to use.

**That any of this is a good idea.** See the root README, section "Are you crazy?"

## Building it and watching it eat itself

You need the real `appa` installed and a C compiler. From this folder:

```sh
# Build the port with the installed appa. This emits C into transpilation/.
appa build

# Compile that C. It's one big translation unit, -O3 is ideal, -O0 works and is 3x slower.
# It goes one folder up so it doesn't sit inside the project it's about to compile.
cc -O2 -o ../appa-selfhost transpilation/program.c

# Now use the compiler you just built to compile its own source. Still from this folder, because that's where the .gconf is.
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

The hashes match. Not "the same warnings", not "close enough". The same bytes, decorative header
comments included, which meant reproducing .NET's seeded `System.Random` and a SHA-256 exactly. You
can go further and compile *that* output into an `appa-selfhost-2` and check it against the first
one. It's a fixpoint, so it stops changing.

`../appa-selfhost --help` lists every command the real compiler has. The ones it can't carry out say
so and tell you why.

## What's in here

| Path | What it is |
|------|-----------|
| `src/` | The compiler. Mirrors `Appa/src/` file for file: `Syntax/`, `Semantics/`, `Lowering/`, `Backend/`, `CLI/`. |
| `selfhostlib/` | A local copy of libgata plus what the port needed on top: `Paths.g`, `Sha256.g`, `NetRandom.g`, `File.g`, `Dir.g`, `Args.g`. |
| `env.selfhost.g` | The environment. Cross-platform C floor, POSIX and Win32, no external libraries. |
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
management (roughly 45% each). The difference is *how the bill is paid*: .NET pays in a few dozen
bulk collections, ARC pays 104 million separate times, at 15.25 refcount operations per allocated
object. A compiler is close to the worst case for that ratio.

[Benchmark.md](Benchmark.md) has the full thing: the instruction-level ablation, the profiles, why
a bump arena on its own is a *pessimisation* until you add one `madvise` call, and what I'd do about
it.

## For the love of the game

None of what follows is useful. That is rather the point.

### A language older than most of the people reading this

Gata does not have a code generator. It has a translator, and what it translates into is C.

That decision was made for boring reasons. C is what a kernel wants to link against, and writing a
register allocator was never the interesting part of this project. But it has a consequence nobody
designs for and everybody inherits, which is that **C got everywhere first**. It was released in
1972. It is older than the PC, older than the internet as anyone uses it, older than most of the
people who will read this file. Every strange machine that has ever been built has, sooner or
later, had someone write a C compiler for it, because that was how you made the machine useful.

So appa does not port to anything. It arrives. Point the transpiler at a project, take the C out of
`transpilation/`, and hand it to whatever compiler that machine has - and the question stops being
"has anyone made Gata run here" and becomes "did anyone, at any point in the last fifty years, care
enough about this box to write a C compiler for it". Usually somebody did.

What follows is what happened when I actually tried it.

### It runs on MS-DOS

Not "could be made to". It was built, it booted, it compiled Gata, in DOSBox.

The pipeline is the ordinary one right up until the last step. The C# `appa` transpiles `selfhost/`
into one C translation unit, `transpilation/program.c` plus `transpilation/shared.h`. Then, instead
of the host `cc`:

```sh
i586-pc-msdosdjgpp-gcc -O2 -march=i386 -mtune=i486 -std=gnu99 \
  -o appa.exe transpilation/program.c
```

That is **DJGPP**, meaning GCC 12.2 configured for `i586-pc-msdosdjgpp`, with DJGPP's own `libc.a`
underneath it - and the output is `appa.exe`, a 32-bit protected-mode DOS executable. Put it on the DOS
filesystem next to `CWSDPMI.EXE`, and:

```
C:\> appa.exe --help
C:\> appa.exe check myproj
C:\> appa.exe build myproj
```

There is a real pleasure in that prompt :)

**CWSDPMI** is a necessary piece, and it is a lovely thing to still be depending on. MS-DOS is
a 16-bit real-mode operating system with a 640 KB ceiling, and no compiler for a language like this
was ever going to fit in 640 KB. So in the early nineties a whole subculture built its way out:
DPMI hosts, DOS extenders, the machinery that flips the CPU into 32-bit protected mode on the way
into `main()` and hands the program a flat address space with paging behind it. Charles W. Sandmann
wrote CWSDPMI so that people could have 32 bits on a 16-bit operating system, and thirty years
later it is what lets a compiler from the 2020s swap its 100 MB working set onto a disk that
thinks it is 1994.

Because DPMI does the work, the binary is not fussy about which DOS is underneath. **MS-DOS 5.0**
through **6.22** (the last standalone retail release, and the one most people mean when they say
MS-DOS) and the DOSes buried under Windows 95, 98 and Me. **FreeDOS**. **IBM PC DOS**. **DR-DOS**
and **OpenDOS**. Any 80386 or later. Either CWSDPMI supplies the DPMI host or something already
there does: `EMM386`, `QEMM386`, `JEMMEX`, names that were once arguments people had.

None of this required Gata to be clever. It required Gata to not be greedy:

- **Nothing to install first.** No CLR, no JVM, no bytecode interpreter, no LLVM. The C *is* the
  program.
- **No garbage collector.** Memory is compile-time ARC over `malloc`/`free`. There is no collector
  thread to schedule on an operating system that has no threads, and no pause to absorb.
- **No JIT, no dynamic loading, nothing position-independent.**
- **A floor that is a 1989 C library.** `fopen`/`fread`/`fwrite`/`fseek`,
  `malloc`/`realloc`/`free`, `opendir`/`stat`, a clock, and stdout. That is the whole of it.

### Learning, in 2026, why DOS text is grey

The one part that took real work was colour, and it turned out to be the most enjoyable thing in
this entire folder.

Appa colours its output. That used to mean ANSI escapes stapled into the strings, which is fine on
a terminal and gibberish on a console that has never heard of VT100. So colour became a marker
carried inside the string, turned into a `SetColor` call at the floor - which meant the compiler's
own source stopped containing a single escape byte, and every question about how a colour is
actually *spelled* moved into one file. Windows XP gets the console API. A terminal gets SGR.
Redirect it anywhere and you get clean text, which is the property that matters most: a captured
log is the same bytes the screen showed, minus the colour it could not record.

Then DOS, where it turns out colour cannot be a property of the bytes at all.

Everywhere else the attribute travels with the text. DOS does neither trick. stdout goes through
INT 21h and comes out at BIOS teletype output, which in text mode draws your character using the
attribute **already sitting in that cell** and ignores anything you set. That is why DOS output is
grey on black no matter what you ask for. It is also why `textattr()` on its own does nothing at
all: it sets the attribute that conio's *own* output functions use, so the text has to travel
through conio for the colour to ever reach it.

So on DOS the floor stops calling `fwrite` and starts calling `putch`, one byte at a time, into
video memory. There is something genuinely funny about writing that in 2026 - and about the
carriage return I put before every newline, because Borland's `putch` treated `\n` as a bare line
feed, DJGPP's is not obliged to agree, and forty years on the safest thing is still to emit both
and let the console decide.

And then the reward: `SetColor` takes sixteen palette indices, and the VGA text attribute byte *is*
sixteen palette indices - the foreground in the low nibble, the background in the high one. The
mapping is the identity. The API designed so a kernel could implement it in two instructions and the
byte an IBM PC text console has used since 1981 turn out to be the same thing. No `ANSI.SYS`, no
escape bytes, nothing to configure.

Four small `#ifdef __DJGPP__` arms, all in `env.selfhost.g`. The compiler's own source has no idea
DOS exists.

While I was there, every glyph appa prints became ASCII - the check mark is `+`, the arrow is `->`,
the spinner is `*`, and the bison and wordmark are drawn in `:`, `-`, `=` and `$`. Code page 437 has
nothing left to guess at. The one deliberate exception is the box-drawing banner `Finesse.g` writes
into the *generated* C, because that is emitted output rather than terminal output, and changing it
would break the byte-for-byte match with the C# compiler that this folder exists to demonstrate.

Two things still stand between this and a real MS-DOS install rather than DOSBox, and both are
filesystem rather than compiler. `SymbolCollector.g` has a 15-character stem, and `selfhost.gconf`
has a five-character extension. Neither can exist on FAT16 without a long-filename driver, and
manifest discovery searches for `.gconf` - so it would not find the file DOS had just truncated to
`SELFHOST.GCO`. Under DOSBox-X or Windows 9x LFN it is a non-issue. On a real 6.22 install it is two
small changes nobody has made.

### How far back could this plausibly go?

Once DOS works, the daydream is unavoidable: how far back does this go? So I measured instead of
guessing, and the answer is more interesting than a number.

Three things bound it.

**Memory.** An ordinary project, say, a `main.g` and the standard library it pulls in, 3,348 lines of C
out, peaks at **5.0 MB**. The compiler compiling *itself*, 66 files and 146,242 lines of C out,
peaks at **100 MB**. Those are two completely different machines. 5 MB is a well-appointed
VAX-11/780. 100 MB is not any machine of that era at all. **Running appa and self-hosting appa are
separate ambitions, and only the first one is retro-plausible.**

**Sixty-four-bit integers.** `int64_t` appears 248 times in the emitted C, and it is load-bearing
rather than incidental: SHA-256 for the content seed, and the millisecond clock. Both feed the
byte-identical output, so neither can be quietly dropped. K&R C has no 64-bit type at all.

**The dialect.** The emitter writes ANSI prototypes and `void*`, which no pre-ANSI `pcc` can read -
and that rules out stock 4.3BSD, SunOS 4, and everything on the 1979 UNIX/32V side of the line
without further argument. Worse, appa's own runtime prelude declares loop variables inside `for`
statements in exactly five places, so even `-std=gnu89` refuses it. It wants a C99 front end.

Put together, the boundary lands somewhere I did not expect. **The machine can be from 1977**: a
VAX-11/780 has a 32-bit flat address space, and a 5 MB working set fits inside the 8 MB one could be
loaded with. **The compiler cannot be from before about 2001**, which is where GCC 3.0 and a C99
front end arrive. Everything earlier fails on the toolchain, not on the hardware.

Which is a strange and rather wonderful place to end up. The oldest thing you could plausibly point
this at is a minicomputer from 1977, being fed C by a cross-compiler built twenty-four years after
it shipped. The machine is not the limit. Nobody's *machine* is the limit any more. The limit is
which compiler you can get onto it.

Below the VAX it stops being a toolchain problem and becomes physics: an 8086 has no flat 32-bit
address space and a PDP-11 has 64 KB of one, and no amount of stubbing gets a 5 MB working set into
either. But the near side of that line is a decent list - anything with a flat 32-bit address
space, 4 MB of RAM, and a GCC that targets it. VAX under NetBSD. 68020. i386. Early SPARC.

I have not tried any of them. If someone is mad enough to do it, please message me.

### The floor, and what it does not do

The reason all of this stays cheap is that `env.selfhost.g` is bare on purpose, and bare
unconditionally - there is no switch to set and no configuration to get wrong.

Six of its bindings are stubs, and they are stubs because a compiler provably never calls them.
`Console.Clear`, `Console.Home`, `Console.Goto` and `Console.ShowCursor` have zero call sites in
`src/`: appa prints lines from the top and stops. `Console.InputLine` has zero, because a compiler
takes its input as paths on argv. `Sys.Yield` and `Sys.Sleep` have zero, because a transpile-only
appa is single-threaded and does all its work inline.

Stubbing them is not housekeeping - it is what removes the dependencies. Out goes `<sched.h>`,
which no 4BSD-era host has. Out goes `nanosleep`, which arrived with POSIX.1b in 1993. What is left
asks its host for four things: stdio, malloc, `opendir`/`stat`, and a clock.

Everything else is detected rather than configured. The fixed-width types come from `<stdint.h>`
where the compiler admits to having one and from hand-written typedefs off `<limits.h>` where it
does not. The window size comes from `TIOCGWINSZ` where that exists and from a fixed 80x24 where it
does not. The clock prefers `clock_gettime`, then `QueryPerformanceCounter`, then C89's `clock()`.
And the one screen effect appa actually uses - redrawing the progress line in place - is built from
a carriage return and a run of spaces rather than an erase-to-end-of-line escape, because spaces are
the one thing every console since the teletype has drawn the same way.

Through all of it the emitted bytes never changed. That was the only thing worth checking, and it
holds.

## Known gaps

- **`appa install`, `appa update`, `appa new` and `appa run` do not exist here**, and neither do
  their options (`--with-path`, `--no-path`, `--force`, `headless`, `timeout=`). They need HTTPS,
  zip extraction, and process spawning; the floor binds none of those yet, so rather than accept a
  command that could only ever refuse itself, the CLI simply does not offer it. Everything on the
  transpile path works. A **GatOS image build** is the one exception that is still detected: a
  `.gconf` can declare `<TargetBackend>GatOS</TargetBackend>`, and that build stops with an
  explanation instead of quietly emitting something else.
- **`WarnReferenceCycles` (G101) is not ported.** It's a warning, and porting it would have meant
  approximating where C# points the diagnostic. I'd rather it be absent than wrong. The real `appa`
  still reports it, including over this port's own source.
- **The port has found real bugs in itself** and will probably find more. Every one so far surfaced
  as a byte difference against the C# output, which is exactly the property this folder exists to
  have.

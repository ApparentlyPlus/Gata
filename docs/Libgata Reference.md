# Libgata Reference

Manual pages for `libgata`, the Gata standard library. Section 3 is library calls; section 7 is the overview.

The language itself is documented in [The Gata Programming Language](The%20Gata%20Programming%20Language.md).

| Page | Description |
|---|---|
| [libgata(7)](#libgata7) | library overview and conventions |
| [algorithms(3)](#algorithms3) | sort, search, min/max |
| [bigint(3)](#bigint3) | arbitrary-precision integers |
| [char(3)](#char3) | character classification |
| [console(3)](#console3) | text I/O and screen control |
| [format(3)](#format3) | printf-style formatting |
| [hash(3)](#hash3) | hashing primitives |
| [int(3)](#int3) | int conversion and parsing |
| [list(3)](#list3) | growable array |
| [long(3)](#long3) | int64 conversion and parsing |
| [map(3)](#map3) | hash maps |
| [math(3)](#math3) | floating-point math |
| [mem(3)](#mem3) | allocation and raw memory |
| [misc(3)](#misc3) | startup utilities |
| [optional(3)](#optional3) | optional values |
| [priorityqueue(3)](#priorityqueue3) | binary min-heap |
| [queue(3)](#queue3) | FIFO queue |
| [random(3)](#random3) | pseudo-random numbers |
| [result(3)](#result3) | success-or-error values |
| [runtime(3)](#runtime3) | reference-counting runtime |
| [set(3)](#set3) | hash sets |
| [span(3)](#span3) | non-owning buffer views |
| [stack(3)](#stack3) | LIFO stack |
| [string(3)](#string3) | strings and string building |
| [sync(3)](#sync3) | locks and atomics |
| [sys(3)](#sys3) | process and machine control |
| [time(3)](#time3) | monotonic clock |

---

## libgata(7)

### NAME

libgata — the Gata standard library

### DESCRIPTION

`libgata` is ordinary Gata source, shipped with `appa` and compiled into your image. It has no privileges the language lacks: every platform capability it reaches goes through the environment floor.

Import one module at a time, by file basename. There is no umbrella import, and an unimported module is never parsed or compiled in.

```go
import List;
import Console;
```

Imports are transitive for visibility only. Import what you use.

### CONVENTIONS

**Lenient and strict.** The plain name returns a zero value on failure; the `Strict` or `OrThrow` twin is `throws` and refuses. Use the strict form only when a real zero and a failure differ for you.

**Zero value.** `default(T)`: `0`, `false`, or `null` for a class. Gata has no runtime null checks.

**Ownership.** Containers own their elements. `Pop` and `Dequeue` transfer ownership to the caller; every other accessor returns a borrowed reference. `List.Raw()` is a borrow-only view with no bounds checks.

**Null arguments.** Generally treated as empty or absent, not faulted. Exceptions are noted per page.

**Growth.** Every growable container has `Length()`, `IsEmpty()`, `Capacity()` and `Reserve(int)`. Growth is amortised doubling.

**Iteration.** `for..in` needs `Length()` and `Get(int)`. Only `List[T]` qualifies. `String` does not: it spells its accessor `CharAt`.

**Calling.** Module members are static: `Int.Parse(s)`. Free functions are called bare: `alloc(n)`, `IsSome(m)`. Generic type arguments are always inferred.

### CAPABILITIES

Reaching these links the matching GatOS subsystem into the image. Everything else is pure computation.

| Reaching | Pulls in |
|---|---|
| `alloc`, `new`, any container | memory management |
| [console(3)](#console3) output | framebuffer or serial console |
| `Console.InputLine` | keyboard driver and input stack |
| [time(3)](#time3), `new Random()` | timers and interrupts |
| a `process` or `thread` declaration | scheduler and threading |

### FILES

`Runtime.g` and `Mem.g` are the base; any program declaring a class needs both bound. Importing any higher-level module pulls them in.

| File | Imports |
|---|---|
| `Char.g`, `Mem.g`, `Optional.g`, `Result.g`, `Runtime.g`, `Span.g`, `Sync.g`, `Sys.g`, `Time.g` | — |
| `Format.g`, `Hash.g` | `String` |
| `Algorithms.g` | `List`, `Span` |
| `Math.g` | `Algorithms` |
| `Random.g` | `Time` |
| `Int.g`, `Long.g` | `String`, `Char` |
| `Console.g` | `String`, `Int` |
| `Misc.g` | `String`, `Console` |
| `Stack.g`, `Queue.g`, `PriorityQueue.g` | `Runtime`, `String`, `Mem` |
| `BigInt.g` | `String`, `Char`, `Mem`, `Runtime` |
| `List.g` | `Runtime`, `Optional`, `String`, `Mem`, `Span` |
| `String.g` | `Runtime`, `Char`, `Mem`, `List`, `Span`, `Int`, `Long`, `Format` |
| `Set.g` | `Runtime`, `String`, `List`, `Hash`, `Mem` |
| `Map.g` | `Runtime`, `String`, `List`, `Mem`, `Hash`, `Optional` |

---

## algorithms(3)

### NAME

Algorithms — generic sorting, searching and comparison

### LIBRARY

libgata (`Algorithms.g`)

### SYNOPSIS

```go
import Algorithms;

module Algorithms

public T    func Min[T](T a, T b)
public T    func Max[T](T a, T b)
public      func Swap[T](ref T a, ref T b)
public      func SwapElems[T](List[T] list, int i, int j)
public bool func IsSorted[T](List[T] list)
public      func Sort[T](List[T] list)
public      func SortBy[T](List[T] list, func(T, T) -> bool less)
public int  func BinarySearch[T](List[T] sortedList, T target)
public T    func MinBy[T](List[T] list, func(T, T) -> bool less)
public T    func MaxBy[T](List[T] list, func(T, T) -> bool less)

public      func SortSpan[T](Span[T] s)
public      func SortSpanBy[T](Span[T] s, func(T, T) -> bool less)
public int  func BinarySearchSpan[T](Span[T] s, T target)
public bool func IsSortedSpan[T](Span[T] s)
public      func ReverseSpan[T](Span[T] s)
```

### DESCRIPTION

Duck-typed generics over `<` and `==`. Nothing is constrained; a `T` lacking the operator fails at the instantiation that needed it.

These are generic methods, not members of a generic class, so each is stamped only for the types actually used.

**`Min()`**, **`Max()`** — Smaller and larger of *a* and *b* by `<`.

**`Swap()`** — Exchange two variables. Both parameters are `ref`; the call site must write `ref` too.

**`SwapElems()`** — Exchange `list[i]` and `list[j]` in place.

**`IsSorted()`** — True when *list* is non-decreasing by `<`.

**`Sort()`** — Sort in place by `<`. Median-of-three introsort.

**`SortBy()`** — As `Sort()`, driven by *less* instead of `<`. `less(a, b)` is true when *a* precedes *b*. *less* must be a free function; Gata has no closures.

**`BinarySearch()`** — Index of *target* in an already-sorted list.

**`MinBy()`**, **`MaxBy()`** — Extreme element of *list* by *less*.

**`SortSpan()`**, **`SortSpanBy()`**, **`BinarySearchSpan()`**, **`IsSortedSpan()`**, **`ReverseSpan()`** — The same five, over a [span(3)](#span3) instead of a `List[T]`. Kept as their own engine rather than routed through `List`, since building a temporary list just to sort a buffer that already has one is exactly the allocation `Span` exists to avoid.

### RETURN VALUE

`Min()` returns *b* on a tie; `Max()` returns *a*. Only `<` is consulted.

`BinarySearch()` and `BinarySearchSpan()` return the index, or -1 if absent.

`MinBy()` and `MaxBy()` return the zero value if *list* is empty.

### NOTES

`Sort()`, `SortBy()`, `SortSpan()` and `SortSpanBy()` are not stable.

`BinarySearch()` and `BinarySearchSpan()` on an unsorted input return a meaningless result, not an error.

### SEE ALSO

[list(3)](#list3), [span(3)](#span3), [math(3)](#math3)

---

## bigint(3)

### NAME

BigInt — arbitrary-precision signed integers

### LIBRARY

libgata (`BigInt.g`)

### SYNOPSIS

```go
import BigInt;

class BigInt

public static BigInt func Zero()
public static BigInt func One()
public static BigInt func MinusOne()
public static BigInt func FromInt(int v)
public static BigInt func FromLong(int64 v)
public static BigInt func FromULong(uint64 v)
public        BigInt func Clone()

public int   func Sign()
public bool  func IsZero()
public bool  func IsOne()
public bool  func IsMinusOne()
public bool  func IsNegative()
public bool  func IsEven()
public bool  func IsPowerOfTwo()
public int   func BitLength()
public int   func LimbCount()
public bool  func TestBit(int i)

public int    func CompareTo(BigInt o)
public bool   func Equals(BigInt o)
public static int    func Compare(BigInt a, BigInt b)
public static BigInt func Min(BigInt a, BigInt b)
public static BigInt func Max(BigInt a, BigInt b)

public static BigInt func Add(BigInt a, BigInt b)
public static BigInt func Subtract(BigInt a, BigInt b)
public static BigInt func Multiply(BigInt a, BigInt b)
public static BigInt func Negate(BigInt v)
public static BigInt func Abs(BigInt v)
public        BigInt func Square()

public static BigInt func DivRem(BigInt a, BigInt b, ref BigInt rem)
public static BigInt func Divide(BigInt a, BigInt b)
public static BigInt func Remainder(BigInt a, BigInt b)
public static throws BigInt func DivRemOrThrow(BigInt a, BigInt b, ref BigInt rem)
public static throws BigInt func DivideOrThrow(BigInt a, BigInt b)
public static throws BigInt func RemainderOrThrow(BigInt a, BigInt b)

public static BigInt func Pow(BigInt v, int e)
public static BigInt func ModPow(BigInt v, BigInt e, BigInt m)
public static BigInt func Gcd(BigInt a, BigInt b)

public bool   func FitsInt()
public bool   func FitsLong()
public int    func ToInt()
public int64  func ToLong()
public String func ToString()
public String func ToHex()
public String func ToStringRadix(int radix)

public static BigInt func Parse(String s)
public static BigInt func ParseRadix(String s, int radix)
public static throws BigInt func ParseStrict(String s)
public static throws BigInt func ParseStrictRadix(String s, int radix)

operators:  + - * / %   & | ^ ~   << >>   == != < > <= >=   -(unary)
```

### DESCRIPTION

Sign-and-magnitude: a sign in {-1, 0, +1} and a little-endian array of 32-bit limbs. Zero is the only value with no limbs.

A `BigInt` is immutable. Every operation allocates its result, so sharing a reference is always safe.

Multiplication is schoolbook below 32 limbs and Karatsuba above, with a split for lopsided operands between. Squaring crosses over at 48 limbs. Division is grammar-school long division. `ModPow()` is square-and-multiply with a reduction per step.

`new BigInt()` is zero. `default(BigInt)` is `null`.

**`FromULong()`** — Reads the top bit as magnitude, not sign.

**`Clone()`** — A separate object with the same value. Rarely needed; values are immutable.

**`BitLength()`** — Bits of the magnitude: 0 for zero, 1 for ±1.

**`IsPowerOfTwo()`** — True only for a positive value with one bit set.

**`TestBit()`** — Bit *i* of the magnitude, not of a two's-complement view.

**`Square()`** — `v * v`. The `*` operator detects this case and routes here anyway.

**`Pow()`** — Square-and-multiply. `Pow(v, 0)` is 1 for every *v*, including zero.

**`ModPow()`** — Magnitude computed from `|v|`, sign applied at the end: negative exactly when *v* is negative and *e* is odd.

**`Gcd()`** — Euclid over full-width remainders. Always non-negative.

**`ToStringRadix()`** — Radix 2 to 36, digits `0`-`9` then `a`-`z`.

**`ToHex()`** — Radix 16 with a `0x` prefix, rendering the magnitude: `-0xff`, not two's complement.

**`Parse()`** — Skips leading whitespace, takes an optional sign, stops at the first non-digit.

**`ParseStrict()`** — Requires the whole string to be one clean integer: optional surrounding whitespace, optional sign, at least one digit, nothing else.

Division is truncated, as in C: the quotient rounds toward zero and the remainder carries the dividend's sign, so `a == (a / b) * b + a % b` for every sign combination.

`>>` is arithmetic, rounding toward negative infinity: `-1 >> 1` is -1. A negative shift count reads as the opposite shift.

`&`, `|`, `^` and `~` act as if the value were two's complement with infinite sign extension, so `-1 & x == x` and `~x == -(x + 1)`.

### RETURN VALUE

A null operand is treated as zero throughout, including in comparison.

`Divide()`, `Remainder()`, `DivRem()`, `/` and `%` return zero when the divisor is zero.

`Pow()` returns zero for a negative exponent.

`ModPow()` returns zero when the modulus is zero or ±1, or the exponent is negative.

`ToInt()` and `ToLong()` truncate silently when the value does not fit; test with `FitsInt()` or `FitsLong()` first.

`ToStringRadix()` falls back to radix 10 for a radix outside 2 to 36.

`Parse()` and `ParseRadix()` return zero for null, empty and invalid input.

`Abs()` returns an already non-negative value unchanged rather than copying.

### ERRORS

`DivideOrThrow()`, `RemainderOrThrow()` and `DivRemOrThrow()` throw when the divisor is zero.

`ParseStrict()` and `ParseStrictRadix()` throw on null, an out-of-range radix, or any input that is not one clean integer.

### NOTES

`++` and `--` are not overloaded. Gata requires them to mutate in place, which every holder of the reference would observe.

Comparing against the `null` literal is a pointer check and never reaches `==`.

Not implemented: Toom-3 multiplication, Burnikel-Ziegler division, Montgomery and Barrett reduction, Lehmer GCD, byte-array and `double` conversion, logarithms.

### EXAMPLES

```go
let BigInt r = null;
let q = BigInt.DivRem(a, b, ref r);

let n = BigInt.ParseStrict(line) catch { assign BigInt.Zero(); };
```

### SEE ALSO

[int(3)](#int3), [long(3)](#long3), [math(3)](#math3)

---

## char(3)

### NAME

Char — ASCII character classification and case

### LIBRARY

libgata (`Char.g`)

### SYNOPSIS

```go
import Char;

module Char

public bool func IsDigit(char c)
public bool func IsLetter(char c)
public bool func IsLetterOrDigit(char c)
public bool func IsHexDigit(char c)
public bool func IsWhitespace(char c)
public bool func IsUpper(char c)
public bool func IsLower(char c)
public char func ToUpper(char c)
public char func ToLower(char c)
public int  func DigitValue(char c)
```

### DESCRIPTION

ASCII only. Gata has no Unicode.

**`IsDigit()`** — `'0'` to `'9'`.

**`IsLetter()`** — `'a'`-`'z'`, `'A'`-`'Z'`.

**`IsHexDigit()`** — `'0'`-`'9'`, `'a'`-`'f'`, `'A'`-`'F'`.

**`IsWhitespace()`** — Space, tab, newline, carriage return, vertical tab, form feed.

**`ToUpper()`**, **`ToLower()`** — Map letters; other characters pass through unchanged.

**`DigitValue()`** — Numeric value of a decimal digit.

### RETURN VALUE

`DigitValue()` returns -1 for anything that is not `'0'` to `'9'`. It does not decode hex.

### SEE ALSO

[string(3)](#string3), [int(3)](#int3)

---

## console(3)

### NAME

Console — text I/O and screen control

### LIBRARY

libgata (`Console.g`)

### SYNOPSIS

```go
import Console;

module Console

public void func Print(String s)
public void func PrintLine(String s)
public void func NewLine()
public void func Clear()
public void func Home()
public void func ShowCursor(bool visible)
public int  func Width()
public int  func Height()
public void func SetColor(int fg, int bg)
public throws String func InputLine()
```

### DESCRIPTION

Output is batched: one `Print()` is one write through the floor.

**`Print()`** — Write *s* with no trailing newline.

**`PrintLine()`** — `Print()` then `NewLine()`. Two writes.

**`Clear()`** — Blank the screen.

**`Home()`** — Move the cursor to the top-left without blanking, for redrawing a frame in place.

**`Width()`**, **`Height()`** — Screen size in characters.

**`SetColor()`** — Foreground and background as 0-15 VGA palette indices. Stays in effect until changed.

**`InputLine()`** — Read one line, without the trailing newline.

### RETURN VALUE

`Print()` writes nothing for a null string.

### ERRORS

`InputLine()` throws at end of input.

### NOTES

`InputLine()` reads through a 1024-byte buffer; a longer line is truncated rather than an error, and the remainder is queued for the next call.

Calling `InputLine()` links the keyboard driver and input stack into a GatOS image.

Building a line and printing it once is cheaper than printing its pieces.

### EXAMPLES

```go
let name = Console.InputLine() catch { assign "anonymous"; };
```

### SEE ALSO

[string(3)](#string3), [format(3)](#format3), [misc(3)](#misc3)

---

## format(3)

### NAME

Format — printf-style formatting

### LIBRARY

libgata (`Format.g`)

### SYNOPSIS

```go
import Format;

module Format

public String func Double(double v)
public String func Double(double v, String spec)
public String func Int(int64 v, String spec)
public String func UInt(uint64 v, String spec)
public String func Str(String v, String spec)
```

### DESCRIPTION

Gata's interpolation has no format specifiers. Formatting is a library call instead.

Each function runs the platform's `snprintf` into an exact-size buffer, so nothing is truncated.

**`Double(v)`** — Default general form, `"%g"`. Carries the `stringify_float` role, so an interpolated `double` goes through it.

**`Double(v, spec)`** — Any float spec: `"%.2f"`, `"%e"`, `"%12.4g"`.

**`Int()`** — Any signed integer spec: `"%d"`, `"%5d"`.

**`UInt()`** — Any unsigned spec: `"%u"`, `"%x"`, `"%08X"`.

**`Str()`** — Any string spec: `"%s"`, `"%-20s"`, `"%.8s"`.

### RETURN VALUE

A null *spec* defaults to `"%g"`, `"%d"`, `"%u"` and `"%s"` respectively. `Str()` renders a null *v* as the empty string.

### NOTES

Write specs without a length modifier. `Int()` and `UInt()` take 64-bit values and insert `ll` themselves; writing `"%lld"` yields `"%llld"`.

### EXAMPLES

```go
let String s = $"pi = {Format.Double(pi, "%.4f")}";
```

### SEE ALSO

[string(3)](#string3), [int(3)](#int3), [long(3)](#long3)

---

## hash(3)

### NAME

Hash — hashing primitives for the hash containers

### LIBRARY

libgata (`Hash.g`)

### SYNOPSIS

```go
import Hash;

module Hash

public usize func Mix(usize x)
public usize func HashString(String key)
```

### DESCRIPTION

**`Mix()`** — SplitMix64-style finalizer. Decorrelates structured integer keys so sequential or aligned keys do not cluster in a linear-probed table.

**`HashString()`** — FNV-1a over the string's raw bytes.

### NOTES

These live in their own module so `Map`, `StringMap`, `Set` and `StringSet` share one copy; a static method inside a generic class is re-stamped per instantiation.

Rarely called directly. They are public so a custom container can hash identically.

### SEE ALSO

[map(3)](#map3), [set(3)](#set3)

---

## int(3)

### NAME

Int — conversion and parsing for `int`

### LIBRARY

libgata (`Int.g`)

### SYNOPSIS

```go
import Int;

module Int

public int    func MaxValue()
public int    func MinValue()
public String func ToString(int n)
public String func ToUnsignedString(uint64 v)
public String func ToHex(int n)
public int    func Parse(String s)
public throws int func ParseStrict(String s)
```

### DESCRIPTION

**`MaxValue()`**, **`MinValue()`** — 2147483647 and -2147483648. Functions, because Gata has no global `let` or static fields.

**`ToString()`** — Decimal, with a leading `-` for negatives. Carries the `stringify_int` role.

**`ToUnsignedString()`** — Decimal for an unsigned value. Carries `stringify_uint`; the signed printer would read the high bit as a sign.

**`ToHex()`** — Lowercase hexadecimal with a `0x` prefix.

**`Parse()`** — Skips leading whitespace, takes an optional sign, stops at the first non-digit.

**`ParseStrict()`** — Requires the whole string to be one clean integer.

### RETURN VALUE

`Parse()` returns 0 for null, empty and invalid input.

### ERRORS

`ParseStrict()` throws on null and on anything but one clean integer.

### NOTES

Neither parser detects overflow; a value too large wraps.

### SEE ALSO

[long(3)](#long3), [bigint(3)](#bigint3), [format(3)](#format3), [char(3)](#char3)

---

## list(3)

### NAME

List — generic growable array

### LIBRARY

libgata (`List.g`)

### SYNOPSIS

```go
import List;

class List[T]

public int  func Length()
public bool func IsEmpty()
public int  func Capacity()
public void func Reserve(int n)

public T           func Get(int i)
public Optional[T] func At(int i)
public T           func First()
public T           func Last()
public T*          func Raw()
public Span[T]     func AsSpan()
public Span[T]     func SubSpan(int start, int len)

public void func Set(int i, T v)
public void func Add(T v)
public void func Insert(int i, T v)
public void func AddRange(List[T] other)
public void func RemoveAt(int i)
public void func RemoveLast()
public void func Clear()
public void func Reverse()

public List[T] func Clone()
public int     func IndexOf(T v)
public bool    func Contains(T v)

public operator T       func [](int i)
public operator         func []=(int i, T v)
public operator List[T] func <<(T v)
```

### DESCRIPTION

The ordered container. Owns its elements: storing retains, removing releases, dropping the list releases the rest. The only type `for..in` walks.

Growth doubles from 8.

**`Get()`** — Element at *i*.

**`At()`** — Element at *i* as an `Optional[T]`, distinguishing absent from a stored zero.

**`First()`**, **`Last()`** — `Get(0)` and `Get(Length() - 1)`.

**`Raw()`** — Borrow-only view of the backing buffer: no bounds checks, no retain, elements stay owned by the list. Used by the sorts in [algorithms(3)](#algorithms3).

**`AsSpan()`** — A [span(3)](#span3) over the whole backing buffer. Same borrow-only deal as `Raw()`, with bounds carried alongside the pointer.

**`SubSpan()`** — A span over `[start, start + len)`, clamped the way `Substring` clamps.

**`Set()`** — Store *v* at *i*. Does not grow the list.

**`Add()`** — Append.

**`Insert()`** — Insert at *i*, clamped to `[0, Length()]`, shifting the tail with one move.

**`AddRange()`** — Append every element of *other*, reserving once up front.

**`Clone()`** — A new list holding the same elements, retained, not deep-copied.

**`IndexOf()`** — First index of *v* by `==`, so a class-typed *T* uses its own `==` if it has one and reference identity otherwise.

**`Clear()`** — Release every element, keep the buffer.

`xs << v` is `Add()` returning the list, so appends chain.

### RETURN VALUE

`Get()`, `First()` and `Last()` return the zero value when the index is out of range or the list is empty.

`At()` returns `None` when *i* is out of range.

`IndexOf()` returns -1 if absent.

`Set()` and `RemoveAt()` are no-ops for an out-of-range *i*. `AddRange(null)` does nothing.

### NOTES

Use `List[T]` rather than a fixed `[N]T` whenever the elements are class-typed; a fixed array never releases its elements.

Do not free the pointer from `Raw()`, or keep it across a mutation that may reallocate.

### EXAMPLES

```go
let xs = new List[int]() { 1, 2, 3 };
xs << 4 << 5;
for v in xs { Console.PrintLine($"{v}"); }
```

### SEE ALSO

[algorithms(3)](#algorithms3), [optional(3)](#optional3), [span(3)](#span3), [stack(3)](#stack3), [queue(3)](#queue3)

---

## long(3)

### NAME

Long — conversion and parsing for `int64`

### LIBRARY

libgata (`Long.g`)

### SYNOPSIS

```go
import Long;

module Long

public String func ToString(int64 n)
public int64  func Parse(String s)
public throws int64 func ParseStrict(String s)
```

### DESCRIPTION

The shapes of [int(3)](#int3), one width up.

**`ToString()`** — Decimal. Carries the `stringify_long` role.

**`Parse()`**, **`ParseStrict()`** — As `Int.Parse()` and `Int.ParseStrict()`.

### RETURN VALUE

`Parse()` returns 0 for null, empty and invalid input.

### ERRORS

`ParseStrict()` throws on null and on anything but one clean integer.

### NOTES

Neither parser detects overflow.

There is no `Long.ToHex()`; use `Format.UInt(v, "%x")`.

### SEE ALSO

[int(3)](#int3), [bigint(3)](#bigint3), [format(3)](#format3)

---

## map(3)

### NAME

Map, StringMap — hash maps

### LIBRARY

libgata (`Map.g`)

### SYNOPSIS

```go
import Map;

class Map[K, V]
class StringMap[V]

public int  func Length()
public bool func IsEmpty()
public int  func Capacity()
public void func Reserve(int n)

public void        func Put(K key, V value)
public V           func Get(K key)
public throws V    func GetOrThrow(K key)
public Optional[V] func Find(K key)
public bool        func TryGet(K key, ref V out)
public V           func GetOr(K key, V fallback)
public bool        func Has(K key)
public void        func Remove(K key)
public void        func Clear()
public List[K]     func Keys()
public List[V]     func Values()

public operator V func [](K key)
public operator   func []=(K key, V value)
```

`StringMap[V]` has the same members with `String` in place of `K`.

### DESCRIPTION

Open addressing with linear probing, growing to keep the load factor under 0.7. Deletion backward-shifts the displaced run rather than leaving tombstones.

`Map[K, V]` hashes the key's bits through `Hash.Mix()`; `K` needs `==`. `StringMap[V]` hashes and compares string contents with `Hash.HashString()`.

**`Put()`** — Insert or overwrite.

**`Keys()`**, **`Values()`** — New lists, in unspecified but matching order.

**`Clear()`** — Empty the map, keep the buffers.

The five readers differ only in how they report absence:

| Call | Returns | On absence |
|---|---|---|
| `Get()` | `V` | the zero value |
| `GetOrThrow()` | `V` | throws |
| `Find()` | `Optional[V]` | `None` |
| `TryGet()` | `bool`, value through *out* | `false` |
| `GetOr()` | `V` | *fallback* |

`Find()`, `TryGet()` and `GetOr()` each distinguish absent from a stored zero, in one probe.

### RETURN VALUE

`Remove()` is a no-op for an absent key.

`StringMap.Put()` ignores a null key; the `StringMap` readers treat a null key as absent.

### ERRORS

`GetOrThrow()` throws when the key is absent, and `StringMap.GetOrThrow()` also when the key is null.

### NOTES

Use `StringMap[V]` for string keys. `Map[String, V]` hashes the reference, so two equal strings at different addresses would be different keys.

Iteration order is unspecified and not stable across versions.

`if (m.Has(k)) { m.Get(k); }` probes twice; use one of the single-probe readers.

### SEE ALSO

[set(3)](#set3), [hash(3)](#hash3), [optional(3)](#optional3), [list(3)](#list3)

---

## math(3)

### NAME

Math — floating-point math

### LIBRARY

libgata (`Math.g`)

### SYNOPSIS

```go
import Math;

module Math

public double func Pi()
public double func E()

public double func Abs(double x)
public double func Floor(double x)
public double func Ceil(double x)
public double func Round(double x)
public double func Trunc(double x)
public double func Sign(double x)
public double func CopySign(double x, double y)

public double func Sqrt(double x)
public double func Pow(double b, double e)
public double func Exp(double x)
public double func Log(double x)
public double func Log1p(double x)
public double func Expm1(double x)
public double func ScalbN(double x, int n)
public double func Mod(double x, double y)

public double func Sin(double x)
public double func Cos(double x)
public double func Tan(double x)
public double func Asin(double x)
public double func Acos(double x)
public double func Atan(double x)
public double func Atan2(double y, double x)

public double func Sinh(double x)
public double func Cosh(double x)
public double func Tanh(double x)
public double func Asinh(double x)
public double func Acosh(double x)
public double func Atanh(double x)

public double func Min(double a, double b)
public double func Max(double a, double b)
public double func Clamp(double v, double lo, double hi)
```

### DESCRIPTION

A full libm written in Gata, not a wrapper around the platform's, so it runs in a kernel with no C library underneath. The kernels are fdlibm-derived.

All arguments and results are `double`; there are no `float` overloads. Trigonometric arguments are in radians.

**`Round()`** — Rounds half away from zero.

**`Trunc()`** — Rounds toward zero.

**`Sign()`** — -1.0, 0.0 or 1.0.

**`CopySign()`** — *x* with the sign of *y*. Carries a sign across zero and infinity without branching.

**`Log()`** — Natural logarithm.

**`Log1p()`**, **`Expm1()`** — `log(1 + x)` and `exp(x) - 1`, accurate for small *x* where the naive form loses everything to cancellation.

**`ScalbN()`** — `x * 2^n` by exponent arithmetic: exact, and without the overflow an explicit power would risk.

**`Mod()`** — Floating-point remainder, `fmod`. Gata's `%` rejects floating-point operands and points here.

**`Atan2()`** — Takes *y* first and resolves the quadrant, which `Atan(y / x)` cannot.

**`Min()`**, **`Max()`**, **`Clamp()`** — `double`-typed conveniences over [algorithms(3)](#algorithms3).

### NOTES

There is no `Log10()` or `Log2()`; divide by `Math.Log(10.0)`.

Argument reduction for large trigonometric inputs uses the full Payne-Hanek path, so `Sin()` of a very large value stays accurate.

Everything not listed here is a private helper.

### SEE ALSO

[algorithms(3)](#algorithms3), [format(3)](#format3), [bigint(3)](#bigint3)

---

## mem(3)

### NAME

alloc, free, Mem — allocation and raw memory operations

### LIBRARY

libgata (`Mem.g`)

### SYNOPSIS

```go
import Mem;

void* func alloc(usize n)
void  func free(void* p)

module Mem

public void  func Copy(void* d, void* s, usize n)
public void  func Move(void* d, void* s, usize n)
public void  func Fill(void* d, byte v, usize n)
public int   func Compare(void* a, void* b, usize n)
public usize func StrLen(char* s)
```

### DESCRIPTION

`alloc()` and `free()` are free functions, called bare.

**`alloc()`** — *n* bytes of raw, uninitialised memory. Carries the `alloc` role, so `new` allocates through it.

**`free()`** — Release memory from `alloc()`.

**`Copy()`** — Copy *n* bytes. Does not handle overlap.

**`Move()`** — Copy *n* bytes, tolerating overlap, copying backward when needed.

**`Fill()`** — Set *n* bytes to *v*.

**`Compare()`** — Byte-wise compare of the first *n* bytes.

**`StrLen()`** — Length of a NUL-terminated C string.

### RETURN VALUE

`Compare()` returns negative, zero or positive from the first differing byte, matching a plain byte scan exactly.

`StrLen()` returns 0 for null.

### NOTES

Allocation does not fail. There is no null return to check and no `throws`; a failed allocation faults at the allocation. Policy lives in the environment's allocator.

The buffer routines move or compare eight bytes per iteration once both cursors reach a common alignment, with byte loops for the head, the tail, and pointers that can never align.

Pair `alloc()` with `defer free()`.

### EXAMPLES

```go
unsafe {
    let p = alloc(1024 as usize) as char*;
    defer free(p);
}
```

### SEE ALSO

[runtime(3)](#runtime3), [string(3)](#string3)

---

## misc(3)

### NAME

Misc — startup utilities

### LIBRARY

libgata (`Misc.g`)

### SYNOPSIS

```go
import Misc;

module Misc

public void func PrintBanner()
```

### DESCRIPTION

**`PrintBanner()`** — Print the centred GatOS startup banner, sized to `Console.Width()`, finishing with a full-width horizontal rule. This is what `appa new` puts in a fresh kernel entry point.

### NOTES

`PrintBanner()` sets colours as it goes and leaves them at white on black rather than restoring the previous colour.

### SEE ALSO

[console(3)](#console3)

---

## optional(3)

### NAME

Optional, IsSome, IsNone, ValueOr — a value that is either there or not

### LIBRARY

libgata (`Optional.g`)

### SYNOPSIS

```go
import Optional;

union Optional[V] { Some(V v), None }

bool func IsSome[V](Optional[V] m)
bool func IsNone[V](Optional[V] m)
V    func ValueOr[V](Optional[V] m, V fallback)
```

### DESCRIPTION

A tagged union, so a value type: assigning copies it, and a `Some` holding a class retains its payload correctly.

The helpers are free functions, called bare: `IsSome(m)`, not `Optional.IsSome(m)`.

**`ValueOr()`** — The value if present, otherwise *fallback*.

The point of receiving one is the `match`, which the compiler checks for exhaustiveness.

### NOTES

Named for its module rather than the shorter `Maybe`: type names in Gata are global to the build, so a library claiming a common one takes it from every program that imports it.

`Optional.Some(3)` infers its instantiation from the argument. `None` has no payload to infer from, so it needs `Optional[int].None()` or an assignment target that settles it.

### EXAMPLES

```go
match (list.At(i)) {
    case Some(v) { Console.PrintLine($"got {v}"); }
    case None    { Console.PrintLine("nothing there"); }
}

let int n = ValueOr(map.Find("count"), 0);
```

### SEE ALSO

[list(3)](#list3), [map(3)](#map3), [result(3)](#result3)

---

## priorityqueue(3)

### NAME

PriorityQueue — binary min-heap

### LIBRARY

libgata (`PriorityQueue.g`)

### SYNOPSIS

```go
import PriorityQueue;

class PriorityQueue[T]

public int  func Length()
public bool func IsEmpty()
public int  func Capacity()
public void func Reserve(int n)

public void func Push(T v)
public T    func Pop()
public throws T func PopOrThrow()
public T    func Peek()
public void func Clear()
```

### DESCRIPTION

Ordered by `<` on `T`, smallest out first. Growth doubles from 8.

**`Push()`** — Insert and sift up.

**`Pop()`** — Remove and return the minimum, sifting down. Transfers ownership to the caller.

**`Peek()`** — The minimum without removing it. The heap keeps ownership.

**`Clear()`** — Empty the heap, keep the buffer.

### RETURN VALUE

`Pop()` and `Peek()` return the zero value when the heap is empty.

### ERRORS

`PopOrThrow()` throws when the heap is empty.

### NOTES

For a max-heap or any other order, give `T` a `<` that means what you want, or keep a `List` and use `Algorithms.SortBy()`.

Ties come out in unspecified order; the heap is not stable.

### SEE ALSO

[queue(3)](#queue3), [stack(3)](#stack3), [algorithms(3)](#algorithms3)

---

## queue(3)

### NAME

Queue — FIFO queue

### LIBRARY

libgata (`Queue.g`)

### SYNOPSIS

```go
import Queue;

class Queue[T]

public int  func Length()
public bool func IsEmpty()
public int  func Capacity()
public void func Reserve(int n)

public void func Enqueue(T v)
public T    func Dequeue()
public throws T func DequeueOrThrow()
public T    func Peek()
public void func Clear()
```

### DESCRIPTION

Backed by a ring buffer, so both ends are constant-time and neither shifts. Growth doubles from 8, unrolling the live window to start at index 0.

**`Enqueue()`** — Add at the back.

**`Dequeue()`** — Remove from the front. Transfers ownership to the caller.

**`Peek()`** — The front without removing it. The queue keeps ownership.

**`Clear()`** — Empty the queue, keep the buffer.

### RETURN VALUE

`Dequeue()` and `Peek()` return the zero value when the queue is empty.

### ERRORS

`DequeueOrThrow()` throws when the queue is empty.

### SEE ALSO

[stack(3)](#stack3), [priorityqueue(3)](#priorityqueue3), [list(3)](#list3)

---

## random(3)

### NAME

Random — pseudo-random numbers

### LIBRARY

libgata (`Random.g`)

### SYNOPSIS

```go
import Random;

class Random

public void   func Reseed(int64 seed)
public uint64 func NextU64()
public int    func Next()
public int    func NextRange(int lo, int hi)
public double func NextDouble()
public bool   func NextBool()
```

### DESCRIPTION

xoshiro256\*\* with a SplitMix64 seeding step.

`new Random()` seeds from `Time.Nanos()`, so each run differs.

**`Reseed()`** — Deterministic reset. The same seed always produces the same sequence.

**`NextU64()`** — The raw generator: 64 uniform bits.

**`Next()`** — Uniform in `[0, 2^31)`.

**`NextRange()`** — Uniform in `[lo, hi)`.

**`NextDouble()`** — Uniform in `[0.0, 1.0)`, with the full 53 bits a `double` holds.

**`NextBool()`** — `true` or `false`.

### RETURN VALUE

`NextRange()` returns *lo* when `hi <= lo`.

### NOTES

Not cryptographically secure. The full state is recoverable from a handful of outputs; do not generate keys, tokens or nonces.

Constructing a `Random` reads the clock, which links timers into a GatOS image. Reseed with a fixed value afterwards for reproducibility.

Not thread-safe. Two threads drawing from one instance interleave into its state; give each thread its own.

### SEE ALSO

[time(3)](#time3), [math(3)](#math3)

---

## result(3)

### NAME

Result, IsOk, IsErr, UnwrapOr, ErrorOr — a value that succeeded with a value or failed with an error

### LIBRARY

libgata (`Result.g`)

### SYNOPSIS

```go
import Result;

union Result[T, E] { Ok(T v), Err(E e) }

bool func IsOk[T, E](Result[T, E] r)
bool func IsErr[T, E](Result[T, E] r)
T    func UnwrapOr[T, E](Result[T, E] r, T fallback)
E    func ErrorOr[T, E](Result[T, E] r, E fallback)
```

### DESCRIPTION

The generic-union sibling of [optional(3)](#optional3): where `Optional` says only whether a value is there, `Result` keeps the reason for a failure instead of discarding it. A `throws` function still returns a bare pass/fail underneath everything a Gata program sees; `Result` is for the call site that wants to hold on to the detail rather than throw it away.

A tagged union, so a value type: assigning copies it, and an `Ok`/`Err` holding a class retains its payload correctly.

The helpers are free functions, called bare: `IsOk(r)`, not `Result.IsOk(r)`.

**`IsOk()`**, **`IsErr()`** — Which variant *r* holds.

**`UnwrapOr()`** — The value if `Ok`, otherwise *fallback*.

**`ErrorOr()`** — The error if `Err`, otherwise *fallback*.

The point of receiving one is usually the `match`, which the compiler checks for exhaustiveness.

### NOTES

`Result[int, String].Err("bad")` infers its instantiation from the argument the same way `Optional.Some()` does; a variant call that leaves a type argument unsettled needs it written out, exactly as `Optional[int].None()` does.

### EXAMPLES

```go
match (parse(line)) {
    case Ok(v)    { Console.PrintLine($"got {v}"); }
    case Err(msg) { Console.PrintLine($"error: {msg}"); }
}

let int n = UnwrapOr(parse(line), 0);
```

### SEE ALSO

[optional(3)](#optional3)

---

## runtime(3)

### NAME

retain, release, obj_init, obj — the reference-counting runtime

### LIBRARY

libgata (`Runtime.g`)

### SYNOPSIS

```go
import Runtime;

native type obj

void* func retain(void* p)
void  func release(void* p)
void  func obj_init(void* o, func(void*) -> void dtor)
```

### DESCRIPTION

The compiler inserts every retain and release; this file defines the operations it inserts. The compiler holds no runtime C names, emitting whatever symbol carries each role.

**`obj`** — The ARC header: a destructor pointer and a strong count, embedded first in every managed object, so any managed pointer aliases its header at offset 0.

**`retain()`** — Add a reference and return it.

**`release()`** — Drop a reference. At zero, run the destructor, then free the memory.

**`obj_init()`** — Stamp a fresh object's header: refcount 1, destructor *dtor*.

### RETURN VALUE

`retain()` returns the reference it counted.

### NOTES

Both `retain()` and `release()` leave static objects alone. A string literal carries a sentinel count, so it is never counted and never destroyed.

These are only nameable inside an `unsafe` block, which switches automatic counting off for its own extent.

Calling `retain(x)` as a bare statement is an error: the extra count would land on a temporary the same scope releases again. Store what it returns.

Any program declaring a class needs these bound, along with `alloc()` from [mem(3)](#mem3).

### EXAMPLES

```go
public void func Set(int i, T v) {
    unsafe {
        release(self.data[i]);
        self.data[i] = retain(v);
    }
}
```

### SEE ALSO

[mem(3)](#mem3)

---

## set(3)

### NAME

Set, StringSet — hash sets

### LIBRARY

libgata (`Set.g`)

### SYNOPSIS

```go
import Set;

class Set[T]
class StringSet

public int  func Length()
public bool func IsEmpty()
public int  func Capacity()
public void func Reserve(int n)

public void     func Add(T item)
public bool     func AddNew(T item)
public bool     func Has(T item)
public void     func Remove(T item)
public void     func Clear()
public List[T]  func ToList()

public Set[T] func Union(Set[T] other)
public Set[T] func Intersect(Set[T] other)
public operator Set[T] func +(Set[T] other)
public operator Set[T] func &(Set[T] other)
```

`StringSet` has the same members with `String` in place of `T`, except `Union()`, `Intersect()`, `+` and `&`.

### DESCRIPTION

Same table design as [map(3)](#map3): open addressing, linear probing, load factor under 0.7, backward-shift delete.

**`Add()`** — Insert if absent. Duplicates are ignored.

**`AddNew()`** — As `Add()`, reporting whether the item was new. One probe.

**`Remove()`** — Delete if present.

**`Clear()`** — Empty the set, keep the buffers.

**`ToList()`** — Collect the elements into a new list, in unspecified order.

**`Union()`**, **`Intersect()`** — Build a new set, leaving both operands alone. Walk live buckets directly rather than probing. `+` and `&` are their operator spellings.

### RETURN VALUE

`AddNew()` returns `false` if the item was already present, and `StringSet.AddNew()` also for a null item.

`Remove()` is a no-op for an absent item. `StringSet.Add()` ignores a null item.

### NOTES

Use `StringSet` for strings. `Set[String]` hashes the reference, not the contents.

Iteration order is unspecified and not stable across versions.

`if (!s.Has(x)) { s.Add(x); }` probes twice; use `AddNew()`.

There is no difference operator; filter with `Has()`.

`StringSet` has no `Union()` or `Intersect()`; build them from `ToList()` and `Add()`.

### SEE ALSO

[map(3)](#map3), [hash(3)](#hash3), [list(3)](#list3)

---

## span(3)

### NAME

Span, FromRaw, Length, IsEmpty, Raw, At, Slice, Equal, StartsWith — a non-owning, bounds-carrying view over a contiguous buffer

### LIBRARY

libgata (`Span.g`)

### SYNOPSIS

```go
import Span;

union Span[T] { View(T* ptr, int len) }

Span[T] func FromRaw[T](T* ptr, int len)

int  func Length[T](Span[T] s)
bool func IsEmpty[T](Span[T] s)
T*   func Raw[T](Span[T] s)
T    func At[T](Span[T] s, int i)

Span[T] func Slice[T](Span[T] s, int start, int len)
bool    func Equal[T](Span[T] a, Span[T] b)
bool    func StartsWith[T](Span[T] s, Span[T] prefix)
```

### DESCRIPTION

A Span borrows memory it does not own: copying one is a plain (pointer, length) copy, the same cost `sizeof(T*) + sizeof(int)` always is, and it never retains or releases anything by holding it. Build one from [string(3)](#string3)'s `AsSpan()`/`SubSpan()`, [list(3)](#list3)'s `AsSpan()`/`SubSpan()`, or `FromRaw()` over your own buffer.

`T` works for both unmanaged element types (`int`, `char`, an enum) and managed class types: a `Span[String]` never retains or releases its elements either way, so it borrows a class element exactly like it borrows a primitive one — the underlying `List`/`String` still owns it.

A Span is only as long-lived as what it borrows from. Nothing checks that for you, the same deal every raw pointer in Gata already makes.

The helpers are free functions, called bare: `Length(s)`, not `Span.Length(s)`.

**`FromRaw()`** — A span over an existing buffer. A null pointer or a non-positive *len* both collapse to the zero-length span, so a caller never has to special-case "the buffer might not exist".

**`Length()`**, **`IsEmpty()`** — Element count, and whether it's zero.

**`Raw()`** — The raw pointer, for library code that wants to walk the buffer itself, inside `unsafe`.

**`At()`** — Element *i*. Retains before returning, same as `List.Get()`: the return value is a value the caller now owns, per Gata's calling convention, regardless of whether the Span itself owns anything. Free for unmanaged `T`, where `retain`/`release` compile to nothing.

**`Slice()`** — The sub-span `[start, start + len)`, clamped to *s*'s own bounds.

**`Equal()`** — Element-wise `==` over both spans. Different lengths are never equal. Generic like `Algorithms.Min`/`Max`: fails to instantiate, once, named, on a `T` with no `==`, rather than silently comparing pointers.

**`StartsWith()`** — True if *prefix* occurs at the start of *s*. An empty *prefix* always matches.

### RETURN VALUE

`At()` returns the zero value if *i* is out of range.

`FromRaw()` and `Slice()` return the zero-length span rather than an out-of-bounds one; indices are clamped, never rejected.

### NOTES

There is no zero-argument `Empty[T]()`: a generic free function with nothing in its argument list to infer `T` from cannot be called, and a call site has no way to spell the type argument explicitly for a plain function call the way a union's own constructor call can (`Span[T].View(...)`). `FromRaw(nullTypedPointer, 0)` is the spelling for an empty span of a known element type.

[algorithms(3)](#algorithms3) has a Span-shaped `SortSpan()`/`SortSpanBy()`/`BinarySearchSpan()`/`IsSortedSpan()`/`ReverseSpan()`, kept as their own engine rather than routed through `List`.

### EXAMPLES

```go
let Span[char] sp = s.SubSpan(6, 5);
Console.PrintLine(String.FromSpan(sp));

let Span[int] xs = list.AsSpan();
Algorithms.SortSpan(xs);
```

### SEE ALSO

[string(3)](#string3), [list(3)](#list3), [algorithms(3)](#algorithms3)

---

## stack(3)

### NAME

Stack — LIFO stack

### LIBRARY

libgata (`Stack.g`)

### SYNOPSIS

```go
import Stack;

class Stack[T]

public int  func Length()
public bool func IsEmpty()
public int  func Capacity()
public void func Reserve(int n)

public void func Push(T v)
public T    func Pop()
public throws T func PopOrThrow()
public T    func Peek()
public void func Clear()
```

### DESCRIPTION

Growth doubles from 8.

**`Push()`** — Add to the top.

**`Pop()`** — Remove and return the top. Transfers ownership to the caller.

**`Peek()`** — The top without removing it. The stack keeps ownership.

**`Clear()`** — Empty the stack, keep the buffer.

### RETURN VALUE

`Pop()` and `Peek()` return the zero value when the stack is empty.

### ERRORS

`PopOrThrow()` throws when the stack is empty.

### SEE ALSO

[queue(3)](#queue3), [priorityqueue(3)](#priorityqueue3), [list(3)](#list3)

---

## string(3)

### NAME

String, StringBuilder — text

### LIBRARY

libgata (`String.g`)

### SYNOPSIS

```go
import String;

class String

public int   func Length()
public bool  func IsEmpty()
public char  func CharAt(int i)
public char* func CStr()
public Span[char] func AsSpan()
public Span[char] func SubSpan(int start, int len)

public bool func Equals(String other)
public int  func CompareTo(String other)

public bool func StartsWith(String prefix)
public bool func EndsWith(String suffix)
public int  func IndexOfChar(char c)
public int  func IndexOf(String sub)
public int  func IndexOf(String sub, int from)
public int  func LastIndexOf(String sub)
public bool func Contains(String sub)

public String func Substring(int start, int len)
public String func ToUpper()
public String func ToLower()
public String func Trim()
public String func Replace(String oldVal, String newVal)
public String func PadLeft(int width, char pad)
public String func PadRight(int width, char pad)
public String func Repeat(int n)
public String func Concat(String other)
public String func ToString()
public List[String] func Split(String sep)
public static String func Join(List[String] parts, String sep)

public static String func FromChar(char c)
public static String func FromRaw(char* raw)
public static String func FromBuffer(char* raw, int len)
public static String func FromSpan(Span[char] s)

public operator char   func [](int i)
public operator bool   func ==(String other)
public operator bool   func <(String other)     // and > <= >=
public operator String func +(String other)
public operator String func as(char c)
public operator String func as(char* raw)
public operator String func as(int n)
public operator String func as(int64 n)
public operator String func as(double v)
public operator String func as(bool b)

class StringBuilder

public int  func Length()
public int  func Capacity()
public void func Reserve(int n)
public void func Clear()
public void func AppendChar(char c)
public void func Append(String s)
public StringBuilder func Put(String s)
public String        func ToString()
```

### DESCRIPTION

`String` is the type of every string literal, and is immutable. A literal is one static object, created once, never freed, never mutated, so writing `"hello"` in a loop allocates nothing.

Everything here is ASCII and byte-indexed.

**`CStr()`** — The raw NUL-terminated buffer, for platform calls. Borrow-only; the string owns it.

**`AsSpan()`** — A [span(3)](#span3) over the whole string: a borrowed, non-allocating view, where `Substring` allocates a new `String`.

**`SubSpan()`** — Like `Substring()`, but borrows instead of allocating. Clamped the same way.

**`CompareTo()`** — Lexicographic order.

**`IndexOf(sub, from)`** — First index of *sub* at or after *from*. An empty *sub* matches at *from*.

**`Substring()`** — *len* characters from *start*. Indices are clamped.

**`ToUpper()`**, **`ToLower()`** — Map ASCII letters only.

**`Trim()`** — Remove leading and trailing whitespace.

**`PadLeft()`**, **`PadRight()`** — Pad to *width*.

**`Split()`** — Split on every occurrence of *sep*.

**`Join()`** — Concatenate *parts* with *sep* between them.

**`FromChar()`** — A one-character string. Carries the `stringify_char` role, which is why an interpolated `char` prints the character rather than its codepoint.

**`FromRaw()`**, **`FromBuffer()`** — Wrap a `char*`, NUL-terminated or of known length. Both copy the bytes, so the source is yours to free immediately.

**`FromSpan()`** — Materialize a borrowed `Span[char]` into a new, owned `String`. Copies the bytes, same as `FromBuffer()`.

`StringBuilder` is mutable text. Interpolation with three or more parts lowers to one, so a ten-part interpolation costs one growable buffer rather than nine intermediate strings. Growth doubles from 16.

**`Append()`** — Append a string.

**`Put()`** — `Append()` returning the builder, so appends chain.

**`StringBuilder.ToString()`** — Snapshot the buffer into a new `String`. The builder stays usable and later appends do not affect the snapshot.

**`StringBuilder.Clear()`** — Reset the length, keep the buffer.

### RETURN VALUE

`IndexOfChar()`, `IndexOf()` and `LastIndexOf()` return -1 if absent.

`CompareTo()` returns negative, zero or positive. Null sorts first.

`PadLeft()` and `PadRight()` return the string unchanged if it is already at least *width* wide. `Repeat(n)` returns `""` for `n <= 0`.

`Split()` with a null or empty *sep* returns a single-element list holding the whole string.

`Append()` treats null and `""` as no-ops.

### NOTES

There is no `[]=`. A string you were handed may be one of the shared static literal objects, and writing through the reference would corrupt every alias. Build text with `StringBuilder`.

`String` is not iterable with `for..in`: the protocol wants `Get(int)` and `String` spells it `CharAt()`. Walk it with an index.

`==` compares contents, never buffer identity. Comparing against the `null` literal is a pointer check and never reaches the operator.

`+` with a string on either side is always concatenation, with the other side converted; a user `+` on the other operand does not intercept it.

A class used in an interpolation needs its own `String func ToString()`; without one it is an error naming that signature.

### SEE ALSO

[char(3)](#char3), [format(3)](#format3), [console(3)](#console3), [int(3)](#int3), [long(3)](#long3), [span(3)](#span3)

---

## sync(3)

### NAME

SpinLock, AtomicInt — locks and atomics

### LIBRARY

libgata (`Sync.g`)

### SYNOPSIS

```go
import Sync;

class SpinLock

public void func Lock()
public bool func TryLock()
public void func Unlock()

class AtomicInt

public int64 func Get()
public void  func Set(int64 v)
public int64 func Add(int64 delta)
public int64 func Increment()
public int64 func Decrement()
public bool  func CompareExchange(int64 expected, int64 desired)
```

### DESCRIPTION

Each is a `volatile` word plus native methods over the compiler's atomic builtins. Neither allocates beyond the object itself.

**`Lock()`** — Acquire, spinning with a scheduler yield per failed attempt, so a contended lock does not starve its holder on one core.

**`TryLock()`** — One attempt. Never spins.

**`Unlock()`** — Release.

`AtomicInt` is a 64-bit counter whose operations are single indivisible instructions with sequentially-consistent ordering. A fresh one starts at zero.

**`Add()`**, **`Increment()`**, **`Decrement()`** — Update and return the new value.

**`CompareExchange()`** — Set the value to *desired* only if it currently equals *expected*.

### RETURN VALUE

`TryLock()` and `CompareExchange()` return whether they succeeded.

### NOTES

`SpinLock` is not reentrant; locking twice from one thread deadlocks. There is no ownership check, so unlocking a lock you do not hold is an uncaught bug. Pair with `defer`.

Nothing else in this library is thread-safe. Two threads sharing a container need one of these around it.

### EXAMPLES

```go
lock.Lock();
defer lock.Unlock();

let old = counter.Get();
while (!counter.CompareExchange(old, old + 1)) { old = counter.Get(); }
```

### SEE ALSO

[sys(3)](#sys3), [time(3)](#time3)

---

## sys(3)

### NAME

Sys, Process, Thread — process and machine control

### LIBRARY

libgata (`Sys.g`)

### SYNOPSIS

```go
import Sys;

native type Process
native type Thread

module Sys

public void func Yield()
public void func Sleep(int ms)
public void func Exit()
public void func Shutdown()
public void func Reboot()

public int    func Argc()
public String func Arg(int i)
```

### DESCRIPTION

**`Yield()`** — Give up the CPU to other threads voluntarily.

**`Sleep()`** — Sleep for at least *ms* milliseconds. Not a precise timer.

**`Exit()`** — Terminate the current userspace process.

**`Shutdown()`**, **`Reboot()`** — Power off or restart. Neither returns on success; on a hosted build both end the process.

`Process` and `Thread` are opaque handles with no Gata-visible fields, which the compiler resolves to a bare pointer. You do not construct them; the generated launcher does, from the `process` and `thread` declarations in your realms.

**`Argc()`** — The process's argument count, `argv[0]` (the program name) included. Hosted only: a batch process has argv, a kernel does not, so a GatOS environment binds no `_env_argc`/`_env_argv` at all. Calling `Argc()`/`Arg()` from a `kernel` realm fails at `appa check`, before it ever reaches C, naming exactly what's missing:

```
<environment>: error[G020]: the active environment's @preamble provides no definition of '_env_argc'; add one
<environment>: error[G020]: the active environment's @preamble provides no definition of '_env_argv'; add one
```

That's the same unbound-floor diagnostic every other capability an environment doesn't provide gets - not a special case, just what `Sys.g`'s ordinary `@extern` declarations plus `ValidateFloor` already do for a call with nothing behind it.

**`Arg()`** — Argument *i*, or an empty string if *i* is out of range.

### RETURN VALUE

`Sleep()` treats a negative *ms* as zero. `Exit()` is a no-op in the kernel realm, where there is no process to end.

### NOTES

`Argc()`/`Arg()` read two globals (`gata_argc`, `gata_argv`) that a Hosted build's generated `main(int argc, char** argv)` populates before anything else runs - unconditionally, for every Hosted build, not gated on whether the program actually reads them back. There is nothing to gate: `main()` with this shape is only ever emitted for a pure Hosted build in the first place, so a GatOS image never carries it regardless.

### SEE ALSO

[time(3)](#time3), [sync(3)](#sync3)

---

## time(3)

### NAME

Time — the monotonic clock

### LIBRARY

libgata (`Time.g`)

### SYNOPSIS

```go
import Time;

module Time

public int64 func Nanos()
public int64 func Millis()
```

### DESCRIPTION

**`Nanos()`** — Nanoseconds since boot, or since the Unix epoch on a hosted build.

**`Millis()`** — The same in milliseconds.

On GatOS the clock is monotonic: it never goes backward and is not adjustable.

### NOTES

Reading the clock links timers and the interrupt machinery into a GatOS image. `new Random()` reads it too.

Measure with a difference, not an absolute.

### EXAMPLES

```go
let start = Time.Millis();
DoWork();
Console.PrintLine($"took {Time.Millis() - start} ms");
```

### SEE ALSO

[random(3)](#random3), [sys(3)](#sys3)

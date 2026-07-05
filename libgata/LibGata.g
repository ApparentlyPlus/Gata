// LibGata.g — libgata entry point.
// `import LibGata;` pulls in the full core standard library.
//
// Sibling modules are referenced by unquoted name, so they resolve from the
// libgata dir (wherever appa installed it), not from the user's project root.
// Symbol collection is global, so import order is not load-bearing — this order
// just documents the dependency direction (String/Char are the foundation).

// The platform layer (#includes, alloc macros, wrappers, boot) is supplied by the
// active target, not imported here — see envs/env.GatOS.g / envs/env.hosted.g.
import Runtime;  // ARC runtime: obj header + retain/release/obj_init (@intrinsic)
import Mem;      // memory engine: alloc (@intrinsic) / free / Mem.Copy / Mem.StrLen
import String;   // the String type, its `+` operator, and str_literal
import Char;     // char classification/conversion
import Int;      // Int / Long / Bool conversions and parsing
import Math;     // Math — floating point
import Format;   // value→text with printf specs (stringify_float)
import Console;  // text I/O and screen control
import Sys;      // process / scheduler control
import Misc;     // kernel boot/startup utilities (e.g. the startup banner)

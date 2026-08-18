/*
 * Manifest.g - NOT PORTED: reads a project's .gconf into a Manifest (Target/Mode/ProjectName/...)
 *
 * Corresponds to Appa/src/CLI/Manifest.cs. needs a small flat-element parser first - .gconf is XML, but only ever a flat <appa> root with unnested, attribute-free, text-only children; see selfhost.txt section 2.6. Not a general XML library.
 */

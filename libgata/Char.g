// Char.g — classification and conversion for the `char` type.
//
// Pure Gata: every function is a small total function of its argument. ASCII only.

import String;

module Char {
    // '0'..'9'
    public bool func IsDigit(char c) {
        return c >= '0' && c <= '9';
    }

    // 'a'..'z' or 'A'..'Z'
    public bool func IsLetter(char c) {
        return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z');
    }

    // A letter or a digit.
    public bool func IsLetterOrDigit(char c) {
        return Char.IsLetter(c) || Char.IsDigit(c);
    }

    // '0'..'9', 'a'..'f' or 'A'..'F'
    public bool func IsHexDigit(char c) {
        return Char.IsDigit(c) || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');
    }

    // Space, tab, newline, carriage return, vertical tab or form feed.
    public bool func IsWhitespace(char c) {
        return c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == 11 || c == 12;
    }

    // 'A'..'Z'
    public bool func IsUpper(char c) {
        return c >= 'A' && c <= 'Z';
    }

    // 'a'..'z'
    public bool func IsLower(char c) {
        return c >= 'a' && c <= 'z';
    }

    // Uppercase a lowercase letter; other characters are returned unchanged.
    public char func ToUpper(char c) {
        if (Char.IsLower(c)) { return (c - 32) as char; }
        return c;
    }

    // Lowercase an uppercase letter; other characters are returned unchanged.
    public char func ToLower(char c) {
        if (Char.IsUpper(c)) { return (c + 32) as char; }
        return c;
    }

    public int func ToInt(char c) {
        return c as int;
    }

    // -1 if `c` is not '0'..'9'.
    public int func DigitValue(char c) {
        if (Char.IsDigit(c)) { return (c - '0') as int; }
        return -1;
    }

    public String func ToString(char c) {
        return String.FromChar(c);
    }
}

/*
 * Char.g - Classification and conversion for the char type
 *
 * Author: u/ApparentlyPlus
 */

module Char {
    /*
     * IsDigit - True for '0'..'9'
     */
    public bool func IsDigit(char c) {
        return c >= '0' && c <= '9';
    }

    /*
     * IsLetter - True for 'a'..'z' or 'A'..'Z'
     */
    public bool func IsLetter(char c) {
        return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z');
    }

    /*
     * IsLetterOrDigit - True for a letter or a digit
     */
    public bool func IsLetterOrDigit(char c) {
        return Char.IsLetter(c) || Char.IsDigit(c);
    }

    /*
     * IsHexDigit - True for '0'..'9', 'a'..'f' or 'A'..'F'
     */
    public bool func IsHexDigit(char c) {
        return Char.IsDigit(c) || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');
    }

    /*
     * IsWhitespace - True for space, tab, newline, CR, vertical tab or form feed
     */
    public bool func IsWhitespace(char c) {
        return c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == 11 || c == 12;
    }

    /*
     * IsUpper - True for 'A'..'Z'
     */
    public bool func IsUpper(char c) {
        return c >= 'A' && c <= 'Z';
    }

    /*
     * IsLower - True for 'a'..'z'
     */
    public bool func IsLower(char c) {
        return c >= 'a' && c <= 'z';
    }

    /*
     * ToUpper - Uppercase a lowercase letter; other characters pass through unchanged
     */
    public char func ToUpper(char c) {
        if (Char.IsLower(c)) { return (c - 32) as char; }
        return c;
    }

    /*
     * ToLower - Lowercase an uppercase letter; other characters pass through unchanged
     */
    public char func ToLower(char c) {
        if (Char.IsUpper(c)) { return (c + 32) as char; }
        return c;
    }

    /*
     * DigitValue - Numeric value of a decimal digit, or -1 if c is not '0'..'9'
     */
    public int func DigitValue(char c) {
        if (Char.IsDigit(c)) { return (c - '0') as int; }
        return -1;
    }
}

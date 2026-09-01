/*
 * Lexer.g - tokenizer: source text to a flat token stream
 *
 * Ports Appa/src/Syntax/Lexer.cs.
 */

import "selfhostlib/String.g";
import "selfhostlib/List.g";
import "selfhostlib/Map.g";
import "src/Diagnostics/TextSpan.g";
import "src/Diagnostics/Diagnostic.g";
import "src/Syntax/Token.g";

/*
 * Converts a Gata source string into a flat list of tokens.
 */
class Lexer {
    String src;
    int pp;
    int ts;
    List[Token] tokens;
    StringMap[TK] kw;
    public ParseError lastErr;

    func _init(String source) {
        self.src = source;
        self.pp = 0;
        self.ts = 0;
        self.tokens = new List[Token]();
        self.kw = new StringMap[TK]();
        self.lastErr = PErr.Nothing();

        self.kw.Put("import", TK.Import);
        self.kw.Put("realm", TK.Realm);
        self.kw.Put("kernel", TK.Kernel);
        self.kw.Put("userspace", TK.Userspace);
        self.kw.Put("foreground", TK.Foreground);
        self.kw.Put("background", TK.Background);
        self.kw.Put("class", TK.Class);
        self.kw.Put("enum", TK.Enum);
        self.kw.Put("module", TK.Module);
        self.kw.Put("func", TK.Func);
        self.kw.Put("static", TK.Static);
        self.kw.Put("public", TK.Public);
        self.kw.Put("private", TK.Private);
        self.kw.Put("entry", TK.Entry);
        self.kw.Put("throws", TK.Throws);
        self.kw.Put("operator", TK.Operator);
        self.kw.Put("as", TK.As);
        self.kw.Put("fields", TK.Fields);
        self.kw.Put("ref", TK.Ref);
        self.kw.Put("return", TK.Return);
        self.kw.Put("if", TK.If);
        self.kw.Put("else", TK.Else);
        self.kw.Put("while", TK.While);
        self.kw.Put("for", TK.For);
        self.kw.Put("in", TK.In);
        self.kw.Put("switch", TK.Switch);
        self.kw.Put("case", TK.Case);
        self.kw.Put("break", TK.Break);
        self.kw.Put("continue", TK.Continue);
        self.kw.Put("debug", TK.Debug);
        self.kw.Put("panic", TK.Panic);
        self.kw.Put("try", TK.Try);
        self.kw.Put("catch", TK.Catch);
        self.kw.Put("new", TK.New);
        self.kw.Put("let", TK.Let);
        self.kw.Put("null", TK.Null);
        self.kw.Put("unsafe", TK.Unsafe);
        self.kw.Put("throw", TK.Throw);
        self.kw.Put("sizeof", TK.Sizeof);
        self.kw.Put("default", TK.Default);
        self.kw.Put("defer", TK.Defer);
        self.kw.Put("match", TK.Match);
        self.kw.Put("union", TK.Union);
        self.kw.Put("assign", TK.Assign);
        self.kw.Put("bool", TK.TBool);
        self.kw.Put("int", TK.TInt);
        self.kw.Put("char", TK.TChar);
        self.kw.Put("float", TK.TFloat);
        self.kw.Put("double", TK.TDouble);
        self.kw.Put("short", TK.TShort);
        self.kw.Put("void", TK.TVoid);

        // Width-explicit family
        self.kw.Put("int64", TK.TPrim);
        self.kw.Put("uint", TK.TPrim);
        self.kw.Put("uint64", TK.TPrim);
        self.kw.Put("ushort", TK.TPrim);
        self.kw.Put("byte", TK.TPrim);
        self.kw.Put("sbyte", TK.TPrim);
        self.kw.Put("usize", TK.TPrim);
        self.kw.Put("uintptr", TK.TPrim);

        self.kw.Put("true", TK.BoolLit);
        self.kw.Put("false", TK.BoolLit);
    }

    /*
     * Tokenize - Tokenizes the whole source, ending with an EOF token the parser can look at safely
     */
    public throws List[Token] func Tokenize() {
        while (self.pp < self.src.Length()) { self.ReadOne(); }
        self.tokens.Add(Token.Tok(TK.EOF, "", TextSpan.Span(self.src.Length(), 0)));
        return self.tokens;
    }

    char func CurChar() { return self.src.CharAt(self.pp); }
    char func PeekChar() { return self.src.CharAt(self.pp + 1); }
    char func PeekCharN(int n) { return self.src.CharAt(self.pp + n); }
    void func Advance() { self.pp = self.pp + 1; }
    void func Advance(int n) { self.pp = self.pp + n; }

    void func Emit(TK kind, String value) {
        self.tokens.Add(Token.Tok(kind, value, TextSpan.Span(self.ts, self.pp - self.ts)));
    }

    /*
     * ErrSpan - The span a failure at the current position points at: the token so far, never
     * narrower than one character (C#'s Math.Max(1, _pp - _ts))
     */
    TextSpan func ErrSpan() {
        let int len = (self.pp - self.ts) > 1 ? (self.pp - self.ts) : 1;
        return TextSpan.Span(self.ts, len);
    }

    throws void func Fail(String m, String code) {
        self.lastErr = PErr.Make(self.ErrSpan(), code, m);
        throw;
    }

    throws void func FailHint(String m, String code, List[String] hints) {
        self.lastErr = ParseError.At(self.ErrSpan(), code, m, hints);
        throw;
    }

    /*
     * ReadOne - Reads the next token from the source string and adds it to the token list
     */
    throws void func ReadOne() {
        if (IsWhiteSpace(self.CurChar())) { self.Advance(); return; }

        if (self.CurChar() == '/' && self.PeekChar() == '/') {
            while (self.pp < self.src.Length() && self.CurChar() != '\n') { self.Advance(); }
            return;
        }

        if (self.CurChar() == '/' && self.PeekChar() == '*') {
            self.ts = self.pp;
            self.Advance(2);
            while (self.pp < self.src.Length() - 1 && !(self.CurChar() == '*' && self.PeekChar() == '/')) {
                self.Advance();
            }
            if (!(self.CurChar() == '*' && self.PeekChar() == '/')) {
                self.Fail("unterminated block comment; missing closing '*/'", Codes.UnterminatedLiteral());
            }
            self.Advance(2);
            return;
        }

        self.ts = self.pp;

        // Annotations like @intrinsic(role)  @preamble(target)  @extern  @environment  @keep
        if (self.CurChar() == '@') {
            self.Advance();
            let int start = self.pp;
            while (self.pp < self.src.Length() && IsIdentPart(self.CurChar())) { self.Advance(); }
            let String nn = self.src.Substring(start, self.pp - start);

            if (nn == "intrinsic") { let String arg = self.ReadParenArg("@intrinsic"); self.Emit(TK.AtIntrinsic, arg); return; }
            if (nn == "preamble") { let String arg = self.ReadParenArg("@preamble"); self.Emit(TK.AtPreamble, arg); return; }
            if (nn == "extern") { self.Emit(TK.AtExtern, "@extern"); return; }
            if (nn == "environment") { self.Emit(TK.AtEnvironment, "@environment"); return; }
            if (nn == "keep") { self.Emit(TK.AtKeep, "@keep"); return; }
            if (nn == "shadows") { self.Emit(TK.AtShadows, "@shadows"); return; }
            if (nn == "builtin") { let String arg = self.ReadParenArg("@builtin"); self.Emit(TK.AtBuiltin, arg); return; }

            self.Fail("unknown annotation '@" + nn + "'; expected '@intrinsic', '@preamble', " +
                      "'@extern', '@environment', '@keep', '@builtin', or '@shadows'", Codes.BadAnnotation());
            return;
        }

        // native { }  or  native type Name { }
        if (self.MatchKw("native")) {
            let int start = self.pp; self.Advance(6); self.SkipWS();
            if (self.CurChar() == '{') { let String body = self.ReadBalanced(); self.Emit(TK.NativeContent, body); return; }

            if (self.MatchKw("type")) {
                self.Advance(4); self.SkipWS();
                let int ns = self.pp;
                while (self.pp < self.src.Length() && IsIdentPart(self.CurChar())) { self.Advance(); }
                let String tname = self.src.Substring(ns, self.pp - ns);
                self.SkipWS();
                if (self.CurChar() == '{' && tname.Length() > 0) {
                    let String body = self.ReadBalanced();
                    self.Emit(TK.NativeTypeDecl, tname + String.FromChar(31 as char) + body);
                    return;
                }
            }

            self.pp = start;
            self.ReadID();
            return;
        }

        // fields { }
        if (self.MatchKw("fields")) {
            let int start = self.pp; self.Advance(6); self.SkipWS();
            if (self.CurChar() != '{') { self.pp = start; self.ReadID(); return; }
            let String fbody = self.ReadBalanced();
            self.Emit(TK.Fields, fbody);
            return;
        }

        if (IsIDStart(self.CurChar())) { self.ReadID(); return; }
        if (self.CurChar() == '$' && self.PeekChar() == '"') { self.ReadInterp(); return; }
        if (self.CurChar() == '"') { let String slit = self.ReadString(); self.Emit(TK.StrLit, slit); return; }
        if (self.CurChar() == '\'') { self.ReadCharLit(); return; }
        if (self.CurChar() >= '0' && self.CurChar() <= '9') { self.ReadNumber(); return; }

        // Compound assignment and multi-character operators, longest match first.
        if (self.CurChar() == '+') {
            if (self.PeekChar() == '=') { self.Advance(2); self.Emit(TK.PlusEq, "+="); return; }
            if (self.PeekChar() == '+') { self.Advance(2); self.Emit(TK.Inc, "++"); return; }
        } else if (self.CurChar() == '-') {
            if (self.PeekChar() == '=') { self.Advance(2); self.Emit(TK.MinusEq, "-="); return; }
            if (self.PeekChar() == '>') { self.Advance(2); self.Emit(TK.Arrow, "->"); return; }
            if (self.PeekChar() == '-') { self.Advance(2); self.Emit(TK.Dec, "--"); return; }
        } else if (self.CurChar() == '*') {
            if (self.PeekChar() == '=') { self.Advance(2); self.Emit(TK.StarEq, "*="); return; }
        } else if (self.CurChar() == '/') {
            if (self.PeekChar() == '=') { self.Advance(2); self.Emit(TK.SlashEq, "/="); return; }
        } else if (self.CurChar() == '%') {
            if (self.PeekChar() == '=') { self.Advance(2); self.Emit(TK.PercentEq, "%="); return; }
        } else if (self.CurChar() == '&') {
            if (self.PeekChar() == '=') { self.Advance(2); self.Emit(TK.AmpEq, "&="); return; }
            if (self.PeekChar() == '&') { self.Advance(2); self.Emit(TK.And, "&&"); return; }
        } else if (self.CurChar() == '|') {
            if (self.PeekChar() == '=') { self.Advance(2); self.Emit(TK.PipeEq, "|="); return; }
            if (self.PeekChar() == '|') { self.Advance(2); self.Emit(TK.Or, "||"); return; }
        } else if (self.CurChar() == '^') {
            if (self.PeekChar() == '=') { self.Advance(2); self.Emit(TK.CaretEq, "^="); return; }
        } else if (self.CurChar() == '=') {
            if (self.PeekChar() == '=') { self.Advance(2); self.Emit(TK.EqEq, "=="); return; }
            self.Advance(); self.Emit(TK.Eq, "="); return;
        } else if (self.CurChar() == '!') {
            if (self.PeekChar() == '=') { self.Advance(2); self.Emit(TK.NotEq, "!="); return; }
        } else if (self.CurChar() == '<') {
            if (self.PeekChar() == '<') {
                if (self.PeekCharN(2) == '=') { self.Advance(3); self.Emit(TK.ShlEq, "<<="); return; }
                self.Advance(2); self.Emit(TK.Shl, "<<"); return;
            }
            if (self.PeekChar() == '=') { self.Advance(2); self.Emit(TK.LtEq, "<="); return; }
        } else if (self.CurChar() == '>') {
            if (self.PeekChar() == '>') {
                if (self.PeekCharN(2) == '=') { self.Advance(3); self.Emit(TK.ShrEq, ">>="); return; }
                self.Advance(2); self.Emit(TK.Shr, ">>"); return;
            }
            if (self.PeekChar() == '=') { self.Advance(2); self.Emit(TK.GtEq, ">="); return; }
        } else if (self.CurChar() == ':') {
            if (self.PeekChar() == ':') { self.Advance(2); self.Emit(TK.ColonColon, "::"); return; }
        }

        // Single character punctuation fallthrough
        let char c = self.CurChar();
        self.Advance();
        if (c == '(') { self.Emit(TK.LParen, "("); return; }
        if (c == ')') { self.Emit(TK.RParen, ")"); return; }
        if (c == '{') { self.Emit(TK.LBrace, "{"); return; }
        if (c == '}') { self.Emit(TK.RBrace, "}"); return; }
        if (c == '[') { self.Emit(TK.LBrack, "["); return; }
        if (c == ']') { self.Emit(TK.RBrack, "]"); return; }
        if (c == ';') { self.Emit(TK.Semi, ";"); return; }
        if (c == ',') { self.Emit(TK.Comma, ","); return; }
        if (c == ':') { self.Emit(TK.Colon, ":"); return; }
        if (c == '.') { self.Emit(TK.Dot, "."); return; }
        self.Emit(TK.Punct, String.FromChar(c));
    }

    /*
     * MatchKw - True when the next characters in src spell exactly word and are not followed by a
     * letter, digit, or underscore (ie. it is a complete word boundary)
     */
    bool func MatchKw(String word) {
        let int n = word.Length();
        if (self.pp + n > self.src.Length()) { return false; }
        let int i = 0;
        while (i < n) {
            if (self.src.CharAt(self.pp + i) != word.CharAt(i)) { return false; }
            i = i + 1;
        }
        let int after = self.pp + n;
        if (after >= self.src.Length()) { return true; }
        return !IsIdentPart(self.src.CharAt(after));
    }

    /*
     * SkipWS - Consumes whitespace characters starting from the current position in the source
     */
    void func SkipWS() { while (self.pp < self.src.Length() && IsWhiteSpace(self.CurChar())) { self.Advance(); } }

    /*
     * ReadParenArg - Reads the required (identifier) argument after an annotation keyword, like @intrinsic(retain).
     */
    throws String func ReadParenArg(String ann) {
        self.SkipWS();
        if (self.CurChar() != '(') {
            self.FailHint("'" + ann + "' requires a parenthesized argument", Codes.BadAnnotation(), HintList.Of1("e.g. " + ann + "(name)"));
        }
        self.Advance();
        self.SkipWS();
        let int s = self.pp;

        while (self.pp < self.src.Length() && IsIdentPart(self.CurChar())) { self.Advance(); }
        let String arg = self.src.Substring(s, self.pp - s);
        if (arg.Length() == 0) {
            self.FailHint("'" + ann + "' argument must be a name", Codes.BadAnnotation(), HintList.Of1("e.g. " + ann + "(name)"));
        }
        self.SkipWS();
        if (self.CurChar() != ')') {
            self.Fail("missing ')' after '" + ann + "(" + arg + "'", Codes.BadAnnotation());
        }
        self.Advance();
        return arg;
    }

    /*
     * ReadBalanced - Reads a balanced block of text enclosed in braces '{' and '}'. 
     */
    throws String func ReadBalanced() {
        self.Advance(); // opening {
        let int start = self.pp;
        let int depth = 1;
        while (self.pp < self.src.Length() && depth > 0) {
            let char cur = self.CurChar();
            let char peek = self.PeekChar();

            if (cur == '/' && peek == '/') {
                while (self.pp < self.src.Length() && self.CurChar() != '\n') { self.Advance(); }
            } else if (cur == '/' && peek == '*') {
                self.Advance(2);
                while (self.pp < self.src.Length() && !(self.CurChar() == '*' && self.PeekChar() == '/')) {
                    self.Advance();
                }
                if (self.pp < self.src.Length()) { self.Advance(2); }
            } else if (cur == '"' || cur == '\'') {
                let char quote = cur;
                self.Advance();
                while (self.pp < self.src.Length() && self.CurChar() != quote) {
                    if (self.CurChar() == '\\' && self.pp + 1 < self.src.Length()) { self.Advance(); }
                    self.Advance();
                }
                if (self.pp < self.src.Length()) { self.Advance(); }
            } else if (cur == '{') {
                depth = depth + 1; self.Advance();
            } else if (cur == '}') {
                depth = depth - 1; self.Advance();
            } else {
                self.Advance();
            }
        }

        if (depth > 0) { self.Fail("Unterminated native block, missing closing '}'", Codes.UnterminatedLiteral()); }
        return self.src.Substring(start, (self.pp - 1) - start);
    }

    /*
     * ReadID - Reads an identifier or keyword from the source string starting at the current position
     */
    void func ReadID() {
        let int start = self.pp;
        while (self.pp < self.src.Length() && IsIdentPart(self.CurChar())) { self.Advance(); }
        let String text = self.src.Substring(start, self.pp - start);

        let TK kind = TK.Ident;
        if (self.kw.TryGet(text, ref kind)) {
            self.Emit(kind, text);
        } else {
            self.Emit(TK.Ident, text);
        }
    }

    /*
     * ReadNumber - Reads a numeric literal: hex (0x...), integer, or float with optional suffix.
     */
    throws void func ReadNumber() {
        let int start = self.pp;

        if (self.CurChar() == '0' && (self.PeekChar() == 'x' || self.PeekChar() == 'X')) {
            self.Advance(2);
            let int digits = self.pp;
            while (self.pp < self.src.Length() && IsHexDigit(self.CurChar())) { self.Advance(); }
            if (self.pp == digits) { self.Fail("hex literal '0x' has no digits", Codes.BadNumber()); }
            self.ReadIntSuffix();
            if (IsIdentPart(self.CurChar())) {
                self.Fail("invalid character '" + (self.CurChar() as String) + "' in hex literal", Codes.BadNumber());
            }
            self.Emit(TK.IntLit, self.src.Substring(start, self.pp - start));
            return;
        }

        while (self.pp < self.src.Length() && self.CurChar() >= '0' && self.CurChar() <= '9') { self.Advance(); }

        let bool isFloat = false;

        if (self.CurChar() == '.' && self.PeekChar() >= '0' && self.PeekChar() <= '9') {
            isFloat = true;
            self.Advance();
            while (self.pp < self.src.Length() && self.CurChar() >= '0' && self.CurChar() <= '9') { self.Advance(); }
        }

        if ((self.CurChar() == 'e' || self.CurChar() == 'E') &&
            ((self.PeekChar() >= '0' && self.PeekChar() <= '9') ||
             ((self.PeekChar() == '+' || self.PeekChar() == '-') && self.PeekCharN(2) >= '0' && self.PeekCharN(2) <= '9'))) {
            isFloat = true;
            self.Advance();
            if (self.CurChar() == '+' || self.CurChar() == '-') { self.Advance(); }
            while (self.pp < self.src.Length() && self.CurChar() >= '0' && self.CurChar() <= '9') { self.Advance(); }
        }

        if (isFloat) {
            if (self.CurChar() == 'f' || self.CurChar() == 'F') { self.Advance(); } // single-precision suffix
            if (IsIdentPart(self.CurChar())) {
                self.Fail("invalid suffix on float literal (found '" + (self.CurChar() as String) +
                          "' after '" + self.src.Substring(start, self.pp - start) + "')", Codes.BadNumber());
            }
            self.Emit(TK.FloatLit, self.src.Substring(start, self.pp - start));
        } else {
            self.ReadIntSuffix();
            if (IsIdentPart(self.CurChar())) {
                self.Fail("invalid suffix on integer literal (found '" + (self.CurChar() as String) +
                          "' after '" + self.src.Substring(start, self.pp - start) + "')", Codes.BadNumber());
            }
            self.Emit(TK.IntLit, self.src.Substring(start, self.pp - start));
        }
    }

    /*
     * ReadIntSuffix - Consumes a trailing integer suffix: any run of u/U/l/L (e.g. ULL, u, L)
     */
    void func ReadIntSuffix() {
        while (self.pp < self.src.Length() &&
               (self.CurChar() == 'u' || self.CurChar() == 'U' || self.CurChar() == 'l' || self.CurChar() == 'L')) {
            self.Advance();
        }
    }

    /*
     * ReadInterp - Reads an interpolated string $"...{expr}..." as a sequence of distinct tokens.
     */
    throws void func ReadInterp() {
        self.Advance(2); // consume $"
        self.Emit(TK.InterpStrStart, "$\"");

        while (self.pp < self.src.Length() && self.CurChar() != '"' && self.CurChar() != '\n') {
            if (self.CurChar() == '{' && self.PeekChar() != '{') {
                self.ts = self.pp; self.Advance();
                self.Emit(TK.Punct, "{");

                let int brdepth = 1;
                while (self.pp < self.src.Length() && brdepth > 0) {
                    if (IsWhiteSpace(self.CurChar())) { self.Advance(); }
                    else {
                        if (self.CurChar() == '{') { brdepth = brdepth + 1; }
                        else if (self.CurChar() == '}') {
                            brdepth = brdepth - 1;
                            if (brdepth == 0) { break; } // don't let ReadOne consume the final '}'
                        }
                        self.ReadOne(); // ordinary tokens, recursively
                    }
                }

                if (brdepth > 0) { self.Fail("unterminated '{' in interpolated string", Codes.UnterminatedLiteral()); }

                self.ts = self.pp; self.Advance();
                self.Emit(TK.Punct, "}");
            } else {
                self.ts = self.pp;
                let int start = self.pp;
                let StringBuilder sb = new StringBuilder();
                let bool usedSb = false;
                while (self.pp < self.src.Length() && self.CurChar() != '"' && self.CurChar() != '\n' &&
                       !(self.CurChar() == '{' && self.PeekChar() != '{')) {
                    if (self.CurChar() == '{' && self.PeekChar() == '{') {
                        sb.Append(self.src.Substring(start, self.pp - start)); usedSb = true;
                        self.Advance(2); sb.AppendChar('{'); start = self.pp;
                    } else if (self.CurChar() == '}' && self.PeekChar() == '}') {
                        sb.Append(self.src.Substring(start, self.pp - start)); usedSb = true;
                        self.Advance(2); sb.AppendChar('}'); start = self.pp;
                    } else if (self.CurChar() == '\\') {
                        self.Advance();
                        if (self.pp >= self.src.Length()) { break; }
                        let char ev = '\0';
                        if (!TryEscape(self.CurChar(), ref ev)) {
                            self.Fail("unrecognized escape '\\" + (self.CurChar() as String) + "' in interpolated string", Codes.BadEscape());
                        }
                        self.Advance();
                    } else { self.Advance(); }
                }
                let String content = usedSb
                    ? sb.Put(self.src.Substring(start, self.pp - start)).ToString()
                    : self.src.Substring(start, self.pp - start);
                self.Emit(TK.StrLit, "\"" + content + "\"");
            }
        }

        if (self.CurChar() != '"') { self.Fail("unterminated interpolated string", Codes.UnterminatedLiteral()); }

        self.ts = self.pp; self.Advance();
        self.Emit(TK.InterpStrEnd, "\"");
    }

    /*
     * ReadString - Reads a string literal from the source string starting at the current position
     */
    throws String func ReadString() {
        let int start = self.pp;
        self.Advance(); // opening "

        while (self.pp < self.src.Length() && self.CurChar() != '"' && self.CurChar() != '\n') {
            if (self.CurChar() == '\\') {
                self.Advance();
                if (self.pp >= self.src.Length()) { break; }
                let char ev = '\0';
                if (!TryEscape(self.CurChar(), ref ev)) {
                    self.Fail("unrecognized escape '\\" + (self.CurChar() as String) + "' in string literal", Codes.BadEscape());
                }
                self.Advance();
            } else { self.Advance(); }
        }

        if (self.CurChar() != '"') { self.Fail("unterminated string literal", Codes.UnterminatedLiteral()); }
        self.Advance(); // closing "
        return self.src.Substring(start, self.pp - start);
    }

    /*
     * ReadCharLit - Reads a character literal from the source string starting at the current position
     */
    throws void func ReadCharLit() {
        self.Advance(); // opening '
        let char val = '\0';

        if (self.CurChar() == '\\') {
            self.Advance();
            let char e = '\0';
            if (!TryEscape(self.CurChar(), ref e)) {
                self.Fail("unrecognized escape '\\" + (self.CurChar() as String) + "' in char literal", Codes.BadEscape());
            }
            val = e; self.Advance();
        } else if (self.CurChar() == '\'') {
            self.Fail("empty char literal", Codes.UnterminatedLiteral());
        } else if (self.CurChar() == '\n' || self.pp >= self.src.Length()) {
            self.Fail("unterminated char literal", Codes.UnterminatedLiteral());
        } else {
            val = self.CurChar(); self.Advance();
        }

        if (self.CurChar() != '\'') { self.Fail("char literal must hold exactly one character", Codes.UnterminatedLiteral()); }
        self.Advance(); // closing '
        self.Emit(TK.CharLit, (val as int) as String);
    }
}

/*
 * TryEscape - Maps a single escape character to its value. Returns false for unrecognized escapes.
 */
bool func TryEscape(char c, ref char val) {
    if (c == 'n')  { val = '\n'; return true; }
    if (c == 't')  { val = '\t'; return true; }
    if (c == 'r')  { val = '\r'; return true; }
    if (c == '0')  { val = '\0'; return true; }
    if (c == '\'') { val = '\''; return true; }
    if (c == '\\') { val = '\\'; return true; }
    if (c == '"')  { val = '"';  return true; }
    return false;
}

bool func IsWhiteSpace(char c) { return c == ' ' || (c >= '\t' && c <= '\r'); }

bool func IsIDStart(char c) {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_';
}

bool func IsIdentPart(char c) {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_';
}

bool func IsHexDigit(char c) {
    return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');
}

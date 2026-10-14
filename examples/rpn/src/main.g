// rpn: a reverse Polish notation calculator. "3 4 + 2 *" means (3 + 4) * 2.
// Anything that goes wrong (a bad token, too few operands, dividing by zero)
// is a throw, and the caller decides what to do about it.

import Console;
import String;
import Stack;
import Char;
import Int;

union Token {
    Num(int v),
    Op(char c)
}

throws Token func ParseToken(String s) {
    if (s.Length() == 1 && "+-*/%".IndexOfChar(s[0]) >= 0) {
        return Token.Op(s[0]);
    }
    let n = Int.ParseStrict(s);
    return Token.Num(n);
}

throws int func Apply(char op, int a, int b) {
    switch (op as int) {
        case '+' { return a + b; }
        case '-' { return a - b; }
        case '*' { return a * b; }
        case '/', '%' {
            if (b == 0) { throw; }
            return op == '/' ? a / b : a % b;
        }
        default { throw; }
    }
}

throws int func Eval(String src) {
    let st = new Stack[int]();
    let parts = src.Split(" ");
    for (let i = 0; i < parts.Length(); i++) {
        let part = parts[i];
        if (part.IsEmpty()) { continue; }

        let tok = ParseToken(part);
        match (tok) {
            case Num(v) { st.Push(v); }
            case Op(c) {
                let b = st.PopOrThrow();
                let a = st.PopOrThrow();
                let r = Apply(c, a, b);
                st.Push(r);
            }
        }
    }

    // a well formed expression leaves exactly one value behind
    if (st.Length() != 1) { throw; }
    return st.Pop();
}

realm userspace {
    entry func Main() {
        Console.PrintLine("rpn calculator. One expression per line, e.g. 3 4 + 2 *");

        // InputLine throws at end of input, which ends the loop.
        while (true) {
            Console.Print("> ");
            let line = Console.InputLine() catch { break; };
            line = line.Trim();
            if (line.IsEmpty()) { continue; }

            let v = Eval(line) catch {
                Console.PrintLine("  error");
                continue;
            };
            Console.PrintLine($"  = {v}");
        }
        Console.NewLine();
    }
}

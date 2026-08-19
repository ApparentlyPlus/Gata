/*
 * selfhost - proof-of-life for the self-hosting scaffold: exercises File.g and Dir.g end to end
 * against the real filesystem through env.selfhost.g's floor. Stands in for the compiler driver
 * until that gets written.
 */
import "selfhostlib/Console.g";
import "selfhostlib/String.g";
import "selfhostlib/List.g";
import "selfhostlib/Result.g";
import "selfhostlib/File.g";
import "selfhostlib/Dir.g";
import "selfhostlib/Sys.g";
import "selfhostlib/Args.g";
import "src/Syntax/Lexer.g";

realm userspace {
    entry func Main() {
        let String path = "selfhost_scratch.txt";
        let String payload = "hello from a self-hosted appa\n";

        Console.PrintLine("write=" + (File.Write(path, payload) as String));
        Console.PrintLine("exists=" + (File.Exists(path) as String));

        match (File.Read(path)) {
            case Ok(contents) { Console.PrintLine("read=" + contents); }
            case Err(msg)     { Console.PrintLineErr("error=" + msg); }
        }

        let String missing = "selfhost_does_not_exist.txt";
        Console.PrintLine("missing.exists=" + (File.Exists(missing) as String));
        match (File.Read(missing)) {
            case Ok(contents) { Console.PrintLine("missing.read=" + contents); }
            case Err(msg)     { Console.PrintLineErr("missing.error=" + msg); }
        }

        let String dir = "selfhost_scratch_dir";
        Console.PrintLine("mkdir=" + (Dir.MakeDir(dir) as String));
        Console.PrintLine("isdir=" + (Dir.IsDir(dir) as String));

        let String nested = dir + "/nested.txt";
        File.Write(nested, "nested\n");
        let List[String] entries = Dir.List(dir);
        Console.PrintLine("entrycount=" + (entries.Length() as String));
        let int i = 0;
        while (i < entries.Length()) { Console.PrintLine("entry=" + entries.Get(i)); i = i + 1; }

        Console.PrintLine("cwdlen>0=" + ((Dir.Cwd().Length() > 0) as String));

        Console.PrintLine("cleanup=" + (Dir.DeleteRecursive(dir) as String));
        Console.PrintLine("gone=" + (!Dir.IsDir(dir) as String));
        Dir.DeleteFile(path);

        Console.PrintLine("argc=" + (Args.Argc() as String));
        let int a = 0;
        while (a < Args.Argc()) { Console.PrintLine("argv[" + (a as String) + "]=" + Args.Arg(a)); a = a + 1; }

        Sys.Exit(0);

        let Lexer lex = new Lexer("type Foo { bar: int; }");
        let tk = lex.Tokenize() catch { return;};
    }
}

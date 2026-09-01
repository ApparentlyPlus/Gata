/*
 * Layout.g - composing the emitter's sections into the build's translation-unit files
 *
 * Ports Appa/src/Backend/Layout.cs.
 */

import "selfhostlib/String.g";
import "selfhostlib/List.g";
import "selfhostlib/Optional.g";
import "selfhostlib/Int.g";
import "src/IR/Ir.g";
import "src/Semantics/SymbolTable.g";
import "src/Backend/CodeWriter.g";
import "src/Backend/Emitter.g";
import "src/Backend/Finesse.g";
import "selfhostlib/Sha256.g";

/*
 * One named output file produced for a single translation unit.
 */
class OutputFile {
    public String name;
    public String content;
    func _init(String name, String content) { self.name = name; self.content = content; }
}

module Layout {

    /*
     * LauncherName - The C function generated to create every process and spawn its threads.
     */
    public String func LauncherName() { return "uapps"; }

    /*
     * Compose - The emitter output as the set of translation-unit files for this build
     */
    public List[OutputFile] func Compose(EmitOutput o, SymbolTable sym) {
        let Finesse fin = new Finesse(Layout.ContentSeed(o));

        let List[OutputFile] files = new List[OutputFile]();
        files.Add(new OutputFile("shared.h", Layout.SharedHeader(fin, o)));
        let bool launch = o.processes.Length() > 0;

        if (o.hasKernelRealm && o.hasUserRealm) {
            let List[String] krest = new List[String]();
            krest.Add(o.kernelBoot);
            files.Add(new OutputFile("kmain.c", Layout.Concat(fin, "kmain.c", o.kernelPreamble,
                o.kernelTypes, o.kernelFwd, o.kernelFuncs, krest)));

            files.Add(new OutputFile("uproc.c", Layout.Concat(fin, "uproc.c", o.userPreamble,
                o.userTypes, o.userFwd, o.userFuncs, new List[String]())));

            files.Add(new OutputFile("uproc.h", Layout.UprocHeader(fin, o.processes)));
            files.Add(new OutputFile("umain.c", Layout.Launcher(fin, o.processes, sym, true)));
            return files;
        }

        if (o.hasUserRealm) {
            let List[String] urest = new List[String]();
            urest.Add(launch ? Layout.Launcher(fin, o.processes, sym, false) : "");
            urest.Add(Layout.HostedMain(o.userEntryCName, launch));
            files.Add(new OutputFile("program.c", Layout.Concat(fin, "program.c", o.userPreamble,
                o.userTypes, o.userFwd, o.userFuncs, urest)));
            return files;
        }

        if (o.hasKernelRealm) {
            let List[String] krest = new List[String]();
            krest.Add(launch ? Layout.Launcher(fin, o.processes, sym, false) : "");
            krest.Add(o.kernelBoot);
            files.Add(new OutputFile("kmain.c", Layout.Concat(fin, "kmain.c", o.kernelPreamble,
                o.kernelTypes, o.kernelFwd, o.kernelFuncs, krest)));
        }
        return files;
    }

    /*
     * HostedMain - The generated main() for a hosted build.
     */
    String func HostedMain(Optional[String] entryCName, bool launch) {
        let bool hasEntry = false;
        let String entryFn = "";
        match (entryCName) { case Some(e) { hasEntry = true; entryFn = e; } case None { } }
        if (!hasEntry && !launch) { return ""; }

        let CodeWriter w = new CodeWriter();
        w.Block("int main(int argc, char** argv) {");
        w.Line("gata_argc = argc;");
        w.Line("gata_argv = argv;");
        if (launch) { w.Line(Layout.LauncherName() + "();"); }
        if (hasEntry) { w.Line(entryFn + "();"); }
        w.Line("return 0;");
        w.End("}");
        return w.Text();
    }

    /*
     * ContentSeed - A stable SHA-256 of the emitted content, as the header generator's seed.
     */
    int func ContentSeed(EmitOutput o) {
        let Sha256 h = new Sha256();
        h.Append(o.sharedHeader);
        h.Append(o.kernelPreamble);
        h.Append(o.kernelTypes);
        h.Append(o.kernelFwd);
        h.Append(o.kernelFuncs);
        h.Append(o.kernelBoot);
        h.Append(o.userPreamble);
        h.Append(o.userTypes);
        h.Append(o.userFwd);
        h.Append(o.userFuncs);
        return Sha256.SeedFromDigest(h.Digest());
    }

    /*
     * SharedHeader - The shared header, with its pragma-once guard and the emitted shared types
     */
    String func SharedHeader(Finesse fin, EmitOutput o) {
        let CodeWriter w = new CodeWriter();
        w.Line(fin.GenerateKewlHeader("shared.h"));
        w.Line("#pragma once");
        w.Line("");
        w.Line(o.sharedHeader);
        return w.Text();
    }

    /*
     * Concat - Sections into one translation unit, behind a file header comment.
     */
    String func Concat(Finesse fin, String name, String s1, String s2, String s3, String s4,
                       List[String] rest) {
        let StringBuilder sb = new StringBuilder();
        sb.Append(fin.GenerateKewlHeader(name));
        sb.Append("\n");
        sb.Append(s1);
        sb.Append("\n");
        sb.Append(s2);
        sb.Append("\n");
        sb.Append(s3);
        sb.Append("\n");
        sb.Append(s4);
        let int i = 0;
        while (i < rest.Length()) {
            let String section = rest.Get(i);
            if (section.Length() > 0) { sb.Append("\n"); sb.Append(section); }
            i = i + 1;
        }
        return sb.ToString();
    }

    /*
     * UprocHeader - The header forward-declaring every thread entry function
     */
    String func UprocHeader(Finesse fin, List[IrProcess] procs) {
        let CodeWriter w = new CodeWriter();
        w.Line(fin.GenerateKewlHeader("uproc.h"));
        w.Line("#pragma once");
        w.Line("");
        let int i = 0;
        while (i < procs.Length()) {
            let IrProcess p = procs.Get(i);
            let int j = 0;
            while (j < p.threads.Length()) {
                match (p.threads.Get(j).entryFunc) {
                    case Some(e) { w.Line("void " + e.cName + "(void* arg);"); }
                    case None { }
                }
                j = j + 1;
            }
            i = i + 1;
        }
        return w.Text();
    }

    /*
     * Launcher - The userspace launcher that creates processes and spawns their threads through
     * environment bindings, so porting the OS is an edit to env.*.g and never to this file.
     */
    String func Launcher(Finesse fin, List[IrProcess] procs, SymbolTable sym, bool ownUnit) {
        let String procCreate  = sym.FloorName(Roles.EnvProcCreate());
        let String procHide    = sym.FloorName(Roles.EnvProcHide());
        let String threadSpawn = sym.FloorName(Roles.EnvThreadSpawn());

        let CodeWriter w = new CodeWriter();
        if (ownUnit) {
            w.Line(fin.GenerateKewlHeader("umain.c"));
            w.Line("#include \"uproc.h\"");
            w.Line("");
            w.Line("// Topology floor provided by the environment (env.*.g).");
            w.Line("extern void* " + procCreate + "(const char* name);");
            w.Line("extern void  " + procHide + "(void* proc);");
            w.Line("extern void  " + threadSpawn +
                   "(void* proc, const char* name, void (*entry)(void*), int is_user);");
            w.Line("");
        }
        w.Block("void " + Layout.LauncherName() + "(void) {");
        let int i = 0;
        while (i < procs.Length()) {
            let IrProcess proc = procs.Get(i);
            let String handle = "__p" + Int.ToString(i);
            w.Line("void* " + handle + " = " + procCreate + "(\"" + proc.name + "\");");
            if (proc.mode == "background") { w.Line(procHide + "(" + handle + ");"); }
            let int j = 0;
            while (j < proc.threads.Length()) {
                let IrThread th = proc.threads.Get(j);
                match (th.entryFunc) {
                    case Some(e) {
                        let String isUser = e.vis == Visibility.Kernel ? "0" : "1";
                        w.Line(threadSpawn + "(" + handle + ", \"" + th.name + "\", " + e.cName +
                               ", " + isUser + ");");
                    }
                    case None { }
                }
                j = j + 1;
            }
            i = i + 1;
        }
        w.End("}");
        return w.Text();
    }
}

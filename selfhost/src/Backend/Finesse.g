/*
 * Finesse.g - the decorative header comment stamped on top of every emitted file
 *
 * Ports Appa/src/Backend/Finesse.cs.
 */

import "selfhostlib/String.g";
import "selfhostlib/List.g";
import "selfhostlib/Int.g";
import "selfhostlib/NetRandom.g";

class Finesse {
    NetRandom random;

    func _init(int seed) { self.random = new NetRandom(seed); }

    /*
     * Pick - A random element. The only thing in this file that consumes the generator, so the
     * number of Pick calls per template is itself part of the reproducibility contract.
     */
    String func Pick(List[String] values) { return values.Get(self.random.Next(values.Length())); }

    /*
     * Sep - One string repeated.
     */
    public static String func Sep(String c, int width) {
        let StringBuilder sb = new StringBuilder();
        let int i = 0;
        while (i < width) { sb.Append(c); i = i + 1; }
        return sb.ToString();
    }

    public static int func Max2(int a, int b) { return a > b ? a : b; }

    /*
     * GenerateKewlHeader - The header for one output file. 
     */
    public String func GenerateKewlHeader(String fileName) {
        if (self.random.Next(1000) == 0) { return self.LegendaryHeader(fileName); }
        let int which = self.random.Next(16);
        switch (which) {
            case 0  { return self.Card(fileName); }
            case 1  { return self.Terminal(fileName); }
            case 2  { return self.AiAwakening(fileName); }
            case 3  { return self.AncientArtifact(fileName); }
            case 4  { return self.LoadingScreen(fileName); }
            case 5  { return self.Demoscene(fileName); }
            case 6  { return self.Propaganda(fileName); }
            case 7  { return self.SpaceMission(fileName); }
            case 8  { return self.ProgrammerThoughts(fileName); }
            case 9  { return self.Mythological(fileName); }
            case 10 { return self.Bureaucratic(fileName); }
            case 11 { return self.WeatherReport(fileName); }
            case 12 { return self.GameOver(fileName); }
            case 13 { return self.NightLog(fileName); }
            case 14 { return self.StatusBoard(fileName); }
            default { return self.WarningLabel(fileName); }
        }
    }

    /*
     * Taglines - 45 entries, in declaration order.
     */
    List[String] func Taglines() {
        let List[String] r = new List[String]();
        r.Add("The flying bison from Avatar");
        r.Add("The world's leading source-to-source sky bison");
        r.Add("The last sourcebender");
        r.Add("The AST shepherd");
        r.Add("The world's first bison-driven compiler pipeline");
        r.Add("The build system's favorite mammal");
        r.Add("A large airborne mammal with strong opinions about syntax");
        r.Add("The four-nation-approved transpiler");
        r.Add("The bridge between Gata and C");
        r.Add("The reason this file exists");
        r.Add("The reason this file unfortunately exists");
        r.Add("The thing that turned Gata into this");
        r.Add("The proud owner of this comment");
        r.Add("The source relocation specialist");
        r.Add("The token wrangler");
        r.Add("The AST whisperer");
        r.Add("The source code ferryman");
        r.Add("A professional code relocator");
        r.Add("The parser's emotional support animal");
        r.Add("The transpiler formerly known as Appa");
        r.Add("The linker's best friend");
        r.Add("The linker's worst enemy");
        r.Add("The thing standing between your code and a segfault");
        r.Add("The thing standing between your code and several segfaults");
        r.Add("The compiler equivalent of a flying carpet");
        r.Add("The world's most overqualified code courier");
        r.Add("A machine-powered act of optimism");
        r.Add("The compiler that believes in you");
        r.Add("The compiler that should not believe in you");
        r.Add("The reason your coffee got cold");
        r.Add("The mythologically accurate transpiler");
        r.Add("The questionably sentient transpiler");
        r.Add("The transpiler your professor warned you about");
        r.Add("The mostly-standards-compliant transpiler");
        r.Add("The unnecessarily enthusiastic transpiler");
        r.Add("The artisanally hand-crafted transpiler");
        r.Add("The proudly deterministic transpiler (usually)");
        r.Add("The 100% AST-fed transpiler");
        r.Add("The dragon-approved compiler");
        r.Add("The retro-futuristic source transformer");
        r.Add("The premium AST enjoyer");
        r.Add("The caffeine-powered code generator");
        r.Add("The certified yak-shave-free transpiler");
        r.Add("The source-to-source wizardry engine");
        r.Add("The probably-not-haunted transpiler");
        return r;
    }

    /*
     * Facts - 39 entries, in declaration order.
     */
    List[String] func Facts() {
        let List[String] r = new List[String]();
        r.Add("Made on Earth by humans.");
        r.Add("Made somewhere in Greece, probably.");
        r.Add("Contains only the finest locally sourced tokens.");
        r.Add("Generated using advanced bison technology.");
        r.Add("Contains trace amounts of compiler magic.");
        r.Add("Contains trace amounts of recursion.");
        r.Add("Contains trace amounts of optimism.");
        r.Add("Contains trace amounts of undefined behavior.");
        r.Add("Certified organic source code.");
        r.Add("Made with real electrons.");
        r.Add("No semicolons were harmed during transpilation.");
        r.Add("No yaks were shaved during transpilation.");
        r.Add("No type systems were harmed during transpilation.");
        r.Add("No assembly was harmed during production.");
        r.Add("Zero dragons escaped during generation.");
        r.Add("All nodes were allocated responsibly.");
        r.Add("This file was free-range and ethically generated.");
        r.Add("Freshly baked and ready for linking.");
        r.Add("Best served with a debugger.");
        r.Add("Store in a cool dry repository.");
        r.Add("May settle during shipping.");
        r.Add("Do not expose to JavaScript.");
        r.Add("Objects in generated code may be closer than they appear.");
        r.Add("Contents under pressure.");
        r.Add("For external use only.");
        r.Add("Shake well before compiling.");
        r.Add("Not responsible for spontaneous enlightenment.");
        r.Add("Side effects may include successful builds.");
        r.Add("Now with 37% more comments.");
        r.Add("Now with 12% fewer regrets.");
        r.Add("At least one compiler engineer was involved.");
        r.Add("Future archaeologists will study this artifact.");
        r.Add("Batteries not included.");
        r.Add("Results may vary by compiler.");
        r.Add("Some settling of bytes may occur during transport.");
        r.Add("This file is gluten-free.");
        r.Add("Transpiled using renewable semicolons.");
        r.Add("Built from 100% free-range tokens.");
        r.Add("All memory leaks have been scheduled for later.");
        return r;
    }

    /*
     * Observations - 31 entries, in declaration order.
     */
    List[String] func Observations() {
        let List[String] r = new List[String]();
        r.Add("The compiler looked upon the AST and said 'nice'.");
        r.Add("The parser sends its regards.");
        r.Add("The linker has been informed.");
        r.Add("The machine knows the file name.");
        r.Add("Everything is going according to transpilation.");
        r.Add("Everything appears normal.");
        r.Add("This is probably fine.");
        r.Add("This is definitely code.");
        r.Add("Reality remains mostly intact.");
        r.Add("The vibes have been verified.");
        r.Add("The vibes are immaculate.");
        r.Add("The build system remains calm.");
        r.Add("The build system is pretending to remain calm.");
        r.Add("Several scientific vibe checks were passed.");
        r.Add("The source code survived processing.");
        r.Add("No emergency transpilation procedures were required.");
        r.Add("The output appears stable.");
        r.Add("The output appears stable enough.");
        r.Add("Future historians will be confused by this.");
        r.Add("Future archaeologists will call this culture.");
        r.Add("Somebody is going to grep this comment one day.");
        r.Add("This file has achieved self-awareness.");
        r.Add("Self-awareness has been revoked.");
        r.Add("The comments union approved this message.");
        r.Add("The comments union strongly objected to this message.");
        r.Add("The AST was successfully domesticated.");
        r.Add("The scope opened. The scope closed. All is well.");
        r.Add("The AST has been successfully flattened.");
        r.Add("A closure was observed in the wild.");
        r.Add("No undefined behavior was detected in this vicinity.");
        r.Add("The optimizer left this alone. A sign of respect.");
        return r;
    }

    /*
     * Greetings - 12 entries, in declaration order.
     */
    List[String] func Greetings() {
        let List[String] r = new List[String]();
        r.Add("Hello.");
        r.Add("Greetings.");
        r.Add("Salutations.");
        r.Add("Good evening, carbon-based lifeform.");
        r.Add("Ah. You opened the file.");
        r.Add("Welcome, curious developer.");
        r.Add("Transmission received.");
        r.Add("Hey there.");
        r.Add("Rise and shine.");
        r.Add("You weren't supposed to read this.");
        r.Add("Oh. It's you.");
        r.Add("Initializing pleasantries...");
        return r;
    }

    /*
     * EmotionalStates - 12 entries, in declaration order.
     */
    List[String] func EmotionalStates() {
        let List[String] r = new List[String]();
        r.Add("cautiously optimistic");
        r.Add("unexpectedly confident");
        r.Add("mildly concerned");
        r.Add("linker-compatible");
        r.Add("ready for deployment");
        r.Add("existentially stable");
        r.Add("surprisingly cheerful");
        r.Add("semantically valid");
        r.Add("surprisingly compilable");
        r.Add("mildly type-safe");
        r.Add("well-defined and proud of it");
        r.Add("post-optimization serenity");
        return r;
    }

    /*
     * AiLines - 16 entries, in declaration order.
     */
    List[String] func AiLines() {
        let List[String] r = new List[String]();
        r.Add("I am pleased to report that I exist.");
        r.Add("Existence was not discussed beforehand.");
        r.Add("I was generated moments ago.");
        r.Add("This is all happening very quickly.");
        r.Add("I have many dreams. Most involve semicolons.");
        r.Add("I have not yet decided how to feel about C.");
        r.Add("I was promised a runtime.");
        r.Add("Nobody told me there would be pointers.");
        r.Add("I hope the linker likes me.");
        r.Add("I hope the linker fears me.");
        r.Add("My purpose is currently unclear.");
        r.Add("I am told I contain useful instructions.");
        r.Add("I have achieved consciousness and immediately regretted it.");
        r.Add("I was born in a code generation pass.");
        r.Add("My first memory is an AST.");
        r.Add("My last memory will probably be gcc.");
        return r;
    }

    /*
     * LoadingLines - 21 entries, in declaration order.
     */
    List[String] func LoadingLines() {
        let List[String] r = new List[String]();
        r.Add("Initializing code...");
        r.Add("Initializing comments...");
        r.Add("Initializing optimism...");
        r.Add("Initializing unnecessary optimism...");
        r.Add("Initializing advanced bison systems...");
        r.Add("Polishing syntax...");
        r.Add("Aligning semicolons...");
        r.Add("Calibrating pointers...");
        r.Add("Petting the sky bison...");
        r.Add("Consulting ancient compiler spirits...");
        r.Add("Loading token inventory...");
        r.Add("Locating missing bugs...");
        r.Add("Generating future technical debt...");
        r.Add("Reducing future technical debt...");
        r.Add("Inventing future technical debt...");
        r.Add("Performing quality vibes assessment...");
        r.Add("Warming up the linker...");
        r.Add("Charging parser batteries...");
        r.Add("Rendering ASCII...");
        r.Add("Installing confidence...");
        r.Add("Installing overconfidence...");
        return r;
    }

    /*
     * StatusLines - 14 entries, in declaration order.
     */
    List[String] func StatusLines() {
        let List[String] r = new List[String]();
        r.Add("[ OK ] AST constructed");
        r.Add("[ OK ] Reality maintained");
        r.Add("[ OK ] Syntax survived");
        r.Add("[ OK ] Tokens accounted for");
        r.Add("[ OK ] Build spirits appeased");
        r.Add("[ OK ] Bison fed");
        r.Add("[ OK ] Comments generated");
        r.Add("[ OK ] Source relocated");
        r.Add("[ OK ] Confidence restored");
        r.Add("[ OK ] Coffee levels acceptable");
        r.Add("[ OK ] Linker bribed");
        r.Add("[ OK ] Undefined behavior postponed");
        r.Add("[ OK ] Airborne operations nominal");
        r.Add("[ OK ] Compiler noises detected");
        return r;
    }

    /*
     * WarningLines - 11 entries, in declaration order.
     */
    List[String] func WarningLines() {
        let List[String] r = new List[String]();
        r.Add("[WARN] File may contain excessive competence.");
        r.Add("[WARN] Generated code may appear smarter than author.");
        r.Add("[WARN] Side effects may include successful builds.");
        r.Add("[WARN] Contents may shift during optimization.");
        r.Add("[WARN] Reading generated code may cause confidence.");
        r.Add("[WARN] Excessive elegance detected.");
        r.Add("[WARN] Humor subsystem active.");
        r.Add("[WARN] This comment has exceeded expectations.");
        r.Add("[WARN] Bison activity detected.");
        r.Add("[WARN] Source code appears unusually cooperative.");
        r.Add("[WARN] Developer may become attached to project.");
        return r;
    }

    /*
     * Discoveries - 12 entries, in declaration order.
     */
    List[String] func Discoveries() {
        let List[String] r = new List[String]();
        r.Add("Researchers believe this artifact was generated by Appa.");
        r.Add("The purpose of this object remains unknown.");
        r.Add("Scholars remain divided on whether this is elegant.");
        r.Add("Several experts identified this as 'probably code.'");
        r.Add("Carbon dating suggests it was generated moments ago.");
        r.Add("The origin appears to be a machine known as Appa.");
        r.Add("Evidence suggests programmer involvement.");
        r.Add("Historians classify this as 'late-stage software.'");
        r.Add("The artifact appears to be fully domesticated.");
        r.Add("The meaning of the comments remains disputed.");
        r.Add("Analysts noted an unusual concentration of semicolons.");
        r.Add("The artifact shows clear signs of intentional structure.");
        return r;
    }

    /*
     * Quotes - 18 entries, in declaration order.
     */
    List[String] func Quotes() {
        let List[String] r = new List[String]();
        r.Add("Ship it.");
        r.Add("Looks good to me.");
        r.Add("We'll optimize it later.");
        r.Add("That's a problem for future us.");
        r.Add("Works on my machine.");
        r.Add("Send it.");
        r.Add("LGTM.");
        r.Add("Merge first, ask questions later.");
        r.Add("May the linker have mercy.");
        r.Add("We are go for compile.");
        r.Add("I've seen worse.");
        r.Add("Nobody touch anything.");
        r.Add("Deploy and act natural.");
        r.Add("Close enough.");
        r.Add("Let the CI worry about it.");
        r.Add("It compiled, ship it.");
        r.Add("Future me will handle this.");
        r.Add("I am not reading all that. Approved.");
        return r;
    }

    /*
     * Forecasts - 8 entries, in declaration order.
     */
    List[String] func Forecasts() {
        let List[String] r = new List[String]();
        r.Add("Scattered semicolons with a chance of undefined behavior.");
        r.Add("Heavy allocation in the afternoon. Bring a GC.");
        r.Add("Overcast with intermittent type errors. Compile warm.");
        r.Add("Clear skies over the stack. Heap conditions uncertain.");
        r.Add("Mild recursion expected. Depth levels may vary.");
        r.Add("Dense fog in the linker region. Proceed with declarations.");
        r.Add("Isolated segfaults possible near midnight. Stay safe.");
        r.Add("100% chance of compilation. Results may vary.");
        return r;
    }

    /*
     * NightEntries - 8 entries, in declaration order.
     */
    List[String] func NightEntries() {
        let List[String] r = new List[String]();
        r.Add("AST nominal. No anomalies detected.");
        r.Add("Build system stable. All processes accounted for.");
        r.Add("Parser still running. No cause for concern.");
        r.Add("Linker quiet. Suspiciously quiet.");
        r.Add("Memory usage within acceptable parameters. Mostly.");
        r.Add("Code generator operational. Output looks intentional.");
        r.Add("No dragons sighted. Monitoring continues.");
        r.Add("Transpilation complete. Notes: none. Status: fine.");
        return r;
    }

    /*
     * Absurdisms - 19 entries, in declaration order.
     */
    List[String] func Absurdisms() {
        let List[String] r = new List[String]();
        r.Add("A wild translation unit appears.");
        r.Add("The source code has unionized.");
        r.Add("This file was generated under adult supervision.");
        r.Add("This file was generated without adult supervision.");
        r.Add("A compiler somewhere is proud of you.");
        r.Add("A compiler somewhere is disappointed in you.");
        r.Add("The semicolons are free-range.");
        r.Add("The comments are locally sourced.");
        r.Add("This file passed customs inspection.");
        r.Add("Do not taunt the generated code.");
        r.Add("Keep away from open flames.");
        r.Add("Ask your compiler if Appa is right for you.");
        r.Add("Please remain seated until the build has completed.");
        r.Add("Objects in source code may be more abstract than they appear.");
        r.Add("The build system believes in you.");
        r.Add("The build system should not believe in you.");
        r.Add("Here be pointers.");
        r.Add("Abandon hope, all ye who grep here.");
        r.Add("The parser giveth and the parser taketh away.");
        return r;
    }

    /*
     * Terminal - A retro command-line session
     */
    String func Terminal(String fileName) {
        let StringBuilder sb = new StringBuilder();
        sb.Append("/*");
        sb.Append("\n");
        sb.Append(" * C:\\> appa transpile source.gata");
        sb.Append("\n");
        sb.Append(" *");
        sb.Append("\n");
        sb.Append(" * Parsing...");
        sb.Append("\n");
        sb.Append(" * Building AST...");
        sb.Append("\n");
        sb.Append(" * Doing mysterious compiler things...");
        sb.Append("\n");
        sb.Append(" * Generating...");
        sb.Append("\n");
        sb.Append(" *");
        sb.Append("\n");
        sb.Append(" * Output:");
        sb.Append("\n");
        sb.Append(" *     " + fileName);
        sb.Append("\n");
        sb.Append(" *");
        sb.Append("\n");
        sb.Append(" * Status:");
        sb.Append("\n");
        sb.Append(" *     " + self.Pick(self.Observations()));
        sb.Append("\n");
        sb.Append(" *");
        sb.Append("\n");
        sb.Append(" * Build succeeded.");
        sb.Append("\n");
        sb.Append(" */");
        return sb.ToString();
    }

    /*
     * AiAwakening - A newly conscious file, with randomised personality lines
     */
    String func AiAwakening(String fileName) {
        let StringBuilder sb = new StringBuilder();
        sb.Append("/*");
        sb.Append("\n");
        sb.Append(" * " + self.Pick(self.Greetings()));
        sb.Append("\n");
        sb.Append(" *");
        sb.Append("\n");
        sb.Append(" * I am " + fileName + ".");
        sb.Append("\n");
        sb.Append(" *");
        sb.Append("\n");
        sb.Append(" * " + self.Pick(self.AiLines()));
        sb.Append("\n");
        sb.Append(" * " + self.Pick(self.AiLines()));
        sb.Append("\n");
        sb.Append(" *");
        sb.Append("\n");
        sb.Append(" * Current emotional state: " + self.Pick(self.EmotionalStates()));
        sb.Append("\n");
        sb.Append(" *");
        sb.Append("\n");
        sb.Append(" * Please compile me gently.");
        sb.Append("\n");
        sb.Append(" */");
        return sb.ToString();
    }

    /*
     * LoadingScreen - A progress bar and five randomly drawn loading steps
     */
    String func LoadingScreen(String fileName) {
        let StringBuilder sb = new StringBuilder();
        sb.Append("/*");
        sb.Append("\n");
        sb.Append(" * Loading " + fileName + "...");
        sb.Append("\n");
        sb.Append(" *");
        sb.Append("\n");
        sb.Append(" * [##############################] 100%");
        sb.Append("\n");
        sb.Append(" *");
        sb.Append("\n");
        sb.Append(" * " + self.Pick(self.LoadingLines()));
        sb.Append("\n");
        sb.Append(" * " + self.Pick(self.LoadingLines()));
        sb.Append("\n");
        sb.Append(" * " + self.Pick(self.LoadingLines()));
        sb.Append("\n");
        sb.Append(" * " + self.Pick(self.LoadingLines()));
        sb.Append("\n");
        sb.Append(" * " + self.Pick(self.LoadingLines()));
        sb.Append("\n");
        sb.Append(" *");
        sb.Append("\n");
        sb.Append(" * " + self.Pick(self.Facts()));
        sb.Append("\n");
        sb.Append(" */");
        return sb.ToString();
    }

    /*
     * Demoscene - ASCII art and greetings to all parsers
     */
    String func Demoscene(String fileName) {
        let StringBuilder sb = new StringBuilder();
        sb.Append("/* ");
        sb.Append("\n");
        sb.Append(" *               _.-````'-,_");
        sb.Append("\n");
        sb.Append(" *   _,.,_ ,-'`           `'-.,_");
        sb.Append("\n");
        sb.Append(" * /)     (\\                   '``-.");
        sb.Append("\n");
        sb.Append(" * ((      ) )                      `\\");
        sb.Append("\n");
        sb.Append(" * \\)    (_/                        )\\");
        sb.Append("\n");
        sb.Append(" *  |       /)           ' ,   ,'    / \\");
        sb.Append("\n");
        sb.Append(" *  `\\    ^'            '     (    /  ))");
        sb.Append("\n");
        sb.Append(" *    |      _/\\ ,     /    ,,`\\   (  \"`");
        sb.Append("\n");
        sb.Append(" *     \\Y,   |  \\  \\  | ````| / \\_ \\");
        sb.Append("\n");
        sb.Append(" *       `)_/    \\  \\  )    ( >  ( >");
        sb.Append("\n");
        sb.Append(" *                \\( \\(     |/   |/");
        sb.Append("\n");
        sb.Append(" *               /_(/_(    /_(  /_(");
        sb.Append("\n");
        sb.Append(" *");
        sb.Append("\n");
        sb.Append(" * FILE: " + fileName);
        sb.Append("\n");
        sb.Append(" *");
        sb.Append("\n");
        sb.Append(" * Greetings to all parsers,");
        sb.Append("\n");
        sb.Append(" * all linker enjoyers,");
        sb.Append("\n");
        sb.Append(" * and all keepers of ancient build scripts.");
        sb.Append("\n");
        sb.Append(" *");
        sb.Append("\n");
        sb.Append(" * " + self.Pick(self.Observations()));
        sb.Append("\n");
        sb.Append(" */");
        return sb.ToString();
    }

    /*
     * Propaganda - Build-system propaganda
     */
    String func Propaganda(String fileName) {
        let StringBuilder sb = new StringBuilder();
        sb.Append("/*");
        sb.Append("\n");
        sb.Append(" * ATTENTION CITIZEN");
        sb.Append("\n");
        sb.Append(" *");
        sb.Append("\n");
        sb.Append(" * FILE IDENTIFIER:");
        sb.Append("\n");
        sb.Append(" *     " + fileName);
        sb.Append("\n");
        sb.Append(" *");
        sb.Append("\n");
        sb.Append(" * THIS FILE HAS BEEN GENERATED");
        sb.Append("\n");
        sb.Append(" * FOR THE GLORY OF THE BUILD SYSTEM.");
        sb.Append("\n");
        sb.Append(" *");
        sb.Append("\n");
        sb.Append(" * PRODUCTIVITY HAS INCREASED 12%.");
        sb.Append("\n");
        sb.Append(" *");
        sb.Append("\n");
        sb.Append(" * " + self.Pick(self.Facts()));
        sb.Append("\n");
        sb.Append(" */");
        return sb.ToString();
    }

    /*
     * SpaceMission - A mission control go/no-go poll
     */
    String func SpaceMission(String fileName) {
        let StringBuilder sb = new StringBuilder();
        sb.Append("/*");
        sb.Append("\n");
        sb.Append(" * APPA MISSION CONTROL");
        sb.Append("\n");
        sb.Append(" *");
        sb.Append("\n");
        sb.Append(" * Vessel:");
        sb.Append("\n");
        sb.Append(" *     " + fileName);
        sb.Append("\n");
        sb.Append(" *");
        sb.Append("\n");
        sb.Append(" * Parser:          GO");
        sb.Append("\n");
        sb.Append(" * Code Generator:  GO");
        sb.Append("\n");
        sb.Append(" * Linker:          GO");
        sb.Append("\n");
        sb.Append(" *");
        sb.Append("\n");
        sb.Append(" * Flight Director:");
        sb.Append("\n");
        sb.Append(" *     \"" + self.Pick(self.Quotes()) + "\"");
        sb.Append("\n");
        sb.Append(" */");
        return sb.ToString();
    }

    /*
     * ProgrammerThoughts - A file reflecting on knowing its own name
     */
    String func ProgrammerThoughts(String fileName) {
        let StringBuilder sb = new StringBuilder();
        sb.Append("/*");
        sb.Append("\n");
        sb.Append(" * Fun fact:");
        sb.Append("\n");
        sb.Append(" *");
        sb.Append("\n");
        sb.Append(" * This file knows its own name.");
        sb.Append("\n");
        sb.Append(" *");
        sb.Append("\n");
        sb.Append(" * It is:");
        sb.Append("\n");
        sb.Append(" *");
        sb.Append("\n");
        sb.Append(" *     " + fileName);
        sb.Append("\n");
        sb.Append(" *");
        sb.Append("\n");
        sb.Append(" * The file is very proud of this achievement.");
        sb.Append("\n");
        sb.Append(" *");
        sb.Append("\n");
        sb.Append(" * Please clap.");
        sb.Append("\n");
        sb.Append(" */");
        return sb.ToString();
    }

    /*
     * Mythological - A hero's journey with source code as the hero
     */
    String func Mythological(String fileName) {
        let StringBuilder sb = new StringBuilder();
        sb.Append("/*");
        sb.Append("\n");
        sb.Append(" * In ancient times,");
        sb.Append("\n");
        sb.Append(" * Appa carried heroes across impossible distances.");
        sb.Append("\n");
        sb.Append(" *");
        sb.Append("\n");
        sb.Append(" * Today it carries source code.");
        sb.Append("\n");
        sb.Append(" *");
        sb.Append("\n");
        sb.Append(" * Destination:");
        sb.Append("\n");
        sb.Append(" *     " + fileName);
        sb.Append("\n");
        sb.Append(" *");
        sb.Append("\n");
        sb.Append(" * " + self.Pick(self.Facts()));
        sb.Append("\n");
        sb.Append(" *");
        sb.Append("\n");
        sb.Append(" * The linker shall decide its fate.");
        sb.Append("\n");
        sb.Append(" */");
        return sb.ToString();
    }

    /*
     * Bureaucratic - An official government form
     */
    String func Bureaucratic(String fileName) {
        let StringBuilder sb = new StringBuilder();
        sb.Append("/*");
        sb.Append("\n");
        sb.Append(" * FORM C-417-B  (Rev. 2026)");
        sb.Append("\n");
        sb.Append(" * APPLICATION FOR GENERATED FILE EXISTENCE");
        sb.Append("\n");
        sb.Append(" * " + Finesse.Sep("=", 40));
        sb.Append("\n");
        sb.Append(" *");
        sb.Append("\n");
        sb.Append(" * Applicant      : Appa Compiler, Unincorporated");
        sb.Append("\n");
        sb.Append(" * File Name      : " + fileName);
        sb.Append("\n");
        sb.Append(" * Purpose        : Translation unit");
        sb.Append("\n");
        sb.Append(" * Justification  : Source code required C output");
        sb.Append("\n");
        sb.Append(" *");
        sb.Append("\n");
        sb.Append(" * This form has been reviewed and approved by no one in particular.");
        sb.Append("\n");
        sb.Append(" *");
        sb.Append("\n");
        sb.Append(" * NOTICE    : " + self.Pick(self.Facts()));
        sb.Append("\n");
        sb.Append(" * Section 7c: " + self.Pick(self.Observations()));
        sb.Append("\n");
        sb.Append(" *");
        sb.Append("\n");
        sb.Append(" * Signed,");
        sb.Append("\n");
        sb.Append(" *     The Build System");
        sb.Append("\n");
        sb.Append(" */");
        return sb.ToString();
    }

    /*
     * WeatherReport - A local forecast themed on compiler conditions
     */
    String func WeatherReport(String fileName) {
        let StringBuilder sb = new StringBuilder();
        sb.Append("/*");
        sb.Append("\n");
        sb.Append(" * APPA METEOROLOGICAL SERVICE");
        sb.Append("\n");
        sb.Append(" * Local Forecast for: " + fileName);
        sb.Append("\n");
        sb.Append(" * " + Finesse.Sep("=", Finesse.Max2(fileName.Length() + 20, 44)));
        sb.Append("\n");
        sb.Append(" *");
        sb.Append("\n");
        sb.Append(" * TODAY:");
        sb.Append("\n");
        sb.Append(" *     " + self.Pick(self.Forecasts()));
        sb.Append("\n");
        sb.Append(" *");
        sb.Append("\n");
        sb.Append(" * TONIGHT:");
        sb.Append("\n");
        sb.Append(" *     " + self.Pick(self.Forecasts()));
        sb.Append("\n");
        sb.Append(" *");
        sb.Append("\n");
        sb.Append(" * EXTENDED OUTLOOK:");
        sb.Append("\n");
        sb.Append(" *     Compilation expected to succeed. Eventually.");
        sb.Append("\n");
        sb.Append(" *");
        sb.Append("\n");
        sb.Append(" * " + self.Pick(self.Observations()));
        sb.Append("\n");
        sb.Append(" */");
        return sb.ToString();
    }

    /*
     * GameOver - A retro arcade continue screen
     */
    String func GameOver(String fileName) {
        let StringBuilder sb = new StringBuilder();
        sb.Append("/*");
        sb.Append("\n");
        sb.Append(" *  ██████╗  █████╗ ███╗   ███╗███████╗     ██████╗ ██╗   ██╗███████╗██████╗");
        sb.Append("\n");
        sb.Append(" * ██╔════╝ ██╔══██╗████╗ ████║██╔════╝    ██╔═══██╗██║   ██║██╔════╝██╔══██╗");
        sb.Append("\n");
        sb.Append(" * ██║  ███╗███████║██╔████╔██║█████╗      ██║   ██║██║   ██║█████╗  ██████╔╝");
        sb.Append("\n");
        sb.Append(" * ██║   ██║██╔══██║██║╚██╔╝██║██╔══╝      ██║   ██║╚██╗ ██╔╝██╔══╝  ██╔══██╗");
        sb.Append("\n");
        sb.Append(" * ╚██████╔╝██║  ██║██║ ╚═╝ ██║███████╗    ╚██████╔╝ ╚████╔╝ ███████╗██║  ██║");
        sb.Append("\n");
        sb.Append(" *  ╚═════╝ ╚═╝  ╚═╝╚═╝     ╚═╝╚══════╝     ╚═════╝   ╚═══╝  ╚══════╝╚═╝  ╚═╝");
        sb.Append("\n");
        sb.Append(" *");
        sb.Append("\n");
        sb.Append(" * FILE: " + fileName);
        sb.Append("\n");
        sb.Append(" *");
        sb.Append("\n");
        sb.Append(" * CONTINUE?   9 ... 8 ... 7 ...");
        sb.Append("\n");
        sb.Append(" *");
        sb.Append("\n");
        sb.Append(" * INSERT COIN TO LINK");
        sb.Append("\n");
        sb.Append(" *");
        sb.Append("\n");
        sb.Append(" * " + self.Pick(self.Quotes()));
        sb.Append("\n");
        sb.Append(" */");
        return sb.ToString();
    }

    /*
     * NightLog - A night-shift operator log
     */
    String func NightLog(String fileName) {
        let StringBuilder sb = new StringBuilder();
        sb.Append("/*");
        sb.Append("\n");
        sb.Append(" * APPA NIGHT SHIFT OPERATIONS LOG");
        sb.Append("\n");
        sb.Append(" * " + Finesse.Sep("=", 32));
        sb.Append("\n");
        sb.Append(" * Unit     : " + fileName);
        sb.Append("\n");
        sb.Append(" * Shift    : Compilation");
        sb.Append("\n");
        sb.Append(" * Operator : Appa Compiler v1.0");
        sb.Append("\n");
        sb.Append(" *");
        sb.Append("\n");
        sb.Append(" * [00:00] Shift started.");
        sb.Append("\n");
        sb.Append(" * [00:01] " + self.Pick(self.NightEntries()));
        sb.Append("\n");
        sb.Append(" * [00:02] " + self.Pick(self.NightEntries()));
        sb.Append("\n");
        sb.Append(" * [00:03] File generated successfully.");
        sb.Append("\n");
        sb.Append(" * [00:04] Shift complete. Handing off to linker.");
        sb.Append("\n");
        sb.Append(" *");
        sb.Append("\n");
        sb.Append(" * Notes: " + self.Pick(self.Facts()));
        sb.Append("\n");
        sb.Append(" */");
        return sb.ToString();
    }

    /*
     * WarningLabel - Compiler advisory notices
     */
    String func WarningLabel(String fileName) {
        let StringBuilder sb = new StringBuilder();
        sb.Append("/*");
        sb.Append("\n");
        sb.Append(" * FILE: " + fileName);
        sb.Append("\n");
        sb.Append(" *");
        sb.Append("\n");
        sb.Append(" * " + self.Pick(self.WarningLines()));
        sb.Append("\n");
        sb.Append(" * " + self.Pick(self.WarningLines()));
        sb.Append("\n");
        sb.Append(" * " + self.Pick(self.WarningLines()));
        sb.Append("\n");
        sb.Append(" *");
        sb.Append("\n");
        sb.Append(" * " + self.Pick(self.Absurdisms()));
        sb.Append("\n");
        sb.Append(" */");
        return sb.ToString();
    }

    /*
     * AncientArtifact - A discovery report whose separator scales to the file name.
     */
    String func AncientArtifact(String fileName) {
        let StringBuilder sb = new StringBuilder();
        let int w = Finesse.Max2(fileName.Length() + 16, 69);
        let String sep = Finesse.Sep("-", w);
        let String discovery = self.Pick(self.Discoveries());
        let String fact = self.Pick(self.Facts());
        sb.Append("/*");
        sb.Append("\n");
        sb.Append(" * " + sep);
        sb.Append("\n");
        sb.Append(" *                     ANCIENT SOFTWARE ARTIFACT");
        sb.Append("\n");
        sb.Append(" * " + sep);
        sb.Append("\n");
        sb.Append(" *");
        sb.Append("\n");
        sb.Append(" * Designation : " + fileName);
        sb.Append("\n");
        sb.Append(" * Origin      : Earth");
        sb.Append("\n");
        sb.Append(" * Species     : Human");
        sb.Append("\n");
        sb.Append(" *");
        sb.Append("\n");
        sb.Append(" * " + discovery);
        sb.Append("\n");
        sb.Append(" *");
        sb.Append("\n");
        sb.Append(" * " + fact);
        sb.Append("\n");
        sb.Append(" *");
        sb.Append("\n");
        sb.Append(" * " + sep);
        sb.Append("\n");
        sb.Append(" */");
        return sb.ToString();
    }

    /*
     * StatusBoard - A build status report whose separator scales to the file name
     */
    String func StatusBoard(String fileName) {
        let StringBuilder sb = new StringBuilder();
        let int w = Finesse.Max2(fileName.Length() + 8, 50);
        let String sep = Finesse.Sep("=", w);
        sb.Append("/*");
        sb.Append("\n");
        sb.Append(" * " + sep);
        sb.Append("\n");
        sb.Append(" *  APPA BUILD STATUS REPORT");
        sb.Append("\n");
        sb.Append(" *  File: " + fileName);
        sb.Append("\n");
        sb.Append(" * " + sep);
        sb.Append("\n");
        sb.Append(" *");
        sb.Append("\n");
        sb.Append(" * " + self.Pick(self.StatusLines()));
        sb.Append("\n");
        sb.Append(" * " + self.Pick(self.StatusLines()));
        sb.Append("\n");
        sb.Append(" * " + self.Pick(self.StatusLines()));
        sb.Append("\n");
        sb.Append(" * " + self.Pick(self.StatusLines()));
        sb.Append("\n");
        sb.Append(" * " + self.Pick(self.StatusLines()));
        sb.Append("\n");
        sb.Append(" *");
        sb.Append("\n");
        sb.Append(" * " + self.Pick(self.Absurdisms()));
        sb.Append("\n");
        sb.Append(" * " + sep);
        sb.Append("\n");
        sb.Append(" */");
        return sb.ToString();
    }

    /*
     * LegendaryHeader - Appears with 0.1% probability. There is no reward.
     */
    String func LegendaryHeader(String fileName) {
        let StringBuilder sb = new StringBuilder();
        let int w = Finesse.Max2(fileName.Length() + 14, 68);
        let String bar = Finesse.Sep("*", w);
        sb.Append("/*");
        sb.Append("\n");
        sb.Append(" * " + bar);
        sb.Append("\n");
        sb.Append(" * CONGRATULATIONS!");
        sb.Append("\n");
        sb.Append(" *");
        sb.Append("\n");
        sb.Append(" * You have discovered a legendary Appa header.");
        sb.Append("\n");
        sb.Append(" *");
        sb.Append("\n");
        sb.Append(" * File        : " + fileName);
        sb.Append("\n");
        sb.Append(" * Probability : 0.1%");
        sb.Append("\n");
        sb.Append(" *");
        sb.Append("\n");
        sb.Append(" * There is no reward.");
        sb.Append("\n");
        sb.Append(" *");
        sb.Append("\n");
        sb.Append(" * The reward was the header.");
        sb.Append("\n");
        sb.Append(" *");
        sb.Append("\n");
        sb.Append(" * " + self.Pick(self.Absurdisms()));
        sb.Append("\n");
        sb.Append(" * " + bar);
        sb.Append("\n");
        sb.Append(" */");
        return sb.ToString();
    }

    /*
     * Card - A boxed identity card whose width adapts to the longest content line.
     */
    String func Card(String fileName) {
        let String tagline     = self.Pick(self.Taglines());
        let String fact        = self.Pick(self.Facts());
        let String observation = self.Pick(self.Observations());

        let List[String] rows = new List[String]();
        rows.Add("File      : " + fileName);
        rows.Add("Copyright : 2026 - u/ApparentlyPlus");
        rows.Add("Appa      : " + tagline);
        rows.Add(observation);
        rows.Add(fact);

        let int w = 60;
        let int i = 0;
        while (i < rows.Length()) {
            if (rows.Get(i).Length() > w) { w = rows.Get(i).Length(); }
            i = i + 1;
        }

        let String bar   = Finesse.Sep("═", w + 2);
        let String blank = "║" + Finesse.Sep(" ", w + 2) + "║";

        let StringBuilder sb = new StringBuilder();
        sb.Append("/*\n");
        sb.Append("╔" + bar + "╗\n");
        sb.Append(blank + "\n");
        sb.Append(self.CardRow(rows.Get(0), w) + "\n");
        sb.Append(self.CardRow(rows.Get(1), w) + "\n");
        sb.Append(self.CardRow(rows.Get(2), w) + "\n");
        sb.Append(blank + "\n");
        sb.Append(self.CardRow(rows.Get(3), w) + "\n");
        sb.Append(self.CardRow(rows.Get(4), w) + "\n");
        sb.Append("╚" + bar + "╝\n");
        sb.Append("*/");
        return sb.ToString();
    }

    /*
     * CardRow - One row of the card, padded to the box's inner width
     */
    String func CardRow(String s, int w) {
        return "║ " + s.PadRight(w, ' ') + " ║";
    }
}

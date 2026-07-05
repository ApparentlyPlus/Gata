// Misc.g — kernel boot/startup utilities (currently just the startup banner).
//
// Ported from GatOS's own kernel/misc.c so it's ordinary, replaceable Gata code
// instead of something baked into the kernel boot sequence. Colors are the raw
// VGA palette indices from kernel/drivers/console.h's CONSOLE_COLOR_* (cyan=3,
// magenta=5, yellow=14, white=15, black=0).

import String;
import Console;

module Misc {
    public void func PrintBanner() {
        let int screenWidth = Console.Width();
        let int contentWidth = 59;

        Console.SetColor(3, 0); // cyan on black
        Console.NewLine();
        PrintCentered("   █████████             █████       ███████     █████████ ", screenWidth, contentWidth);
        PrintCentered("  ███░░░░░███           ░░███      ███░░░░░███  ███░░░░░███", screenWidth, contentWidth);
        PrintCentered(" ███     ░░░   ██████   ███████   ███     ░░███░███    ░░░ ", screenWidth, contentWidth);
        PrintCentered("░███          ░░░░░███ ░░░███░   ░███      ░███░░█████████ ", screenWidth, contentWidth);
        PrintCentered("░███    █████  ███████   ░███    ░███      ░███ ░░░░░░░░███", screenWidth, contentWidth);
        PrintCentered("░░███  ░░███  ███░░███   ░███ ███░░███     ███  ███    ░███", screenWidth, contentWidth);
        PrintCentered(" ░░█████████ ░░████████  ░░█████  ░░░███████░  ░░█████████ ", screenWidth, contentWidth);
        PrintCentered("  ░░░░░░░░░   ░░░░░░░░    ░░░░░     ░░░░░░░     ░░░░░░░░░  ", screenWidth, contentWidth);

        Console.SetColor(5, 0); // magenta on black
        let String versionLine = "G a t O S   K e r n e l  v2.0.0";
        Console.NewLine();
        PrintCentered(versionLine, screenWidth, versionLine.Length());
        Console.NewLine();

        Console.SetColor(14, 0); // yellow on black
        let String created = "Created by: u/ApparentlyPlus";
        PrintCentered(created, screenWidth, created.Length());
        Console.NewLine();

        Console.SetColor(15, 0); // white on black
        for (let int i = 0; i < screenWidth; i++) { Console.Print("_"); }
        Console.NewLine();
        Console.NewLine();
    }

    void func PrintCentered(String line, int screenWidth, int contentWidth) {
        let int pad = (screenWidth - contentWidth) / 2;
        if (pad < 0) { pad = 0; }
        for (let int i = 0; i < pad; i++) { Console.Print(" "); }
        Console.PrintLine(line);
    }
}

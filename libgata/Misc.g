/*
 * Misc.g - Kernel boot/startup utilities
 *
 * Author: u/ApparentlyPlus
 */

import String;
import Console;

module Misc {

    /*
     * PrintBanner - Print the centered GatOS startup banner
     */
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
        Console.Print("_".Repeat(screenWidth));
        Console.NewLine();
        Console.NewLine();
    }

    /*
     * PrintCentered - Print one padded line, the single built string is one batched write
     */
    void func PrintCentered(String line, int screenWidth, int contentWidth) {
        let int pad = (screenWidth - contentWidth) / 2;
        if (pad < 0) { pad = 0; }
        Console.PrintLine(" ".Repeat(pad) + line);
    }
}

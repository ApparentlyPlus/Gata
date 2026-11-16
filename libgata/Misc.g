/*
 * Misc.g - Kernel boot/startup utilities
 *
 * Author: u/ApparentlyPlus
 */

import String;
import Console;

module Misc {

    /*
     * PrintBanner - Print the centered GatOS startup banner, with the logo beside the wordmark
     * when the screen is wide enough for both (same layout as GatOS's print_banner)
     */
    public void func PrintBanner() {
        let int screenWidth = Console.Width();
        let int logoWidth = 47;
        let int wordWidth = 59;
        let int gap = 3;

        Console.SetColor(3, 0); // cyan on black
        Console.NewLine();
        if (screenWidth >= logoWidth + gap + wordWidth) {
            // The wordmark is 8 rows to the logo's 12, so it sits 2 rows down
            let int pad = (screenWidth - logoWidth - gap - wordWidth) / 2;
            for (let i = 0; i < 12; i++) {
                let line = " ".Repeat(pad) + Logo(i);
                if (i >= 2 && i < 10) { line = line + " ".Repeat(gap) + Wordmark(i - 2); }
                Console.PrintLine(line);
            }
        } else {
            for (let i = 0; i < 8; i++) { PrintCentered(Wordmark(i), screenWidth, wordWidth); }
        }

        Console.SetColor(5, 0); // magenta on black
        let String versionLine = "G a t O S   K e r n e l  v2.1.0";
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

    // Row i of the logo, 47 columns each
    String func Logo(int i) {
        switch (i) {
            case 0  { return "      🬭🬵🬹🬹████████🬹🬹🬭🬏       🬭🬭🬭           🬞   "; }
            case 1  { return "   🬞🬹█████████████████🬺🬱     █████🬹🬱🬭🬭🬭🬭🬭🬵🬻█🬱  "; }
            case 2  { return "  🬵██████████████████████🬏   ▐███████████████🬱 "; }
            case 3  { return " 🬻██████🬎🬂🬂🬂🬂🬊🬬███████████🬏  ▐████████████████🬓"; }
            case 4  { return "🬷█████🬝🬀       🬊██████████🬺  ▐█████████████████"; }
            case 5  { return "██████🬀         🬨██████████🬏 🬉█████████████████"; }
            case 6  { return "██████🬏         ▐██████████🬲  🬬███████🬎🬂  🬊███🬄"; }
            case 7  { return "🬨█████🬺🬏        🬁███████████🬱  🬊🬎🬎🬎🬎🬂       🬂🬀 "; }
            case 8  { return " 🬬██████🬹🬭🬭🬭     🬊███████████🬺🬱🬭🬭              "; }
            case 9  { return "  🬊█████████████🬱 🬊██████████████████🬹         "; }
            case 10 { return "   🬁🬎████████████   🬊🬬████████████████🬄        "; }
            default { return "      🬂🬊🬎🬎█████🬎🬂     🬁🬂🬎🬎🬬█████████🬎🬆         "; }
        }
    }

    // Row i of the "GatOS" wordmark, 59 columns each
    String func Wordmark(int i) {
        switch (i) {
            case 0  { return "   █████████             █████       ███████     █████████ "; }
            case 1  { return "  ███░░░░░███           ░░███      ███░░░░░███  ███░░░░░███"; }
            case 2  { return " ███     ░░░   ██████   ███████   ███     ░░███░███    ░░░ "; }
            case 3  { return "░███          ░░░░░███ ░░░███░   ░███      ░███░░█████████ "; }
            case 4  { return "░███    █████  ███████   ░███    ░███      ░███ ░░░░░░░░███"; }
            case 5  { return "░░███  ░░███  ███░░███   ░███ ███░░███     ███  ███    ░███"; }
            case 6  { return " ░░█████████ ░░████████  ░░█████  ░░░███████░  ░░█████████ "; }
            default { return "  ░░░░░░░░░   ░░░░░░░░    ░░░░░     ░░░░░░░     ░░░░░░░░░  "; }
        }
    }
}

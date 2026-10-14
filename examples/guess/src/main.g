// guess: the classic number guessing game, played from the keyboard.
// It runs as a userspace process; the kernel only has to boot.

import Console;
import String;
import Int;
import Random;

enum Hint { Low, High, Right }

Hint func Judge(int guess, int secret) {
    if (guess < secret) { return Hint.Low; }
    if (guess > secret) { return Hint.High; }
    return Hint.Right;
}

realm kernel {
    entry func Main() {
        Console.PrintLine("The game runs in its own process. Press Alt+Tab to play.");
    }
}

realm userspace {
    foreground process Game {
        let int best = 0;

        thread Play {
            entry func Run() {
                let rng = new Random();
                Console.PrintLine("I'm thinking of a number from 1 to 100.");
                Console.PrintLine("Type 'quit' to stop.");

                while (true) {
                    let secret = rng.NextRange(1, 101);
                    let tries = 0;
                    Console.NewLine();

                    while (true) {
                        Console.Print("guess> ");
                        let line = Console.InputLine() catch { return; };
                        line = line.Trim();
                        if (line == "quit") {
                            Console.PrintLine("bye!");
                            return;
                        }

                        let g = Int.ParseStrict(line) catch {
                            Console.PrintLine("  that's not a number");
                            continue;
                        };
                        tries++;

                        switch (Judge(g, secret)) {
                            case Hint.Low { Console.PrintLine("  higher"); }
                            case Hint.High { Console.PrintLine("  lower"); }
                            case Hint.Right {
                                Console.PrintLine($"  yes! {secret} in {tries} tries");
                                break;
                            }
                        }
                    }

                    if (best == 0 || tries < best) {
                        best = tries;
                        Console.PrintLine("  new best score");
                    }
                    Console.PrintLine($"  best so far: {best}. new round!");
                }
            }
        }
    }
}

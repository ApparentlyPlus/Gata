// snake: the arcade game, in its own userspace process. One thread reads
// the arrow keys and the other moves the snake on a timer, sharing the
// heading through an AtomicInt. Game over powers the machine off.

import Console;
import String;
import Queue;
import Set;
import Random;
import Sync;
import Algorithms;
import Time;
import Sys;

// Clockwise, so the opposite of d is (d + 2) % 4
enum Dir { Up, Right, Down, Left }

// A tile is two blank cells, and its value is their background colour
enum Tile { Empty = 0, Body = 2, Wall = 8, Head = 10, Food = 12 }

void func Flush(StringBuilder sb, Tile t) {
    Console.SetColor(15, t as int);
    Console.Print(sb.ToString());
    sb.Clear();
}

class Snake {
    public int w;
    public int h;
    public int score;
    Queue[int] body;    // cells as y * w + x, head at the back
    Set[int] cells;     // the same cells, for hit tests
    int head;
    int food;
    Random rng;

    func _init(int w, int h) {
        self.w = w;
        self.h = h;
        self.score = 0;
        self.body = new Queue[int]();
        self.cells = new Set[int]();
        self.rng = new Random();
        for (let i = 0; i < 3; i++) { self.Grow((h / 2) * w + w / 4 + i); }
        self.food = self.FreeCell();
    }

    void func Grow(int cell) {
        self.body.Enqueue(cell);
        self.cells.Add(cell);
        self.head = cell;
    }

    int func FreeCell() {
        while (true) {
            let c = self.rng.NextRange(0, self.w * self.h);
            if (!self.cells.Has(c)) { return c; }
        }
    }

    // Move one cell. False once the snake hits a wall or itself
    public bool func Step(Dir d) {
        let x = self.head % self.w;
        let y = self.head / self.w;
        switch (d) {
            case Dir.Up { y--; }
            case Dir.Down { y++; }
            case Dir.Left { x--; }
            case Dir.Right { x++; }
        }
        if (x < 0 || y < 0 || x >= self.w || y >= self.h) { return false; }

        let next = y * self.w + x;
        let ate = next == self.food;
        // The tail gets out of the way first, so chasing it is fine
        if (!ate) { self.cells.Remove(self.body.Dequeue()); }
        if (self.cells.Has(next)) { return false; }
        self.Grow(next);
        if (ate) {
            self.score++;
            self.food = self.FreeCell();
        }
        return true;
    }

    Tile func At(int x, int y) {
        if (x < 0 || y < 0 || x >= self.w || y >= self.h) { return Tile.Wall; }
        let c = y * self.w + x;
        if (c == self.head) { return Tile.Head; }
        if (c == self.food) { return Tile.Food; }
        return self.cells.Has(c) ? Tile.Body : Tile.Empty;
    }

    // The whole board from the top-left, every frame. The console
    // only repaints the cells whose contents actually changed
    public void func Draw() {
        let sb = new StringBuilder();
        let run = Tile.Wall;
        Console.Home();
        for (let y = -1; y <= self.h; y++) {
            for (let x = -1; x <= self.w; x++) {
                let t = self.At(x, y);
                if (t != run) {
                    Flush(sb, run);
                    run = t;
                }
                sb.Append("  ");
            }
            sb.AppendChar('\n');
        }
        Flush(sb, run);
        Console.SetColor(15, 0);
        Console.PrintLine($" score {self.score}    arrows to steer, Q to quit");
    }
}

realm kernel {
    entry func Main() {
        Console.PrintLine("Snake runs in its own process. Press Alt+Tab to play.");
    }
}

realm userspace {
    foreground process Game {
        let AtomicInt heading = new AtomicInt();
        let AtomicInt moved = new AtomicInt();
        let AtomicInt over = new AtomicInt();

        // Checked against the last step, not the heading, so two quick
        // turns inside one tick can't fold the snake back onto itself
        void func Turn(Dir d) {
            if ((d as int + 2) % 4 != moved.Get() as int) { heading.Set(d as int64); }
        }

        thread Keys {
            entry func Run() {
                Console.SetRaw(true);
                while (over.Get() == 0) {
                    let k = Console.ReadKey() catch { return; };
                    match (k) {
                        case Up { Turn(Dir.Up); }
                        case Down { Turn(Dir.Down); }
                        case Left { Turn(Dir.Left); }
                        case Right { Turn(Dir.Right); }
                        case Char(c) { if (c == 'q') { over.Set(1); } }
                    }
                }
            }
        }

        thread Play {
            entry func Run() {
                let s = new Snake(30, 16);
                heading.Set(-1);    // stays put until the first key
                moved.Set(Dir.Right as int64);
                Console.ShowCursor(false);
                Console.Clear();
                s.Draw();
                while (heading.Get() < 0) { Sys.Sleep(20); }

                let next = Time.Millis();
                while (over.Get() == 0) {
                    let d = (heading.Get() as int) as Dir;
                    if (!s.Step(d)) { break; }
                    moved.Set(d as int64);
                    s.Draw();

                    // A little faster with every bite. Sleep out what's left of the tick
                    next = next + Algorithms.Max(60, 150 - s.score * 4);
                    let wait = next - Time.Millis();
                    if (wait > 0) { Sys.Sleep(wait as int); }
                }

                over.Set(1);
                Console.SetColor(12, 0);
                Console.PrintLine($" game over, {s.score} eaten. Powering off...");
                Sys.Sleep(3000);
                Sys.Shutdown();
            }
        }
    }
}

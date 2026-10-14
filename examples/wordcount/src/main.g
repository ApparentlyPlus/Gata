// wordcount: count the words in a short text and print the most common ones
// as a little bar chart.

import Console;
import String;
import List;
import Map;
import Char;
import Algorithms;

class Word {
    public String text;
    public int count;

    func _init(String text, int count) {
        self.text = text;
        self.count = count;
    }
}

// Lowercase, and keep only letters, so "Cat," and "cat" are the same word.
private String func Clean(String w) {
    let sb = new StringBuilder();
    for (let i = 0; i < w.Length(); i++) {
        let c = w[i];
        if (Char.IsLetter(c)) { sb.AppendChar(Char.ToLower(c)); }
    }
    return sb.ToString();
}

// Higher count first, ties in alphabetical order.
bool func Before(Word a, Word b) {
    if (a.count != b.count) { return a.count > b.count; }
    return a.text < b.text;
}

private List[Word] func Count(List[String] lines) {
    let counts = new StringMap[int]();
    for line in lines {
        for raw in line.Split(" ") {
            let w = Clean(raw);
            if (w.IsEmpty()) { continue; }
            counts[w] = counts.GetOr(w, 0) + 1;
        }
    }

    let res = new List[Word]();
    for k in counts.Keys() { res.Add(new Word(k, counts[k])); }
    Algorithms.SortBy(res, Before);
    return res;
}

realm kernel {
    entry func Main() {
        let text = new List[String]() {
            "The cat sat on the mat.",
            "The dog sat on the log, and the cat watched the dog.",
            "Then the cat and the dog both fell asleep on the mat."
        };

        let words = Count(text);
        Console.PrintLine($"{words.Length()} distinct words");
        Console.NewLine();

        let top = Algorithms.Min(words.Length(), 6);
        for (let i = 0; i < top; i++) {
            let w = words[i];
            Console.PrintLine($"  {w.text.PadRight(8, ' ')} {"#".Repeat(w.count)} {w.count}");
        }
    }
}

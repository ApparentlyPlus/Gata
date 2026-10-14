// kitchen: one waiter thread takes orders, two chef threads cook them.
// The threads share the order queue through process variables, guarded by
// a SpinLock, and count finished dishes with an AtomicInt.

import Console;
import String;
import Queue;
import Sync;
import Sys;

// The house menu, and plain unlocked printing.
module Menu {
    public String func Dish(int id) {
        switch (id % 4) {
            case 0 { return "soup"; }
            case 1 { return "pasta"; }
            case 2 { return "salad"; }
            default { return "steak"; }
        }
    }
}

void func Say(String who, String msg) {
    Console.PrintLine($"{who.PadRight(7, ' ')}| {msg}");
}

realm kernel {
    entry func Main() {
        Say("kernel", $"today's menu starts with {Menu.Dish(1)} and {Menu.Dish(2)}");
        Say("kernel", "the kitchen runs in its own process. Press Alt+Tab to watch.");
    }
}

realm userspace {
    foreground process Kitchen {
        let int total = 10;
        let Queue[int] orders = new Queue[int]();
        let SpinLock lock = new SpinLock();
        let SpinLock out = new SpinLock();
        let AtomicInt done = new AtomicInt();
        let AtomicInt byAna = new AtomicInt();
        let AtomicInt byBen = new AtomicInt();

        // Same name as the root Say, plus a lock so three threads don't
        // interleave their lines. The printing itself is still the root's.
        @shadows void func Say(String who, String msg) {
            out.Lock();
            ::Say(who, msg);
            out.Unlock();
        }

        // Tonight order #7 is the chef's special. Everything else comes off the house menu.
        @shadows module Menu {
            public String func Dish(int id) {
                if (id == 7) { return "chef's special"; }
                return ::Menu.Dish(id);
            }
        }

        // Take the next order, or -1 if the queue is empty right now.
        int func Next() {
            lock.Lock();
            let id = orders.IsEmpty() ? -1 : orders.Dequeue();
            lock.Unlock();
            return id;
        }

        void func Cook(String who, int ms, AtomicInt tally) {
            while (done.Get() < total) {
                let id = Next();
                if (id < 0) {
                    Sys.Sleep(20);
                    continue;
                }
                Say(who, $"cooking #{id} ({Menu.Dish(id)})");
                Sys.Sleep(ms);
                tally.Increment();
                done.Increment();
                Say(who, $"#{id} ready ({done.Get()}/{total})");
            }
        }

        thread Waiter {
            entry func Run() {
                for (let i = 1; i <= total; i++) {
                    lock.Lock();
                    orders.Enqueue(i);
                    lock.Unlock();
                    Say("waiter", $"order #{i} in");
                    Sys.Sleep(120);
                }

                while (done.Get() < total) { Sys.Sleep(50); }
                Say("waiter", $"all done: ana cooked {byAna.Get()}, ben cooked {byBen.Get()}");
            }
        }

        thread Ana { entry func Run() { Cook("ana", 250, byAna); } }
        thread Ben { entry func Run() { Cook("ben", 400, byBen); } }
    }
}

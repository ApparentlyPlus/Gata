// bank: a small ledger. Money is a class with real operators, transactions
// are a tagged union, and an overdraft is a throw that the ledger catches.

import Console;
import String;
import List;
import Format;

class Money {
    public int64 cents;

    func _init(int64 cents) { self.cents = cents; }

    public static Money func Of(int dollars, int cents) {
        return new Money((dollars as int64) * 100 + cents);
    }

    public operator Money func +(Money o) { return new Money(self.cents + o.cents); }
    public operator Money func -(Money o) { return new Money(self.cents - o.cents); }
    public operator bool func <(Money o) { return self.cents < o.cents; }
    public operator bool func >(Money o) { return self.cents > o.cents; }
    public operator bool func <=(Money o) { return self.cents <= o.cents; }
    public operator bool func >=(Money o) { return self.cents >= o.cents; }

    // Lets Money sit directly inside an interpolated string.
    public String func ToString() {
        let sign = self.cents < 0 ? "-" : "";
        let abs = self.cents < 0 ? -self.cents : self.cents;
        return $"{sign}${abs / 100}.{Format.Int(abs % 100, "%02d")}";
    }
}

class Account {
    public String owner;
    public Money balance;

    func _init(String owner) {
        self.owner = owner;
        self.balance = new Money(0);
    }

    public void func Deposit(Money m) { self.balance += m; }

    public throws void func Withdraw(Money m) {
        if (m > self.balance) { throw; }
        self.balance -= m;
    }
}

union Tx {
    Deposit(Account to, Money amount),
    Withdraw(Account from, Money amount),
    Transfer(Account from, Account to, Money amount)
}

// Withdraw's throw propagates straight out of here, so a failed transfer never reaches the Deposit and no money is created.
throws void func Run(Tx tx) {
    match (tx) {
        case Deposit(to, amt) { to.Deposit(amt); }
        case Withdraw(from, amt) { from.Withdraw(amt); }
        case Transfer(from, to, amt) {
            from.Withdraw(amt);
            to.Deposit(amt);
        }
    }
}

String func Describe(Tx tx) {
    match (tx) {
        case Deposit(to, amt) { return $"deposit  {amt} to {to.owner}"; }
        case Withdraw(from, amt) { return $"withdraw {amt} from {from.owner}"; }
        case Transfer(from, to, amt) { return $"transfer {amt} {from.owner} -> {to.owner}"; }
    }
}

realm kernel {
    entry func Main() {
        let alice = new Account("alice");
        let bob = new Account("bob");

        let txs = new List[Tx]() {
            Tx.Deposit(alice, Money.Of(120, 0)),
            Tx.Deposit(bob, Money.Of(15, 50)),
            Tx.Transfer(alice, bob, Money.Of(40, 25)),
            Tx.Withdraw(bob, Money.Of(100, 0)),
            Tx.Withdraw(bob, Money.Of(5, 75)),
            Tx.Transfer(bob, alice, Money.Of(60, 0))
        };

        let failed = 0;
        for tx in txs {
            let line = Describe(tx).PadRight(36, ' ');
            Run(tx) catch {
                Console.PrintLine($"{line} DECLINED");
                failed++;
                continue;
            };
            Console.PrintLine($"{line} ok");
        }

        Console.NewLine();
        Console.PrintLine($"{failed} of {txs.Length()} declined");
        for a in [alice, bob] {
            Console.PrintLine($"  {a.owner.PadRight(6, ' ')} {a.balance}");
        }

        let total = alice.balance + bob.balance;
        Console.PrintLine($"  total  {total}");
    }
}

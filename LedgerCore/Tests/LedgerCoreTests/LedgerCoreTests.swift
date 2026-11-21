import XCTest
@testable import LedgerCore

final class LedgerCoreTests: XCTestCase {
    var cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()
    let now = Date(timeIntervalSince1970: 1_795_132_800) // 2026-11-20 UTC

    func parse(_ s: String) -> Entry { RuleParser.parse(s, now: now, calendar: cal) }

    func testSimpleExpense() {
        let e = parse("1500 spend on snacks")
        XCTAssertEqual(e.amount, 1500); XCTAssertEqual(e.kind, .expense); XCTAssertEqual(e.category, "Dining Out")
        XCTAssertFalse(e.needsInput)
    }

    func testLentViaCreditCard() {
        let e = parse("5000 rupees lent through credit card to Rahul")
        XCTAssertEqual(e.amount, 5000); XCTAssertEqual(e.kind, .lent); XCTAssertEqual(e.method, "Credit Card")
        XCTAssertEqual(e.person, "Rahul"); XCTAssertFalse(e.needsInput)
    }

    func testAmountsAndOrdinals() {
        XCTAssertEqual(RuleParser.amount(in: "1.5k uber"), 1500)
        XCTAssertEqual(RuleParser.amount(in: "₹1,50,000 rent"), 150_000)
        XCTAssertEqual(RuleParser.amount(in: "2 lakh"), 200_000)
        XCTAssertEqual(RuleParser.amount(in: "2 samosa 40"), 40)
        XCTAssertNil(RuleParser.amount(in: "on the 12th"))
    }

    func testNeedsInput() {
        XCTAssertEqual(parse("spent on snacks").question, "How much was it?")
        XCTAssertEqual(parse("lent 2000").question, "Who was this with?")
        XCTAssertEqual(parse("paid 300").question, "What was this spent on?")
    }

    func testIncomeAndRepayment() {
        let salary = parse("salary 50000 credited")
        XCTAssertEqual(salary.kind, .income); XCTAssertEqual(salary.category, "Salary"); XCTAssertEqual(salary.method, "")
        let back = parse("got 2000 back from Rahul")
        XCTAssertEqual(back.kind, .repaidToMe); XCTAssertEqual(back.person, "Rahul")
        XCTAssertEqual(parse("yesterday 200 auto").date, cal.date(byAdding: .day, value: -1, to: now))
    }

    func testRupees() {
        XCTAssertEqual(money(150_000), "₹1,50,000")
        XCTAssertEqual(money(Decimal(string: "1500.5")!), "₹1,500.50")
        XCTAssertEqual(money(-200), "-₹200")
    }

    /// Your first real automation test: a UPI handle means UPI, and "to VPA" isn't a person.
    func testUPIHandle() {
        let e = parse("₹250 debited from A/c XX1234 to VPA test@ybl")
        XCTAssertEqual(e.method, "UPI"); XCTAssertEqual(e.person, ""); XCTAssertEqual(e.amount, 250)
        XCTAssertEqual(parse("paid 300 to rahul@okaxis").method, "UPI")
        XCTAssertEqual(parse("Rs 300 debited, help: support@hdfcbank.com").method, "") // an email isn't UPI
    }

    /// One currency per ledger, no conversion: the others' amounts are left for you to fill in.
    func testOtherCurrencies() {
        defer { Currency.current = Currency(code: "INR") }
        Currency.current = Currency(code: "USD")
        XCTAssertEqual(money(150_000), "$150,000")
        XCTAssertEqual(RuleParser.amount(in: "You made a $25.00 purchase with card ending 4321. Avl bal $1,200"), 25)
        XCTAssertNil(RuleParser.amount(in: "Rs 500 debited from A/c XX1234"))
        XCTAssertNil(MessageFilter.ignoreReason("Chase: You made a $42.10 transaction with your debit card at TARGET"))
        Currency.current = Currency(code: "EUR")
        XCTAssertEqual(RuleParser.amount(in: "€12,50 spent at cafe"), Decimal(string: "12.50"))
        XCTAssertNil(RuleParser.amount(in: "USD 12.99 spent at NETFLIX"))
        Currency.current = Currency(code: "AUD")
        XCTAssertEqual(RuleParser.amount(in: "$30 spent at Woolworths"), 30) // a plain $ is ours, not USD
        Currency.current = Currency(code: "AED")
        XCTAssertEqual(money(500), "AED 500")
        XCTAssertEqual(RuleParser.amount(in: "AED 75.50 debited from your account"), Decimal(string: "75.50"))
    }

    func testStatement() {
        let entries = [parse("1500 spent on snacks via upi"), parse("5000 lent to Rahul by credit card"),
                       parse("got 1000 back from Rahul"), parse("lent 300")]
        let text = Statement.text(for: now, entries: entries, calendar: cal)
        XCTAssertTrue(text.contains("STATEMENT: November 2026"))
        XCTAssertTrue(text.contains("Dining Out") && text.contains("₹1,500"))
        XCTAssertTrue(text.contains("Rahul owes you ₹4,000"))
        XCTAssertTrue(text.contains("NEEDS INPUT (1)"))
        XCTAssertTrue(Statement.text(for: cal.date(byAdding: .month, value: -1, to: now)!, entries: entries, calendar: cal)
            .contains("No entries this month."))
    }

    func testSplitParsing() {
        XCTAssertNil(Split.parse("1500 spent on snacks"))
        XCTAssertNil(Split.parse("200 shared auto"))
        XCTAssertEqual(Split.parse("split the outing with 3 people"),
                       SplitRequest(hint: ["outing"], others: 3))
        XCTAssertEqual(Split.parse("3 logo ne contribute kar diya outing ka"),
                       SplitRequest(hint: ["outing"], others: 3, alreadyPaid: true))
        XCTAssertEqual(Split.parse("split 1200 dinner with Rahul, Amit and Neha"),
                       SplitRequest(hint: ["dinner"], amount: 1200, names: ["Rahul", "Amit", "Neha"], others: 3))
        XCTAssertEqual(Split.parse("split it between 4 of us")?.others, 3)
    }

    func testSplitTargetAndApply() {
        var outing = parse("1200 spent on outing by credit card"); outing.date = now.addingTimeInterval(-3600)
        let snacks = parse("100 snacks")
        let entries = [outing, snacks]
        let request = Split.parse("split the outing with 3 people")!
        XCTAssertEqual(Split.target(for: request, in: entries)?.id, outing.id) // word match beats "latest"
        XCTAssertNil(Split.target(for: Split.parse("split 999 dinner with Rahul")!, in: entries)) // new bill
        XCTAssertEqual(Split.target(for: Split.parse("split it with Rahul")!, in: entries)?.id, snacks.id)

        let (updated, owed) = Split.apply(request, to: outing)
        XCTAssertEqual(updated.amount, 300); XCTAssertEqual(updated.splitTotal, 1200)
        XCTAssertEqual(owed.count, 3); XCTAssertEqual(owed[0].amount, 300); XCTAssertEqual(owed[0].kind, .lent)
        XCTAssertEqual(owed[0].splitOf, outing.id); XCTAssertEqual(owed[0].method, "Credit Card")
        XCTAssertEqual(owed[0].question, "Who owes you this share?")

        // Re-splitting uses the original bill, not your current share; rounding paisa stays with you.
        let (again, none) = Split.apply(SplitRequest(others: 2, alreadyPaid: true), to: updated)
        XCTAssertEqual(again.amount, Decimal(string: "400")); XCTAssertTrue(none.isEmpty)
        var odd = outing; odd.amount = 1000
        XCTAssertEqual(Split.apply(SplitRequest(others: 2), to: odd).updated.amount, Decimal(string: "333.34"))
    }

    func testCategoriesAndIcons() {
        XCTAssertEqual(parse("Paid 1500 for wifi bill").category, "Utilities")
        XCTAssertEqual(parse("Spent 500 on dosa").category, "Dining Out")
        XCTAssertEqual(parse("ordered pizza from zomato 450").category, "Food Delivery") // delivery beats dish
        XCTAssertEqual(parse("amazon 2300 headphones").category, "Online Shopping")
        XCTAssertEqual(parse("blinkit 640").category, "Groceries")
        XCTAssertEqual(parse("electricity bill 1800").category, "Utilities")
        XCTAssertEqual(parse("netflix 649").category, "Subscriptions")
        XCTAssertEqual(RuleParser.emoji(for: "Utilities"), "💡")
        XCTAssertEqual(RuleParser.emoji(for: "Bills"), "🧾") // old saved entries keep an icon
        XCTAssertEqual(RuleParser.emoji(for: "Whatever"), "🏷️")
    }

    /// Your real case: wifi ₹1,500 already saved, then "he paid 700" means your share is ₹800.
    func testRoommatePaidPartOfWifi() {
        let wifi = parse("Paid 1500 for wifi bill"), dosa = parse("Spent 500 on dosa")
        let r = Split.parse("Wifi bill split between roomate, he paid 700")!
        XCTAssertEqual(r.names, ["Roomate"]); XCTAssertEqual(r.others, 1)
        XCTAssertEqual(r.contributed, 700); XCTAssertNil(r.amount); XCTAssertTrue(r.alreadyPaid)
        XCTAssertEqual(Split.target(for: r, in: [wifi, dosa])?.id, wifi.id) // existing bill, not a new ₹700 one
        let (updated, owed) = Split.apply(r, to: wifi)
        XCTAssertEqual(updated.amount, 800); XCTAssertEqual(updated.splitTotal, 1500); XCTAssertTrue(owed.isEmpty)

        let half = Split.parse("roommate ne wifi ka aadha de diya")!
        XCTAssertEqual(Split.apply(half, to: wifi).updated.amount, 750)
        XCTAssertEqual(Split.apply(Split.parse("split wifi with roommate")!, to: wifi).updated.amount, 750)
        XCTAssertNil(Split.parse("half kg tomatoes 40")) // "half" alone is not a split
    }

    func testTrips() {
        XCTAssertEqual(TripCommand.parse("going on goa trip"), .start("Goa"))
        XCTAssertEqual(TripCommand.parse("started manali trip"), .start("Manali"))
        XCTAssertEqual(TripCommand.parse("trip shuru"), .start("Trip"))
        XCTAssertEqual(TripCommand.parse("trip over"), .end)
        XCTAssertEqual(TripCommand.parse("back from trip"), .end)
        XCTAssertNil(TripCommand.parse("goa trip hotel 5000")) // a money entry, not a command
        XCTAssertNil(TripCommand.parse("1500 spent on snacks"))

        var hotel = parse("hotel 5000"); hotel.trip = "Goa"
        var cab = parse("cab 800"); cab.trip = "Goa"
        var lent = parse("lent 2000 to Rahul"); lent.trip = "Goa"
        let home = parse("dosa 200")
        let entries = [hotel, cab, lent, home]
        XCTAssertEqual(entries.spent(onTrip: "Goa"), 5800) // loans aren't trip cost
        XCTAssertTrue(Statement.text(for: now, entries: entries, calendar: cal).contains("Goa"))
        XCTAssertEqual(try CSV.decode(CSV.encode(entries)).map(\.trip), ["Goa", "Goa", "Goa", nil])
    }

    func testSuggestions() {
        let entries = [parse("Paid 1500 for wifi bill")]
        let empty = Suggest.forInput("", entries: entries, activeTrip: nil)
        XCTAssertTrue(empty.chips.contains("split the wifi with 2 people")) // uses your latest expense
        XCTAssertTrue(empty.chips.contains("going on goa trip"))
        XCTAssertTrue(Suggest.forInput("", entries: entries, activeTrip: "Goa").chips.contains("trip over"))

        XCTAssertEqual(Suggest.forInput("spl", entries: entries, activeTrip: nil).chips.first, "split the wifi with 2 people")
        let typo = Suggest.forInput("splt outing 3", entries: entries, activeTrip: nil)
        XCTAssertEqual(typo.didYouMean, "Did you mean split?")
        XCTAssertEqual(Suggest.forInput("delte", entries: entries, activeTrip: nil).didYouMean, "Did you mean delete?")
        XCTAssertTrue(Suggest.forInput("rent 15000", entries: entries, activeTrip: nil).chips.isEmpty) // money word, not a typo
        XCTAssertTrue(Suggest.forInput("1500 snacks", entries: entries, activeTrip: nil).chips.isEmpty)

        XCTAssertTrue(Suggest.fixes(forFailed: "delete the xyz entry", entries: entries).contains("delete the latest entry"))
        XCTAssertEqual(Suggest.distance("splt", "split"), 1)
    }

    func testReceiptReader() {
        let restaurant = ["DOMINO'S PIZZA", "Tax Invoice", "Date: 20/11/2026", "Ph 9876543210",
                          "Pizza 450.00", "Coke 60.00", "Grand Total 540.00"]
        let s = ReceiptReader.sentence(from: restaurant)
        XCTAssertEqual(s, "540 DOMINO'S PIZZA (scanned receipt)")
        let e = parse(s!)
        XCTAssertEqual(e.amount, 540); XCTAssertEqual(e.category, "Dining Out")

        // Vision often reads "Total" and its amount as separate lines; cash tendered isn't the bill.
        XCTAssertEqual(ReceiptReader.sentence(from: ["Big Bazaar", "Total", "1,250.00"]), "1250 Big Bazaar (scanned receipt)")
        // UPI payment screenshot: ₹ amount, payee name; transaction IDs and years ignored.
        XCTAssertEqual(ReceiptReader.sentence(from: ["Paid to Rahul Sharma", "₹500", "UPI transaction ID 123456789012", "20 Nov 2026"]),
                       "500 Rahul Sharma (scanned receipt)")
        XCTAssertNil(ReceiptReader.sentence(from: ["hello world", "call 9876543210"]))
    }

    func testBankSMS() {
        let upi = parse("Rs 500.00 debited from A/c XX1234 on 20-11-26 to VPA swiggy@icici (UPI Ref 432112345678). Avl Bal Rs 25,340.50")
        XCTAssertEqual(upi.amount, 500); XCTAssertEqual(upi.kind, .expense)
        XCTAssertEqual(upi.category, "Food Delivery"); XCTAssertEqual(upi.method, "UPI")

        let card = parse("INR 2,499.00 spent on HDFC Bank Credit Card XX4321 at AMAZON on 2026-11-20. Avl limit: INR 1,20,000")
        XCTAssertEqual(card.amount, 2499); XCTAssertEqual(card.method, "Credit Card"); XCTAssertEqual(card.category, "Online Shopping")

        let salary = parse("Rs.50000 credited to A/c XX1234 by NEFT from ACME SALARY. Avl Bal Rs 75,000")
        XCTAssertEqual(salary.amount, 50000); XCTAssertEqual(salary.kind, .income); XCTAssertEqual(salary.category, "Salary")

        let both = parse("Your a/c XX99 debited Rs 300 and credited to Rahul via UPI")
        XCTAssertEqual(both.kind, .expense); XCTAssertEqual(both.amount, 300)

        XCTAssertEqual(RuleParser.amount(in: "2 hours parking 50"), 50) // "rs" inside "hours" isn't rupees
        XCTAssertEqual(RuleParser.amount(in: "₹1.5k cab"), 1500)
    }

    func testDeleteCommands() {
        var old = parse("1500 spent on snacks"); old.date = cal.date(byAdding: .day, value: -1, to: now)!
        let uber = parse("200 uber"), lent = parse("lent 5000 to Rahul")
        let entries = [old, uber, lent]
        func ids(_ s: String) -> Set<UUID> { Set(DeleteCommand.matches(DeleteCommand.parse(s)!, in: entries, now: now, calendar: cal)) }

        XCTAssertNil(DeleteCommand.parse("1500 spent on snacks"))
        XCTAssertNil(DeleteCommand.parse("cleared credit card bill 5000"))
        XCTAssertEqual(ids("all entries were test entries please delete"), [old.id, uber.id, lent.id])
        XCTAssertEqual(ids("sab entries hata do"), [old.id, uber.id, lent.id])
        XCTAssertEqual(ids("delete the snacks entry"), [old.id])
        XCTAssertEqual(ids("delete today's entries"), [uber.id, lent.id])
        XCTAssertEqual(ids("remove the 5000 one"), [lent.id])
        XCTAssertEqual(ids("delete all rahul entries"), [lent.id])
        XCTAssertEqual(ids("delete that").count, 1)
    }

    func testDisplayTextIsEnglish() {
        var hindi = Entry(date: now, raw: "स्नैक्स पर 1500 खर्च किए", amount: 1500)
        XCTAssertEqual(hindi.displayText, hindi.raw) // no English yet
        hindi.note = "Spent 1500 on snacks"
        XCTAssertEqual(hindi.displayText, "Spent 1500 on snacks")
        XCTAssertEqual(parse("₹1500 snacks").displayText, "₹1500 snacks")
    }

    func testCSVRoundTrip() throws {
        var e = parse("1500 spent on snacks")
        e.note = "chips, \"lays\"\nand cola"
        e.splitTotal = 4500; e.splitOf = UUID()
        let back = try CSV.decode(CSV.encode([e, parse("lent 2000")]))
        XCTAssertEqual(back.count, 2)
        XCTAssertEqual(back[0].note, e.note); XCTAssertEqual(back[0].id, e.id); XCTAssertEqual(back[0].amount, 1500)
        XCTAssertEqual(back[0].splitTotal, 4500); XCTAssertEqual(back[0].splitOf, e.splitOf); XCTAssertNil(back[1].splitOf)
        XCTAssertEqual(abs(back[0].date.timeIntervalSince(e.date)) < 1, true)
        XCTAssertThrowsError(try CSV.decode("date,kind\nnot-a-date,expense"))
    }

    func testCSVFormulaDefused() throws {
        var e = parse("=HYPERLINK(\"https://x.example\",\"Rs 500 debited\")")
        e.note = "-5 refund"; e.person = "@ravi"
        let csv = CSV.encode([e])
        XCTAssertFalse(csv.contains(",=") || csv.contains(",\"=") || csv.contains(",-5") || csv.contains(",@"))
        let back = try XCTUnwrap(CSV.decode(csv).first)
        XCTAssertEqual(back.raw, e.raw); XCTAssertEqual(back.note, e.note); XCTAssertEqual(back.person, e.person)
    }
}

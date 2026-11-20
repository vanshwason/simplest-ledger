import XCTest
@testable import LedgerCore

final class LedgerCoreTests: XCTestCase {
    var cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()
    let now = Date(timeIntervalSince1970: 1_795_132_800) // 2026-11-20 UTC

    func parse(_ s: String) -> Entry { RuleParser.parse(s, now: now, calendar: cal) }

    func testSimpleExpense() {
        let e = parse("1500 spend on snacks")
        XCTAssertEqual(e.amount, 1500); XCTAssertEqual(e.kind, .expense); XCTAssertEqual(e.category, "Food")
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
        XCTAssertEqual(rupees(150_000), "₹1,50,000")
        XCTAssertEqual(rupees(Decimal(string: "1500.5")!), "₹1,500.50")
        XCTAssertEqual(rupees(-200), "-₹200")
    }

    func testStatement() {
        let entries = [parse("1500 spent on snacks via upi"), parse("5000 lent to Rahul by credit card"),
                       parse("got 1000 back from Rahul"), parse("lent 300")]
        let text = Statement.text(for: now, entries: entries, calendar: cal)
        XCTAssertTrue(text.contains("STATEMENT: November 2026"))
        XCTAssertTrue(text.contains("Food") && text.contains("₹1,500"))
        XCTAssertTrue(text.contains("Rahul owes you ₹4,000"))
        XCTAssertTrue(text.contains("NEEDS INPUT (1)"))
        XCTAssertTrue(Statement.text(for: cal.date(byAdding: .month, value: -1, to: now)!, entries: entries, calendar: cal)
            .contains("No entries this month."))
    }

    func testCSVRoundTrip() throws {
        var e = parse("1500 spent on snacks")
        e.note = "chips, \"lays\"\nand cola"
        let back = try CSV.decode(CSV.encode([e, parse("lent 2000")]))
        XCTAssertEqual(back.count, 2)
        XCTAssertEqual(back[0].note, e.note); XCTAssertEqual(back[0].id, e.id); XCTAssertEqual(back[0].amount, 1500)
        XCTAssertEqual(abs(back[0].date.timeIntervalSince(e.date)) < 1, true)
        XCTAssertThrowsError(try CSV.decode("date,kind\nnot-a-date,expense"))
    }
}

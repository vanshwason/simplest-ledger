import XCTest
@testable import LedgerCore

/// Public sample texts, checked end to end.
/// SMS: TVRCloud/indian-bank-sms-parser test/parser.test.ts and harshsingh-io/indian-bank-sms-parser README (both MIT).
/// Receipts: ICDAR 2019 SROIE via zzzDavid/ICDAR-2019-SROIE (MIT), files 000-007, expected totals from its key files.
final class PublicSamplesTests: XCTestCase {
    typealias SMS = (text: String, amount: Decimal?, kind: Kind?)
    static let transactions: [SMS] = [
        ("Rs.640.00 debited from A/c XX4821 on 12-11-26 to VPA blinkit@ybl. UPI Ref 631233445566. Never share OTP/PIN with anyone. -HDFC Bank", 640, .expense),
        ("Sent Rs.1,250.50 From HDFC Bank A/C *4821 To ZOMATO LIMITED On 12/11/26 Ref 631298765432 Not You? Call 18002586161/SMS BLOCK UPI to 7308080808", Decimal(string: "1250.50"), .expense),
        ("Dear UPI user A/C X5512 debited by 420.0 on date 12Nov26 trf to SWIGGY Refno 631245678901. If not u? call 1800111109. -SBI", 420, .expense),
        ("Dear Customer, Your A/C XXXXX5512 has a debit by transfer of Rs 5,000.00 on 12/11/26 ATM WDL. Avl Bal Rs 23,450.10.-SBI", 5000, .expense),
        ("A/c XX4821 Dr Rs 2,500.00 on 12-11-26 Info: BIL*ONL*ELECTRICITY. Bal Rs 15,730.45", 2500, .expense),
        ("A/c XX4821 Cr Rs 1,000.00 on 12-11-26 by NEFT from ACME LTD. Bal Rs 16,730.45", 1000, .income),
        ("Your A/c XX9087 is credited with INR 85,000.00 on 30-Oct-26 by NEFT from ACME TECHNOLOGIES PVT LTD. Avl Bal INR 1,02,345.67 - Kotak Bank", 85000, .income),
        ("Received Rs.2,000.00 in your Kotak Bank a/c XX9087 from rahul.k@okaxis on 12-11-26.UPI Ref:631211223344.", 2000, .income),
        ("Rs 799.00 reversed to your Axis Bank A/c XX3301 on 12-11-26 for failed UPI txn Ref 631277665544", 799, .income),
        ("Your Debit Card XX1234 has been credited with a refund of Rs 499.00 on 12-11-26", 499, .income),
        ("Refund of Rs.1,299.00 for your ICICI Bank Credit Card XX7731 transaction at MYNTRA has been credited on 12-Nov-26.", 1299, .income),
        ("INR 3,499.00 spent using ICICI Bank Card XX7731 on 12-Nov-26 on AMAZON PAY IN. Avl Limit: INR 1,46,501.00. If not you, call 1800 2662/SMS BLOCK 7731 to 9215676766", 3499, .expense),
        ("USD 12.99 spent on your HDFC Bank Credit Card ending 2210 at NETFLIX.COM on 12-11-26 at 09:14:22. Avl Lmt INR 1,02,340.00", nil, .expense), // foreign: asks you for ₹
        ("You spent $25.00 at STEAM with card XX4321 on 12-11-26 (INR 2,150.00)", 2150, .expense),
        ("Thanks for using HDFC Bank Card XX4821 for Rs. 3000.00 at ATM CHENNAI on 2026-11-12:14:02:11 for Cash Withdrawal. Avl bal: Rs 15,230.45", 3000, .expense),
        ("₹1,045 debited from a/c **3301 at RELIANCE SMART on 12 Nov 2026. Bal ₹9,120.40", 1045, .expense),
        ("EMI of Rs 4,512.00 for loan a/c XXXX6789 has been debited from your A/c XX4821 on 05-11-26. -HDFC Bank", 4512, .expense),
        ("Thank you for your payment of Rs 799 to Airtel using credit card XX4321 on 12-11-26", 799, .expense),
        ("Rs 450 paid at DMART on 12-11-26.Thanks for shopping", 450, .expense),
        ("Rs 120.00 debited from A/c XX1234 on 12-11-26 to VPA swiggy@ybl.Avl Bal Rs 2000", 120, .expense),
        ("Your a/c no XX1234 is debited for Rs 500 on 26-09-26 and credited to a/c XX5678 (UPI Ref 631200000001)", 500, .expense),
        ("Avl Lmt INR 50,000.00. Rs 120.00 spent on Card XX1234 at CAFE on 12-11-26", 120, .expense),
        ("Sent Rs.1,250.50 From HDFC Bank A/C *1001 To payee1@okhdfcbank On 03/10/25 Ref 100000000002", Decimal(string: "1250.50"), .expense),
        ("Dear Customer, Rs.1,111.11 has been debited from your Kotak Bank A/c XX1001 on 23-Oct-26 towards UPI/DR/100000000001/A PAYEE/KKBK.", Decimal(string: "1111.11"), .expense),
    ]

    static let notTransactions = [
        "482913 is the OTP for transaction of INR 2,499.00 on your HDFC Bank Card ending 4821 at FLIPKART. Valid for 5 mins. Do not share OTP with anyone.",
        "Do not share OTP 482910 for Rs 1,500 txn at FLIPKART",
        "Your UPI transaction of Rs 300.00 to blinkit@ybl has failed. Amount if debited will be refunded within 48 hrs.",
        "Congratulations! You are eligible for a pre-approved Personal Loan of Rs 5,00,000 at 10.5% p.a. Apply now: hdfc.bank.in/xyz T&C",
        "Your ICICI Bank Credit Card XX7731 statement: Total Amt Due Rs 32,450.00, Min Amt Due Rs 1,623.00, Due Date 02-Dec-26.",
        "ZOMATO has requested money Rs 450 from you on UPI. Pay now",
        "Your e-mandate debit of Rs 499 for Netflix is scheduled on 28-09-26 from A/c XX1234",
        "Pre-debit alert: Rs 2,500 is scheduled to be debited from A/c XX1234 on 01-10-26 for LIC",
        "Insufficient balance for debit of Rs 1,000 in A/c XX1234 on 12-11-26",
        "Refund of Rs 499 to be credited to your A/c XX1234 in 5 days",
        "Payment of Rs 25,000.00 received towards your ICICI Bank Credit Card XX7731 on 12-Nov-26. Thank you.",
    ]

    func testBankSMSAmountsAndDirection() {
        var failures: [String] = []
        for s in Self.transactions {
            if let reason = MessageFilter.ignoreReason(s.text) { failures.append("IGNORED (\(reason)): \(s.text)"); continue }
            let e = RuleParser.parse(s.text)
            if e.amount != s.amount { failures.append("amount \(e.amount.map { "\($0)" } ?? "nil") ≠ \(s.amount.map { "\($0)" } ?? "nil"): \(s.text)") }
            if let k = s.kind, e.kind != k { failures.append("kind \(e.kind) ≠ \(k): \(s.text)") }
        }
        XCTAssert(failures.isEmpty, "\n" + failures.joined(separator: "\n"))
    }

    func testNonTransactionsAreIgnored() {
        let kept = Self.notTransactions.filter { MessageFilter.ignoreReason($0) == nil }
        XCTAssert(kept.isEmpty, "\nshould be ignored:\n" + kept.joined(separator: "\n"))
    }

    /// One broad automation ("contains Rs") also catches chats; those must never become entries.
    func testChatsAreNotTransactions() {
        let chats = ["I'll see yours at 5, two hours from now", "paid 500 for your ticket, send it back later",
                     "Rs 200 de dena kal", "Happy birthday! Cheers to many more years", "Your Uber is arriving in 3 mins",
                     // Real messages that v1.0.1 wrongly added as ₹1,90,600 and ₹25,199:
                     "Your Apple Account Code is: 190600. Don't share it with anyone.",
                     "Your Apple Account code is: 444552. Do not share it with anyone.",
                     "Your verification code is 482910 for a transaction of Rs 1,500 at AMAZON"]
        for c in chats { XCTAssertNotNil(MessageFilter.ignoreReason(c), c) }
    }

    func testBankSMSDetails() {
        XCTAssertEqual(RuleParser.parse(Self.transactions[0].text).category, "Groceries")       // blinkit
        XCTAssertEqual(RuleParser.parse(Self.transactions[1].text).category, "Food Delivery")   // zomato
        XCTAssertEqual(RuleParser.parse(Self.transactions[3].text).category, "ATM Cash")
        XCTAssertEqual(RuleParser.parse(Self.transactions[3].text).method, "")                 // "has a debit" isn't a debit card
        XCTAssertEqual(RuleParser.parse(Self.transactions[4].text).category, "Utilities")       // electricity
        XCTAssertEqual(RuleParser.parse(Self.transactions[11].text).category, "Online Shopping") // amazon
        XCTAssertEqual(RuleParser.parse(Self.transactions[11].text).method, "Card")
        XCTAssertEqual(RuleParser.parse(Self.transactions[16].text).category, "EMI & Insurance")
        XCTAssertEqual(RuleParser.parse(Self.transactions[17].text).method, "Credit Card")
        XCTAssertTrue(RuleParser.parse(Self.transactions[12].text).needsInput) // USD: asks how much in ₹
    }

    static let receipts: [(lines: [String], total: Decimal)] = [
        (["TAN WOON YANN", "BOOK TA .K(TAMAN DAYA) SDN BND", "789417-W", "NO.53 55,57 & 59, JALAN SAGU 18,", "TAMAN DAYA,", "81100 JOHOR BAHRU,", "JOHOR.", "DOCUMENT NO : TD01167104", "DATE:", "25/12/2018 8:13:39 PM", "CASHIER:", "MANIS", "MEMBER:", "CASH BILL", "CODE/DESC", "PRICE", "DISC", "AMOUNT", "QTY", "RM", "RM", "9556939040116", "KF MODELLING CLAY KIDDY FISH", "1 PC", "*", "9.000", "0.00", "9.00", "TOTAL:", "ROUR DING ADJUSTMENT:", "0.00", "ROUND D TOTAL (RM):", "9.00", "CASH", "10.00", "CHANGE", "1.00", "GOODS SOLD ARE NOT RETURNABLE OR", "EXCHANGEABLE", "***", "***", "THANK YOU", "PLEASE COME AGAIN !", "9.00"], 9),
        (["TAN WOON YANN", "INDAH GIFT & HOME DECO", "27, JALAN DEDAP 13,", "TAMAN JOHOR JAYA,", "81100 JOHOR BAHRU,JOHOR.", "TEL:07-3507405", "FAX:07-3558160", "RECEIPT", "19/10/2018 20:49:59 #01", "CASHIER: CN", "LOCATION/SP: 05 /0531", "MB: MO26588", "ROOM NO: 01", "050100035279", "DESC/ITEM", "QTY", "PRICE", "AMT(RM)", "ST-PRIVILEGE CARD/GD INDAH", "88888", "1", "10.00", "10.00", "GF-TABLE LAMP/STITCH <I>", "62483", "1", "55.90", "55.90", "@DISC", "10.00%", "-5.59", "#TOTAL QTY", "2", "TOTAL AMT................. RM", "60.31", "ROUNDING ADJ............", "-0.01", "RM", "60.30", "CASH.................... RM", "70.30", "CHANGE.................. RM", "10.00", "THANK YOU ! PLEASE COME AGAIN !", "GOODS SOLD ARE NOT RETURNABLE", "THANK YOU ! FLEASE COME AOSIN !", "GOODS SOLD ARE NOT RETURNABLE", "DEALING IN WHOLESALE AND RETAIL."], Decimal(string: "60.30")!),
        (["TAN WOON YANN", "MR D.T.Y. (JOHOR) SDN BHD", "(CO.REG : 933109-X)", "LOT 1851-A & 1851-B, JALAN KPB 6,", "KAWASAN PERINDUSTRIAN BALAKONG,", "43300 SERI KEMBANGAN, SELANGOR", "(MR DIY TESCO TERBAU)", "-INVOICE-", "CHOPPING BOARD 35.5X25.5CM 803M#", "EZ10HD05 - 24", "8970669", "1", "X", "19.00", "19.00", "AIR PRESSURE SPRAYER SX-575-1 1.5L", "HC03-7 - 15", "9066468", "1", "X", "8.02", "8.02", "WAXCO WINDSHILED CLEANER 120ML", "WA14-3A - 48", "9557031100236", "1", "X", "3.02", "3.02", "BOPP TAPE 48MM*100M CLEAR", "FZ-04 - 36", "6935818350846", "1", "X", "3.88", "3.88", "ITEM(S) : 4", "QTY(S) : 4", "TOTAL", "RM 33.92", "ROUNDING ADJUSTMENT", "-RM 0.02", "TOTAL ROUNDED", "RM 33.90", "CASH", "RM 50.00", "CHANGE", "RM 16.10", "12-01-19 21:13 SH01 ZK09", "T4 R000027830", "OPERATOR TRAINEE CASHIER", "EXCHANGE ARE ALLOWED WITHIN", "7 DAYS WITH RECEIPT.", "STRICTLY NO CASH REFUND."], Decimal(string: "33.90")!),
        (["TAN WOON YANN", "YONGFATT ENTERPRISE", "(JM0517726)", "NO 122.124 JALAN DEDAP 13", "81100 JOHOR BAHRU", "TEL 07-3523888", "GST ID: 000849813504", "SIMPLIFIED TAX INVOICE", "CASH", "DOC NO", "CS00031663", "DATE", "25/12/2018", "CASHIER", "USER", "TIME", "12 31 00", "SALESPERSON", "REF.", "ITEM", "QTY", "S/PRICE", "AMOUNT", "TAX", "E8318", "1", "80.91", "80.91", "SR", "ELEGANT SCHTR BAG 15", "TOTAL QTY", "1", "80.91", "TOTAL SALES (EXCLUDING GST) :", "80.91", "DISCOUNT :", "0.00", "TOTAL GST :", "0.00", "ROUNDING", "-0.01", "TOTAL SALES (INCLUSIVE OF GST) :", "80.90", "CASH :", "100.00", "CHANGE :", "19.10", "GST SUMMARY", "TAX CODE", "%", "AMT (RM)", "TAX (RM)", "SR", "0", "80.91", "0.00", "TOTAL :", "80.91", "0.00", "GOODS SOLD ARE NOT REFUNDABLE ONLY"], Decimal(string: "80.90")!),
        (["TAN WOON YANN", "MR D.I.Y. (M) SDN BHD", "(CO. RFG : 860671-D)", "LOT 1851-A & 1851-B, JALAN KPB 6,", "KAWASAN PERINDUSTRIAN BALAKONG,", "43300 SERI KEMBANGAN, SELANGOR", "(TESCO PUTRA NILAI)", "-INVOICE-", "KILAT AUTO ECO WASH & SHINE ES1000 1L", "WA45 /2A - 12", "9555916500133", "1", "X", "3.11", "3.11", "KILAT' ECO AUTO WASH &WAX EW-1000-1L", "WA44-A - 12", "9555916500126", "1", "X", "4.62", "4.62", "WD40 27ML MOO 2572", "WA43-A - 24", "079567600084", "1", "X", "11.23", "11.23", "KLEENSO AJAIB 99 SERAI WANYI 900G", "WDOO - 15", "9555651400385", "1", "X", "7.45", "7.45", "HANDKERCHIEF 71386#2PCS", "PI12PJ11-4 - 6/300", "9090822", "1", "X", "4.50", "4.50", "ITEM (S) : 5", "QTY(S) : 5", "TOTAL", "RM 30.91", "ROUNDING ADJUSTMENT", "RM 0.01", "TOTAL ROUNDED", "RM 30.90", "CASH", "RM 51.00", "CHANGE", "RM 20.10", "18-11-18 13 : 58 SH01 ZI53", "T2 R000002902", "UPERATOR TRAINEE CASHIER", "EXCHANGE ARE ALLOWED WITHIN", "7 DAYS WITH RECEIPT.", "STRICTLY NO CASH REFUND."], Decimal(string: "30.90")!),
        (["TAN CHAY YEE", "ABC HO TRADING", "NO.2&4,JALAN HARMONI 3/2,", "TAMAN DESA HARMONI.", "81100 JOHOR BAHRU JOHOR", "07-355 2616", "CASH BILL :", "01-143008", "DATE", ":", "09/01/2019 8:01:11 PM", "CASHIER", ":", "01", "DESCRIPTION", "QTY", "PRICE", "AMOUNT", "RM", "RM", "PLASTIC", "2", "15.50", "31.00", "TOTAL :", "31.00", "TOTAL AMOUNT:", "31.00", "CASH RECEIVED :", "101.00", "CHANGE :", "70.00", "*GOODS SOLD ARE NON-REFUNDABLE*", "***THANK YOU***", "***PLEASE COME AGAIN***"], 31),
        (["TAN CHAY YEE", "SOON HUAT MACHINERY ENTERPRISE", "(JM0352019-K)", "NO.53 JALAN PUTRA 1,", "TAMAN SRIPUTRA,", "81200 JOHOR BAHRU", "JOHOR", "TEL : 07-5547360 / 016-7993391", "FAX : 07-5624059", "SOONHUAT2000@HOTMAIL.COM", "GST ID : 002116837376", "CASH SALES", "DOC NO.", ": CS00004040", "DATE: 11/01/2019", "CASHIER", ": USER", "TIME: 09:44:00", "SALESPERSON :", "REF.:", "GOODS SOLD ARE NOT RETURNABLE, THANK YOU.", "ITEM", "QTY", "S/PRICE", "S/PRICE", "AMOUNT", "TAX", "1072", "1", "80.00", "80.00", "80.00", "REPAIR ENGINE POWER SPRAYER (1UNIT)", "WORKMANSHIP & SERVICE", "70549", "1", "160.00", "160.00", "160.00", "GIANT 606 OVERFLOW ASSY", "1071", "1", "17.00", "17.00", "17.00", "ENGINE OIL", "70791", "1", "10.00", "10.00", "10.00", "GREASE FOR TOOLS 40ML (AKODA)", "70637", "1", "6.00", "6.00", "6.00", "EY20 PLUG CHAMPION", "1643", "1", "8.00", "8.00", "8.00", "STARTER TALI", "70197", "1", "10.00", "10.00", "10.00", "EY20 STARTER HANDLE", "70561", "2", "18.00", "18.00", "36.00", "HD40 1L COTIN", "TOTAL QTY:", "9", "327.00", "TOTAL SALES :", "327.00", "DISCOUNT :", "0.00", "TOTAL :", "0.00", "ROUNDING :", "0.00", "TOTAL SALES :", "327.00", "CASH :", "327.00", "CHANGE :", "0.00"], 327),
        (["TAN CHAY YEE", "S.H.H. MOTOR (SUNGAI RENGIT) SDN. BHD.", "(801580-T)", "NO. 343, JALAN KURAU, SUNGAI RENGIT,", "81620 PENGERANG, JOHOR.", "TEL: 07-8263254 FAX: 07-8266888", "INVOICE", "ITEM/DESC.", "QTY U.PRICE RM(TOTAL)", "4132", "1", "20.00", "20.00", "CROCS 300X17 TUBES", "SUB TOTAL :", "20.00", "ROUNDING ADJUSTMENT :", "0.00", "GRAND TOTAL :", "20.00", "CASH :", "20.00", "CHANGE :", "0.00", "23-01-2019 13:14:15 PM, PRINT BY: ROOT", "TOKEN NO: 0, STATION ID: A1, PID: POS", "INVOICE NO: 22497", "THANKS YOUR SUPPORT"], 20),
    ]

    func testPublicReceiptTotals() {
        var failures: [String] = []
        for (i, r) in Self.receipts.enumerated() {
            let got = ReceiptReader.total(in: r.lines)
            if got != r.total { failures.append("receipt \(i): got \(got.map { "\($0)" } ?? "nil"), expected \(r.total)") }
        }
        XCTAssert(failures.isEmpty, "\n" + failures.joined(separator: "\n"))
    }

    func testPublicReceiptMerchants() {
        XCTAssertEqual(ReceiptReader.merchant(in: Self.receipts[2].lines), "MR D.T.Y. (JOHOR) SDN BHD")
        XCTAssertEqual(ReceiptReader.merchant(in: Self.receipts[3].lines), "YONGFATT ENTERPRISE")
        XCTAssertEqual(ReceiptReader.merchant(in: Self.receipts[5].lines), "ABC HO TRADING")
    }
}

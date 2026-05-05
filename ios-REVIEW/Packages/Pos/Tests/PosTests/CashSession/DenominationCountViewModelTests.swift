import Testing
@testable import Pos

// MARK: - §39 (Discovered §14) denomination cash count tests

@Suite("DenominationCountViewModel")
struct DenominationCountViewModelTests {

    // MARK: - Total counting

    @Test("Empty count → total is 0")
    func emptyCountIsZero() {
        let vm = DenominationCountViewModel(expectedCents: 10_000)
        #expect(vm.totalCountedCents == 0)
    }

    @Test("Single $100 bill → total 10000 cents")
    func singleHundredBill() {
        let vm = DenominationCountViewModel(expectedCents: 10_000)
        vm.increment(Denomination.all[0])  // $100
        #expect(vm.totalCountedCents == 10_000)
    }

    @Test("Two $20s and three $1s → 4300 cents")
    func mixedDenominations() {
        let vm = DenominationCountViewModel(expectedCents: 5_000)
        let twenties = Denomination.all.first { $0.id == 2_000 }!
        let ones = Denomination.all.first { $0.id == 100 }!
        vm.setCount(2, for: twenties)
        vm.setCount(3, for: ones)
        #expect(vm.totalCountedCents == 4_300)
    }

    // MARK: - Variance

    @Test("Counted == expected → variance 0 → green band")
    func exactMatchIsGreen() {
        let vm = DenominationCountViewModel(expectedCents: 5_000)
        let fifties = Denomination.all.first { $0.id == 5_000 }!
        vm.setCount(1, for: fifties)
        #expect(vm.varianceCents == 0)
        #expect(vm.varianceBand == .green)
    }

    @Test("Counted $3 over → amber band")
    func smallOverageIsAmber() {
        let vm = DenominationCountViewModel(expectedCents: 10_000)
        let hundos = Denomination.all.first { $0.id == 10_000 }!
        let ones = Denomination.all.first { $0.id == 100 }!
        vm.setCount(1, for: hundos)
        vm.setCount(3, for: ones)
        #expect(vm.varianceBand == .amber)
    }

    @Test("Counted $10 over → red band requires reason")
    func largeOverageIsRed() {
        let vm = DenominationCountViewModel(expectedCents: 10_000)
        let hundos = Denomination.all.first { $0.id == 10_000 }!
        let tens = Denomination.all.first { $0.id == 1_000 }!
        vm.setCount(1, for: hundos)
        vm.setCount(1, for: tens)
        #expect(vm.varianceBand == .red)
        #expect(vm.requiresReason == true)
        #expect(vm.requiresManagerPin == true)
    }

    // MARK: - canProceed gating

    @Test("Red band without reason → canProceed false")
    func redBandWithoutReasonBlocksSubmit() {
        let vm = DenominationCountViewModel(expectedCents: 10_000)
        let hundos = Denomination.all.first { $0.id == 10_000 }!
        let tens = Denomination.all.first { $0.id == 1_000 }!
        vm.setCount(1, for: hundos)
        vm.setCount(1, for: tens)
        #expect(!vm.canProceed)
    }

    @Test("Red band + reason + managerPinApproved → canProceed true")
    func redBandWithReasonAndPinAllows() {
        let vm = DenominationCountViewModel(expectedCents: 10_000)
        let hundos = Denomination.all.first { $0.id == 10_000 }!
        let tens = Denomination.all.first { $0.id == 1_000 }!
        vm.setCount(1, for: hundos)
        vm.setCount(1, for: tens)
        vm.overShortReason = "Cashier error on last sale"
        vm.managerPinApproved = true
        #expect(vm.canProceed)
    }

    @Test("Green band → canProceed true without reason")
    func greenBandProceedsWithoutReason() {
        let vm = DenominationCountViewModel(expectedCents: 5_000)
        let fifties = Denomination.all.first { $0.id == 5_000 }!
        vm.setCount(1, for: fifties)
        #expect(vm.canProceed)
    }

    // MARK: - Increment / decrement

    @Test("Decrement below 0 is clamped to 0")
    func decrementClampedAtZero() {
        let vm = DenominationCountViewModel(expectedCents: 0)
        let denom = Denomination.all[0]
        vm.decrement(denom)  // count was 0, should stay 0
        #expect(vm.denominations[0].count == 0)
    }

    @Test("Increment then decrement returns to 0")
    func incrementThenDecrement() {
        let vm = DenominationCountViewModel(expectedCents: 0)
        vm.increment(Denomination.all[0])
        vm.decrement(Denomination.all[0])
        #expect(vm.denominations[0].count == 0)
    }

    // MARK: - Reset

    @Test("Reset clears all counts and reason")
    func resetClearsState() {
        let vm = DenominationCountViewModel(expectedCents: 5_000)
        vm.setCount(5, for: Denomination.all[0])
        vm.overShortReason = "Some reason"
        vm.managerPinApproved = true
        vm.reset()
        #expect(vm.totalCountedCents == 0)
        #expect(vm.overShortReason.isEmpty)
        #expect(!vm.managerPinApproved)
    }
}

// MARK: - EndOfShiftCard trend tests

@Suite("EndOfShiftCard")
struct EndOfShiftCardTests {

    @Test("No prior shift → trend is nil")
    func noPriorShiftNoTrend() {
        let card = EndOfShiftCard(
            saleCount: 10, grossCents: 500_00, tipsCents: 0,
            cashExpectedCents: 200_00, voidsCents: 0, itemsSoldCount: 15
        )
        #expect(card.grossTrendPercent == nil)
        #expect(card.saleCountTrendPercent == nil)
    }

    @Test("50% gross increase vs prior shift")
    func grossTrendFiftyPercent() {
        let card = EndOfShiftCard(
            saleCount: 15, grossCents: 900_00, tipsCents: 0,
            cashExpectedCents: 300_00, voidsCents: 0, itemsSoldCount: 20,
            priorGrossCents: 600_00, priorSaleCount: 10
        )
        #expect(card.grossTrendPercent != nil)
        #expect(abs(card.grossTrendPercent! - 50.0) < 0.01)
    }

    @Test("Zero prior → trend nil (no div-by-zero)")
    func zeroPriorIsNil() {
        let card = EndOfShiftCard(
            saleCount: 5, grossCents: 100_00, tipsCents: 0,
            cashExpectedCents: 50_00, voidsCents: 0, itemsSoldCount: 5,
            priorGrossCents: 0
        )
        #expect(card.grossTrendPercent == nil)
    }
}

// MARK: - AccountingExportGenerator tests

@Suite("AccountingExportGenerator")
struct AccountingExportGeneratorTests {

    let generator = AccountingExportGenerator()
    let sampleRows: [ReconciliationRow] = {
        [ReconciliationRow(
            dateTime: Date(timeIntervalSince1970: 1_745_000_000),
            invoiceId: 1042,
            lineDescription: "iPhone Screen",
            qty: 1,
            unitPriceCents: 14_999,
            lineTotalCents: 14_999,
            tenderMethod: "card",
            tenderAmountCents: 14_999
        )]
    }()

    @Test("QuickBooks IIF starts with HDR line")
    func qbIIFHasHeader() {
        let output = generator.generate(rows: sampleRows, format: .quickBooksIIF)
        #expect(output.hasPrefix("!HDR"))
    }

    @Test("QuickBooks CSV has expected header columns")
    func qbCSVHasColumns() {
        let output = generator.generate(rows: sampleRows, format: .quickBooksCSV)
        let firstLine = output.components(separatedBy: "\n").first ?? ""
        #expect(firstLine == "Date,Description,Amount,Account,Memo")
    }

    @Test("Xero CSV has expected header columns")
    func xeroCSVHasColumns() {
        let output = generator.generate(rows: sampleRows, format: .xeroCSV)
        let firstLine = output.components(separatedBy: "\n").first ?? ""
        #expect(firstLine == "Date,Amount,Payee,Description,Reference,Currency")
    }

    @Test("Xero CSV has USD currency column")
    func xeroCSVHasUSD() {
        let output = generator.generate(rows: sampleRows, format: .xeroCSV)
        #expect(output.contains(",USD"))
    }

    @Test("IIF filename has .iif extension")
    func iifFilenameExtension() {
        let filename = generator.filename(for: .quickBooksIIF)
        #expect(filename.hasSuffix(".iif"))
    }

    @Test("Xero filename has .csv extension")
    func xeroFilenameExtension() {
        let filename = generator.filename(for: .xeroCSV)
        #expect(filename.hasSuffix(".csv"))
    }
}

// MARK: - DailyTieOutValidator tests

@Suite("DailyTieOutValidator")
struct DailyTieOutValidatorTests {

    let validator = DailyTieOutValidator()

    @Test("Tied-out record returns no failures")
    func tiedOutPasses() {
        let rec = DailyReconciliation(
            id: "2026-04-26", date: Date(),
            totalSalesCents: 100_00, totalPaymentsCents: 100_00,
            cashCloseCents: 40_00, bankDepositCents: 40_00
        )
        #expect(validator.validate(rec).isEmpty)
        #expect(validator.isTiedOut(rec))
    }

    @Test("Payment surplus produces failure message")
    func paymentSurplusProducesFailure() {
        let rec = DailyReconciliation(
            id: "2026-04-26", date: Date(),
            totalSalesCents: 100_00, totalPaymentsCents: 103_00,
            cashCloseCents: 40_00, bankDepositCents: 40_00
        )
        let failures = validator.validate(rec)
        #expect(!failures.isEmpty)
        #expect(failures[0].contains("over"))
    }
}

// MARK: - OfflineCardTenderPayload tests

@Suite("OfflineCardTenderPayload")
struct OfflineCardTenderPayloadTests {

    @Test("Payload round-trips through JSON encoder/decoder")
    func jsonRoundTrip() throws {
        let original = OfflineCardTenderPayload(
            invoiceId: 9999,
            approvedAmountCents: 12_500,
            blockChypToken: "tok_test",
            authCode: "AUTH42",
            last4: "4242",
            cardBrand: "Visa",
            idempotencyKey: "idem-key-001"
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(OfflineCardTenderPayload.self, from: data)

        #expect(decoded.invoiceId == original.invoiceId)
        #expect(decoded.approvedAmountCents == original.approvedAmountCents)
        #expect(decoded.blockChypToken == original.blockChypToken)
        #expect(decoded.idempotencyKey == original.idempotencyKey)
    }

    @Test("Idempotency key is non-empty by default")
    func defaultIdempotencyKeyNotEmpty() {
        let p = OfflineCardTenderPayload(invoiceId: 1, approvedAmountCents: 100)
        #expect(!p.idempotencyKey.isEmpty)
    }
}

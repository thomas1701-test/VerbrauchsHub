import StoreKit
import StoreKitTest
import XCTest
@testable import VerbrauchsHub

/// Runs the real StoreKit flow against the local configuration in StoreKit/VerbrauchsHub.storekit.
@MainActor
final class LicenseStoreTests: XCTestCase {
    private var session: SKTestSession!

    override func setUp() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "VerbrauchsHub", withExtension: "storekit"))
        session = try SKTestSession(contentsOf: url)
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true
        executionTimeAllowance = 60
    }

    private func makeStore() async throws -> LicenseStore {
        // SKTestSession provides no AppTransaction, so the verdict for a new user is injected.
        let store = LicenseStore(legacyCheck: { .notLegacy })
        await store.refresh()
        return store
    }

    private func buy(_ product: Product) async throws -> Product.PurchaseResult {
        try await product.purchase()
    }

    func testNewUserStartsTrialThenBuys() async throws {
        let store = try await makeStore()
        XCTAssertEqual(store.state, .trialNotStarted)
        XCTAssertTrue(store.fullPriceText.contains("0,99") || store.fullPriceText.contains("0.99"), store.fullPriceText)

        await store.startTrial(using: buy)
        XCTAssertNil(store.errorMessage)
        guard case .trial(let end) = store.state else { return XCTFail("expected trial, got \(store.state)") }
        XCTAssertEqual(end.timeIntervalSinceNow, 14 * 24 * 60 * 60, accuracy: 120)
        XCTAssertEqual(store.daysLeft, 14)

        await store.buyFullVersion(using: buy)
        XCTAssertEqual(store.state, .purchased)
    }

    func testTrialSurvivesReinstall() async throws {
        let first = try await makeStore()
        await first.startTrial(using: buy)

        // A fresh store reads the trial start back from StoreKit, not from local storage.
        let second = try await makeStore()
        guard case .trial = second.state else { return XCTFail("expected trial, got \(second.state)") }
    }

    func testRefundLocksAgain() async throws {
        let store = try await makeStore()
        await store.startTrial(using: buy)
        await store.buyFullVersion(using: buy)
        XCTAssertEqual(store.state, .purchased)

        let purchase = try XCTUnwrap(session.allTransactions().first { $0.productIdentifier == LicensePolicy.fullProductID })
        try session.refundTransaction(identifier: UInt(purchase.identifier))
        await store.refresh()
        guard case .trial = store.state else { return XCTFail("expected trial after refund, got \(store.state)") }
    }
}

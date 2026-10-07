import Foundation
import StoreKit
import SwiftUI

/// Tracks trial, purchase and existing-customer status via StoreKit 2.
///
/// Rules (see `LicensePolicy`): existing customers are recognised through the signed
/// `AppTransaction`; without a verified answer the app never locks.
@MainActor
@Observable
final class LicenseStore {
    private(set) var state: LicenseState = .checking
    private(set) var fullProduct: Product?
    private(set) var trialProduct: Product?
    private(set) var isWorking = false
    private(set) var productsFailed = false
    var errorMessage: String?

    private var legacy: LegacyVerdict = .unknown
    private var purchased = false
    private var trialStart: Date?
    private var updatesTask: Task<Void, Never>?
    private let simulated: Bool
    private let legacyCheck: @MainActor () async -> LegacyVerdict

    private static let legacyKey = "legacyCustomer"
    private static let lastReminderKey = "license.lastReminder"

    init(legacyCheck: @escaping @MainActor () async -> LegacyVerdict = LicenseStore.checkLegacy) {
        self.legacyCheck = legacyCheck
        #if DEBUG
        if let simulatedState = Self.simulatedState() {
            state = simulatedState
            simulated = true
            return
        }
        #endif
        simulated = false
        if KeychainFlag.isSet(Self.legacyKey) {
            legacy = .legacy
            state = .legacy
        }
        updatesTask = Task { [weak self] in
            for await result in StoreKit.Transaction.updates {
                await self?.handle(result)
            }
        }
        Task { await refresh() }
        Task {
            // Never keep the user waiting on a slow App Store: after a few seconds
            // the app opens and the answer is applied once it arrives.
            try? await Task.sleep(for: .seconds(4))
            if state == .checking { state = .unknown }
        }
    }

    // MARK: - Status

    func refresh() async {
        guard !simulated else { return }
        async let products: Void = loadProducts()
        if legacy != .legacy {
            legacy = await legacyCheck()
            if legacy == .legacy { KeychainFlag.set(Self.legacyKey) }
        }
        await loadEntitlements()
        await products
        recompute()
    }

    /// Re-evaluates the trial end without asking StoreKit, e.g. when the app returns to the foreground.
    func recompute(now: Date = .now) {
        guard !simulated else { return }
        state = LicensePolicy.state(legacy: legacy, purchased: purchased, trialStart: trialStart, now: now)
    }

    var daysLeft: Int? {
        guard case .trial(let end) = state else { return nil }
        return LicensePolicy.daysLeft(until: end, now: .now)
    }

    var fullPriceText: String {
        fullProduct?.displayPrice ?? "0,99 €"
    }

    // MARK: - Reminders

    var isReminderDue: Bool {
        guard case .trial(let end) = state else { return false }
        let start = end.addingTimeInterval(-TimeInterval(LicensePolicy.trialDays) * 24 * 60 * 60)
        let last = UserDefaults.standard.object(forKey: Self.lastReminderKey) as? Date
        return LicensePolicy.shouldRemind(trialStart: start, lastReminder: last, now: .now)
    }

    func markReminderShown() {
        UserDefaults.standard.set(Date.now, forKey: Self.lastReminderKey)
    }

    // MARK: - Actions

    /// The view passes SwiftUI's `PurchaseAction`; tests pass `Product.purchase()`.
    typealias Purchase = (Product) async throws -> Product.PurchaseResult

    func startTrial(using purchase: Purchase) async {
        guard let trialProduct else { return await reloadProductsAfterFailure() }
        await buy(trialProduct, using: purchase)
    }

    func buyFullVersion(using purchase: Purchase) async {
        guard let fullProduct else { return await reloadProductsAfterFailure() }
        await buy(fullProduct, using: purchase)
    }

    func restore() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await AppStore.sync()
        } catch StoreKitError.userCancelled {
            return
        } catch {
            errorMessage = "Die Käufe konnten nicht abgerufen werden. Prüfe deine Internetverbindung und versuche es erneut."
        }
        // Only without a verified proof of the original download is it worth asking Apple again –
        // `AppTransaction.refresh()` shows its own sign-in prompt, on top of the one from `sync()`.
        if legacy == .unknown {
            _ = try? await AppTransaction.refresh()
        }
        await refresh()
        if !state.isFullVersion, errorMessage == nil {
            errorMessage = "Für diese Apple-ID wurde kein Kauf gefunden."
        }
    }

    // MARK: - Private

    private func buy(_ product: Product, using purchase: Purchase) async {
        isWorking = true
        defer { isWorking = false }
        do {
            let result = try await purchase(product)
            #if DEBUG
            if case .success(let verification) = result, case .unverified(_, let error) = verification {
                print("LicenseStore: unverified purchase of \(product.id): \(error)")
            } else if case .success = result {} else {
                print("LicenseStore: purchase of \(product.id) ended with \(result)")
            }
            #endif
            switch result {
            case .success(let verification):
                await handle(verification)
            case .pending:
                errorMessage = "Der Kauf wartet noch auf eine Freigabe, z. B. durch die Familienfreigabe."
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            #if DEBUG
            print("LicenseStore: purchase of \(product.id) failed: \(error)")
            #endif
            errorMessage = "Der Kauf konnte nicht abgeschlossen werden. Bitte versuche es erneut."
        }
    }

    private func handle(_ result: VerificationResult<StoreKit.Transaction>) async {
        guard let transaction = Self.trusted(result) else { return }
        apply(transaction)
        recompute()
        await transaction.finish()
    }

    /// Applies a single transaction right away; `currentEntitlements` can lag behind a fresh purchase.
    private func apply(_ transaction: StoreKit.Transaction) {
        let isActive = transaction.revocationDate == nil
        switch transaction.productID {
        case LicensePolicy.fullProductID:
            purchased = isActive
        case LicensePolicy.trialProductID:
            trialStart = isActive ? transaction.originalPurchaseDate : nil
        default:
            break
        }
    }

    private static func trusted(_ result: VerificationResult<StoreKit.Transaction>) -> StoreKit.Transaction? {
        switch result {
        case .verified(let transaction):
            return transaction
        case .unverified(let transaction, let error):
            #if DEBUG
            // SKTestSession on the simulator fails the device check for its own local transactions.
            if transaction.environment == .xcode, case .invalidDeviceVerification = error { return transaction }
            #endif
            _ = (transaction, error)
            return nil
        }
    }

    private func loadEntitlements() async {
        var isPurchased = false
        var start: Date?
        for await result in StoreKit.Transaction.currentEntitlements {
            guard let transaction = Self.trusted(result), transaction.revocationDate == nil else { continue }
            switch transaction.productID {
            case LicensePolicy.fullProductID:
                isPurchased = true
            case LicensePolicy.trialProductID:
                start = transaction.originalPurchaseDate
            default:
                break
            }
        }
        purchased = isPurchased
        trialStart = start
    }

    private func loadProducts() async {
        do {
            let products = try await Product.products(for: [LicensePolicy.trialProductID, LicensePolicy.fullProductID])
            trialProduct = products.first { $0.id == LicensePolicy.trialProductID }
            fullProduct = products.first { $0.id == LicensePolicy.fullProductID }
            productsFailed = trialProduct == nil || fullProduct == nil
        } catch {
            productsFailed = true
        }
    }

    private func reloadProductsAfterFailure() async {
        isWorking = true
        defer { isWorking = false }
        await loadProducts()
        if productsFailed {
            errorMessage = "Der App Store ist gerade nicht erreichbar. Prüfe deine Internetverbindung und versuche es erneut."
        }
    }

    static func checkLegacy() async -> LegacyVerdict {
        guard case .verified(let app)? = try? await AppTransaction.shared else { return .unknown }
        let isLegacy = LicensePolicy.isLegacy(
            originalBuild: app.originalAppVersion,
            originalPurchaseDate: app.originalPurchaseDate,
            isProduction: app.environment == .production
        )
        return isLegacy ? .legacy : .notLegacy
    }

    #if DEBUG
    /// `-licenseSimulate unlocked|trial|lastday|start|expired` for screenshots and UI tests.
    private static func simulatedState() -> LicenseState? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-licenseSimulate"), index + 1 < args.count else { return nil }
        switch args[index + 1] {
        case "unlocked": return .purchased
        case "trial": return .trial(endsAt: .now.addingTimeInterval(9 * 24 * 60 * 60))
        case "lastday": return .trial(endsAt: .now.addingTimeInterval(5 * 60 * 60))
        case "start": return .trialNotStarted
        case "expired": return .expired
        default: return nil
        }
    }
    #endif
}

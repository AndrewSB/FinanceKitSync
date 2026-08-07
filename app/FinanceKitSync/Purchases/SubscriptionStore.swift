//
//  SubscriptionStore.swift
//  FinanceKitSync
//
//  Everything StoreKit that isn't the entitlement question itself: loading the
//  product so the paywall can quote a real price, buying it, restoring it, and
//  keeping `Entitlement` current as renewals, refunds and revocations arrive.
//
//  No server, by design. StoreKit 2 transactions are signed by Apple and
//  verified on device, so there is no receipt-validation backend, no App Store
//  Server Notifications, and no new infrastructure to run.
//
import Foundation
import StoreKit

@MainActor
@Observable
final class SubscriptionStore {

    /// What the paywall renders. Deliberately a plain value rather than a
    /// `Product`: the price string, the period, and whether *this Apple ID* is
    /// eligible for the trial all come from StoreKit, and nothing downstream
    /// should be tempted to re-derive them.
    struct Offer: Equatable {
        /// Localized, currency-correct, from StoreKit. Never hardcoded.
        var displayPrice: String
        /// "month", "year", "3 months" — the billing period.
        var period: String
        /// "3 days free" when this account is eligible, nil when it is not.
        ///
        /// Eligibility is Apple's to decide. A user who has already had the
        /// trial on this Apple ID, on any device, will not get another one,
        /// and promising them one in the paywall is both a 3.1.2 rejection and
        /// a lie.
        var introOffer: String?
    }

    enum LoadState: Equatable {
        case loading
        case loaded(Offer)
        /// The store couldn't be reached, or the product isn't configured yet.
        case unavailable(String)
    }

    static let shared = SubscriptionStore()

    private(set) var loadState: LoadState = .loading
    private(set) var isPurchasing = false
    private(set) var isRestoring = false
    /// Surfaced under the buy button; nil when there's nothing to say.
    private(set) var purchaseError: String?

    private let entitlement: Entitlement
    private var product: Product?
    private var updatesTask: Task<Void, Never>?

    init(entitlement: Entitlement = .shared) {
        self.entitlement = entitlement
    }

    var offer: Offer? {
        if case .loaded(let offer) = loadState { return offer }
        return nil
    }

    // MARK: - Lifecycle

    /// Starts the transaction listener. Called once, at launch, *before* any
    /// UI — a transaction approved out of band (Ask to Buy, a renewal, a
    /// refund granted while the app was closed) arrives here and nowhere else.
    func startObservingTransactions() {
        guard updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                guard let self else { return }
                if case .verified(let transaction) = update {
                    // Unfinished transactions are redelivered forever.
                    await transaction.finish()
                }
                await self.entitlement.refresh()
                await self.reloadEligibility()
            }
        }
    }

    func load() async {
        do {
            let products = try await Product.products(for: [Entitlement.productID])
            guard let product = products.first else {
                loadState = .unavailable("Subscriptions aren't available right now.")
                return
            }
            self.product = product
            loadState = .loaded(await makeOffer(from: product))
        } catch {
            loadState = .unavailable(error.localizedDescription)
        }
    }

    /// Re-reads intro-offer eligibility without re-fetching the product. After
    /// a purchase the trial has been consumed, and the paywall — which may
    /// still be on screen — must stop advertising it.
    private func reloadEligibility() async {
        guard let product else { return }
        loadState = .loaded(await makeOffer(from: product))
    }

    private func makeOffer(from product: Product) async -> Offer {
        let subscription = product.subscription
        var introOffer: String?
        if let subscription, let intro = subscription.introductoryOffer,
           await subscription.isEligibleForIntroOffer {
            introOffer = Self.describeIntroOffer(intro)
        }
        return Offer(
            displayPrice: product.displayPrice,
            period: subscription.map { Self.describe($0.subscriptionPeriod) } ?? "month",
            introOffer: introOffer
        )
    }

    // MARK: - Buying

    func purchase() async {
        guard let product, !isPurchasing else { return }
        isPurchasing = true
        purchaseError = nil
        defer { isPurchasing = false }

        do {
            switch try await product.purchase() {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    // Apple's signature didn't check out. Nothing to finish,
                    // and nothing to entitle.
                    purchaseError = "That purchase couldn't be verified."
                    Log.append("purchase failed verification")
                    return
                }
                await transaction.finish()
                Log.append("subscription purchased")
                await entitlement.refresh()
                await reloadEligibility()
            case .pending:
                // Ask to Buy, or an SCA challenge. The transaction listener
                // picks it up whenever it's approved.
                purchaseError = "Your purchase is waiting for approval."
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            purchaseError = error.localizedDescription
            Log.append("purchase error: \(error.localizedDescription)")
        }
    }

    /// Restore. `AppStore.sync()` prompts for the Apple ID password, so it is
    /// only ever called from an explicit tap — never automatically at launch,
    /// where `Transaction.currentEntitlements` already has the answer.
    func restore() async {
        guard !isRestoring else { return }
        isRestoring = true
        purchaseError = nil
        defer { isRestoring = false }

        do {
            try await AppStore.sync()
            let status = await entitlement.refresh()
            await reloadEligibility()
            if case .notEntitled = status {
                purchaseError = "No subscription was found for this Apple ID."
            }
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    // MARK: - Formatting

    static func describe(_ period: Product.SubscriptionPeriod) -> String {
        let unit: String
        switch period.unit {
        case .day: unit = "day"
        case .week: unit = "week"
        case .month: unit = "month"
        case .year: unit = "year"
        @unknown default: unit = "period"
        }
        return period.value == 1 ? unit : "\(period.value) \(unit)s"
    }

    /// "3 days free". Read off the offer Apple actually configured, so the
    /// paywall can't drift from App Store Connect.
    static func describeIntroOffer(_ offer: Product.SubscriptionOffer) -> String {
        // An intro offer is `periodCount` repetitions of `period` — three
        // 1-day periods and one 3-day period both read as "3 days".
        let total = offer.period.value * offer.periodCount
        let span = "\(total) \(unitName(offer.period.unit, count: total))"
        switch offer.paymentMode {
        case .freeTrial:
            return "\(span) free"
        case .payUpFront:
            return "\(offer.displayPrice) for the first \(span)"
        case .payAsYouGo:
            return "\(offer.displayPrice) per \(describe(offer.period)) for \(span)"
        default:
            return "\(offer.displayPrice) introductory offer"
        }
    }

    private static func unitName(_ unit: Product.SubscriptionPeriod.Unit, count: Int) -> String {
        let name: String
        switch unit {
        case .day: name = "day"
        case .week: name = "week"
        case .month: name = "month"
        case .year: name = "year"
        @unknown default: name = "period"
        }
        return count == 1 ? name : name + "s"
    }

#if DEBUG
    /// Screenshot mode only: the capture script launches the app straight from
    /// `simctl`, with no scheme and so no StoreKit configuration file, and the
    /// paywall still has to render a plausible price. See `ScreenshotMode`.
    func seedForScreenshots(_ offer: Offer) {
        loadState = .loaded(offer)
    }
#endif
}

//
//  PaywallView.swift
//  FinanceKitSync
//
//  What the subscription buys is *background* sync. Manual sync keeps working
//  without it, and nothing already synced is ever withheld — the copy says so,
//  because it's true and because it's the difference between selling
//  convenience and selling access to the user's own financial data.
//
//  Guideline 3.1.2 wants price, billing period, renewal terms and how to
//  cancel visible on this screen, not behind a link. So they are.
//
import SwiftUI
import StoreKit

struct PaywallView: View {
    @Environment(SubscriptionStore.self) private var store
    @Environment(Entitlement.self) private var entitlement
    @Environment(\.dismiss) private var dismiss

    /// Apple's standard EULA — auto-renewables require terms of use, and this
    /// is the one every app gets by default unless it supplies its own.
    private let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    private let privacyURL = URL(string: "https://andrewsb.github.io/FinanceKitSync/privacy.html")!

    var body: some View {
        NavigationStack {
            ScrollView {
                // Tight, because the whole screen — offer, terms and links —
                // should be readable without scrolling on a 6.1" phone. This
                // capture is also the subscription's review screenshot.
                VStack(alignment: .leading, spacing: 20) {
                    header
                    comparison
                    offerBlock
                    terms
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
            .navigationTitle("Background Sync")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not now") { dismiss() }
                }
            }
            .onChange(of: entitlement.status) { _, status in
                // Bought, restored, or a pending purchase finally approved.
                if case .entitled = status { dismiss() }
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
                .font(.system(size: 40))
                .foregroundStyle(.tint)

            Text("Keep up without opening the app")
                .font(.title.bold())

            Text("A subscription lets FinanceKitSync sync in the background, so new transactions reach your server on their own.")
                .foregroundStyle(.secondary)
        }
    }

    private var comparison: some View {
        VStack(alignment: .leading, spacing: 16) {
            row("bolt.badge.clock", "With a subscription",
                "Transactions are sent throughout the day, without you doing anything.")
            row("hand.tap", "Without one",
                "The app still syncs — you pull to refresh when you open it.")
            row("lock.open", "Either way",
                "Everything already sent stays on your server, and nothing on this device is deleted.")
        }
    }

    private func row(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var offerBlock: some View {
        switch store.loadState {
        case .loading:
            HStack { Spacer(); ProgressView(); Spacer() }
                .frame(height: 88)

        case .unavailable(let message):
            VStack(alignment: .leading, spacing: 8) {
                Label("Subscriptions are unavailable", systemImage: "wifi.exclamationmark")
                    .font(.headline)
                Text(message).font(.callout).foregroundStyle(.secondary)
                Text("Manual sync works regardless.").font(.callout).foregroundStyle(.secondary)
            }

        case .loaded(let offer):
            VStack(spacing: 12) {
                Button {
                    Task { await store.purchase() }
                } label: {
                    VStack(spacing: 2) {
                        // The trial line only appears when StoreKit says this
                        // Apple ID is actually eligible for it.
                        Text(offer.introOffer.map { "Start \($0)" } ?? "Subscribe")
                            .font(.headline)
                        Text(priceLine(offer))
                            .font(.footnote)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(store.isPurchasing)

                if store.isPurchasing { ProgressView() }

                if let error = store.purchaseError {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                }

                Button("Restore purchases") {
                    Task { await store.restore() }
                }
                .disabled(store.isRestoring)
            }
        }
    }

    private func priceLine(_ offer: SubscriptionStore.Offer) -> String {
        let recurring = "\(offer.displayPrice) per \(offer.period)"
        return offer.introOffer == nil ? recurring : "then \(recurring)"
    }

    private var terms: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let offer = store.offer {
                Text(renewalTerms(offer))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 16) {
                Link("Terms of Use", destination: termsURL)
                Link("Privacy Policy", destination: privacyURL)
            }
            .font(.footnote)
        }
    }

    private func renewalTerms(_ offer: SubscriptionStore.Offer) -> String {
        let opening = offer.introOffer.map { "\($0), then the subscription is" }
            ?? "The subscription is"
        return """
        \(opening) \(offer.displayPrice) per \(offer.period), and renews automatically \
        unless it's cancelled at least 24 hours before the period ends. Payment is \
        charged to your Apple Account. Manage or cancel it any time in \
        Settings → your name → Subscriptions.
        """
    }
}

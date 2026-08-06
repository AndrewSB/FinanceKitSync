//
//  OnboardingView.swift
//  FinanceKitSync
//
//  Three steps: what this does, where it sends, permission to read.
//
import SwiftUI
import FinanceKit

struct OnboardingView: View {
    let onComplete: () -> Void

#if DEBUG
    @State private var step = ScreenshotMode.onboardingStep
    @State private var urlText = ScreenshotMode.isActive
        ? ScreenshotMode.sampleURL : ServerConfig.baseURLString
    @State private var tokenText = ScreenshotMode.isActive ? "placeholder-token" : ""
#else
    @State private var step = 0
    @State private var urlText = ServerConfig.baseURLString
    @State private var tokenText = ""
#endif

    var body: some View {
        NavigationStack {
            switch step {
            case 0: explainer
            case 1: serverStep
            default: permissionStep
            }
        }
    }

    // MARK: - Step 1

    private var explainer: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer()
            Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
                .font(.system(size: 56))
                .foregroundStyle(.tint)

            Text("Your transactions, on your server")
                .font(.largeTitle.bold())

            VStack(alignment: .leading, spacing: 16) {
                bullet("iphone", "Your Apple Card, Apple Cash, and Apple Pay transactions are read on this device.")
                bullet("lock.shield", "They're sent over an encrypted connection to a server address you choose.")
                bullet("xmark.circle", "Nobody else receives them. There's no account, and no service in the middle.")
            }

            Spacer()

            Button("Continue") { step = 1 }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
        }
        .padding(28)
    }

    private func bullet(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Step 2

    private var serverStep: some View {
        Form {
            ServerFormView(urlText: $urlText, tokenText: $tokenText)

            Section {
                Button("Continue") {
                    save()
                    step = 2
                }
                .disabled(ServerConfig.validate(urlText) == nil
                          || tokenText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } footer: {
                Text("Don't have a server yet? The setup guide walks through running one on a machine you own.")
            }
        }
        .navigationTitle("Connect")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func save() {
        guard let url = ServerConfig.validate(urlText) else { return }
        ServerConfig.setBaseURL(url)
        ServerConfig.setToken(tokenText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: - Step 3

    private var permissionStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer()
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tint)

            Text("Allow access")
                .font(.largeTitle.bold())

            Text("""
                iOS will ask whether this app can read your financial data. \
                That permission is controlled by iOS, not by this app, and you \
                can revoke it at any time in Settings › Privacy & Security › \
                Financial Data.
                """)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            Button("Continue") {
                Task {
                    // A denial isn't a dead end — the user lands on Home, which
                    // surfaces the error and lets them retry.
                    _ = try? await FinanceStore.shared.requestAuthorization()
                    onComplete()
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
        }
        .padding(28)
    }
}

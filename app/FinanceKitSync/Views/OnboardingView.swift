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

    /// Set when iOS declines (or never asks). Nil while things are going fine.
    @State private var authIssue: String?
    @State private var isRequesting = false

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

            Section {
                Button {
                    // The demo needs neither a server nor Wallet access, so
                    // the permission step is skipped along with the address.
                    DemoMode.shared.enter()
                    onComplete()
                } label: {
                    Label("Try the demo", systemImage: "play.circle")
                }
            } footer: {
                Text("Explore every feature with sample transactions and a built-in stand-in for the server. No server, no Apple Card, and nothing is read from your device. You can leave the demo from Settings at any time.")
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

            if let authIssue {
                VStack(alignment: .leading, spacing: 12) {
                    Label(authIssue, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)

                    if let settings = URL(string: UIApplication.openSettingsURLString) {
                        Link("Open Settings", destination: settings)
                    }
                }
            }

            Spacer()

            Button(isRequesting ? "Asking…" : "Continue") {
                Task { await requestAccess() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
            .disabled(isRequesting)

            if authIssue != nil {
                // A denial isn't a dead end — Home surfaces the same error and
                // lets them retry, so let them through rather than trapping them
                // on this step.
                Button("Continue without it", action: onComplete)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(28)
    }

    /// Asks for financial-data access and *reports* the answer. FinanceKit
    /// returns a status rather than throwing when access isn't granted, and it
    /// can decline without ever showing a prompt — an unavailable store, a
    /// missing `NSFinancialDataUsageDescription`, or a prior denial all look
    /// like a silent no. Discarding that made a broken build indistinguishable
    /// from a working one, which is exactly how a misspelled usage-description
    /// key shipped in 1.0.
    private func requestAccess() async {
        isRequesting = true
        defer { isRequesting = false }

        do {
            let status = try await FinanceStore.shared.requestAuthorization()
            guard status == .authorized else {
                authIssue = """
                    iOS didn't grant access to your financial data. If you saw no \
                    prompt, access may already be turned off in Settings › Privacy \
                    & Security › Financial Data.
                    """
                return
            }
            authIssue = nil
            onComplete()
        } catch {
            authIssue = "The permission request failed: \(error.localizedDescription)"
        }
    }
}

//
//  ServerFormView.swift
//  FinanceKitSync
//
//  Shared server-address form, used by both onboarding and settings so the
//  validation and connection-test behaviour can't drift between them.
//
import SwiftUI

struct ServerFormView: View {
    @Binding var urlText: String
    @Binding var tokenText: String

#if DEBUG
    @State private var testResult: TestResult? =
        ScreenshotMode.showsPassedConnectionTest ? .ok : nil
#else
    @State private var testResult: TestResult?
#endif
    @State private var isTesting = false

    enum TestResult: Equatable {
        case ok
        case failed(String)

        var isOK: Bool { self == .ok }
    }

    /// Both fields look plausible. Doesn't imply the server answered.
    var isValid: Bool {
        ServerConfig.validate(urlText) != nil
            && !tokenText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Section {
            TextField("https://box.example.ts.net:8443", text: $urlText)
                .textContentType(.URL)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onChange(of: urlText) { _, _ in testResult = nil }

            SecureField("Bearer token", text: $tokenText)
                .textContentType(.password)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onChange(of: tokenText) { _, _ in testResult = nil }
        } header: {
            Text("Your server")
        } footer: {
            if urlText.isEmpty {
                Text("Must start with https://. A port is fine.")
            } else if ServerConfig.validate(urlText) == nil {
                Label(
                    "Not a valid https address.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .foregroundStyle(.orange)
            } else {
                Text("Transactions are sent only to this address.")
            }
        }

        Section {
            Button {
                Task { await test() }
            } label: {
                HStack {
                    Text("Test connection")
                    Spacer()
                    if isTesting {
                        ProgressView()
                    }
                }
            }
            .disabled(!isValid || isTesting)

            if let testResult {
                switch testResult {
                case .ok:
                    Label("Connected", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                case .failed(let message):
                    Label(message, systemImage: "xmark.circle.fill")
                        .foregroundStyle(.red)
                }
            }
        }
    }

    /// Exposed so the parent can require a successful test before saving.
    var hasPassedTest: Bool { testResult?.isOK == true }

    private func test() async {
        guard let url = ServerConfig.validate(urlText) else { return }
        isTesting = true
        testResult = nil
        let token = tokenText.trimmingCharacters(in: .whitespacesAndNewlines)

        switch await SyncAPI.checkHealth(baseURL: url, token: token) {
        case .ok:
            testResult = .ok
        case .unauthorized:
            testResult = .failed("The server refused the token.")
        case .unexpected(let detail):
            testResult = .failed(detail)
        case .unreachable(let detail):
            testResult = .failed("Couldn't reach the server: \(detail)")
        }
        isTesting = false
    }
}

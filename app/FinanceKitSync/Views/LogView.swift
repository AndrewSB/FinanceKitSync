//
//  LogView.swift
//  FinanceKitSync
//
import SwiftUI

struct LogView: View {
    @State private var store = LogStore.shared
    @State private var showingShare = false

    var body: some View {
        List {
            if store.entries.isEmpty {
                ContentUnavailableView(
                    "No activity yet",
                    systemImage: "list.bullet.rectangle",
                    description: Text("Run a sync and the details will show up here.")
                )
            } else {
                // Newest first — the interesting line after a failure is the last one.
                ForEach(store.entries.reversed()) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.message)
                            .font(.callout)
                        Text(entry.date, format: .dateTime.month().day().hour().minute().second())
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Activity")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showingShare = true
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    Button(role: .destructive) {
                        store.clear()
                    } label: {
                        Label("Clear", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingShare) {
            ShareSheet(text: store.exportText())
        }
    }
}

/// UIActivityViewController bridge — SwiftUI's ShareLink can't share a
/// generated string as a file without writing it to disk first.
private struct ShareSheet: UIViewControllerRepresentable {
    let text: String

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [text], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

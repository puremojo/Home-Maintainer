//
//  ViewsMoreView.swift
//  Home Maintainer
//

import SwiftUI
import UIKit

struct MoreView: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink(value: "documents") {
                    Label("Documents", systemImage: "folder.fill")
                }
                NavigationLink(value: "providers") {
                    Label("Service Providers", systemImage: "person.2.fill")
                }
                Section {
                    NavigationLink(value: "syncLog") {
                        Label("Sync Log", systemImage: "icloud.and.arrow.down")
                    }
                } footer: {
                    Text("Diagnostic log of iCloud sync and home-sharing activity, for troubleshooting without a Mac attached.")
                }
            }
            .navigationTitle("More")
            .navigationDestination(for: String.self) { destination in
                switch destination {
                case "documents":
                    DocumentsView()
                case "providers":
                    ServiceProvidersContent()
                case "syncLog":
                    SyncLogView()
                default:
                    EmptyView()
                }
            }
        }
    }
}

// MARK: - Sync Log (on-device diagnostic viewer — no cable/Console.app needed)

struct SyncLogView: View {
    @Environment(CloudSharingService.self) private var cloudSharingService
    @State private var didCopy = false

    var body: some View {
        List {
            if cloudSharingService.diagnosticLog.isEmpty {
                Text("No sync activity logged yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(cloudSharingService.diagnosticLog.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
        }
        .navigationTitle("Sync Log")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(didCopy ? "Copied" : "Copy") {
                    UIPasteboard.general.string = cloudSharingService.diagnosticLog.joined(separator: "\n")
                    didCopy = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { didCopy = false }
                }
                .disabled(cloudSharingService.diagnosticLog.isEmpty)
            }
            ToolbarItem(placement: .secondaryAction) {
                Button("Clear", role: .destructive) {
                    cloudSharingService.clearDiagnosticLog()
                }
                .disabled(cloudSharingService.diagnosticLog.isEmpty)
            }
        }
    }
}

#Preview {
    MoreView()
        .environment(HomeManager())
}

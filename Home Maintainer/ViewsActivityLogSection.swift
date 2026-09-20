//
//  ViewsActivityLogSection.swift
//  Home Maintainer
//
//  Shared "who created/last edited this" footer, shown at the bottom of every item's detail
//  view (tasks, projects, documents, appliances, providers).
//

import SwiftUI

struct ActivityLogSection: View {
    let itemName: String
    let createdByName: String?
    let createdAt: Date
    let editedByName: String?
    let editedAt: Date?

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M/d/yyyy, h:mm:ss a"
        return f
    }()

    var body: some View {
        Section("Activity") {
            Text("\(createdByName ?? "Unknown") created \(itemName) at \(Self.formatter.string(from: createdAt))")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let editedAt {
                Text("\(editedByName ?? "Unknown") edited \(itemName) at \(Self.formatter.string(from: editedAt))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

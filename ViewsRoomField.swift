//
//  ViewsRoomField.swift
//  Home Maintainer
//
//  Created by Michael Estrada on 11/11/24.
//

import SwiftUI
import SwiftData

/// A "Room" section with a free-text field plus tappable suggestions drawn from
/// rooms already entered on other tasks (e.g. tap "Kitchen" to reuse it).
struct RoomFieldSection: View {
    @Binding var room: String
    @Query private var tasks: [MaintenanceTask]

    /// Distinct, non-empty rooms used on existing tasks, filtered to match what
    /// the user has typed and excluding an exact match of the current value.
    private var suggestions: [String] {
        let trimmed = room.trimmingCharacters(in: .whitespaces)

        let unique = Set(tasks.compactMap { task -> String? in
            let value = task.room.trimmingCharacters(in: .whitespaces)
            return value.isEmpty ? nil : value
        })

        return unique
            .filter { trimmed.isEmpty || $0.localizedCaseInsensitiveContains(trimmed) }
            .filter { $0.caseInsensitiveCompare(trimmed) != .orderedSame }
            .sorted()
    }

    var body: some View {
        Section("Room") {
            TextField("Room (e.g. Kitchen)", text: $room)

            if !suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(suggestions, id: \.self) { suggestion in
                            Button {
                                room = suggestion
                            } label: {
                                Text(suggestion)
                                    .font(.caption)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Capsule().fill(Color.blue.opacity(0.15)))
                                    .foregroundStyle(.blue)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
}

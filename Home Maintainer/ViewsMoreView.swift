//
//  ViewsMoreView.swift
//  Home Maintainer
//

import SwiftUI

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
            }
            .navigationTitle("More")
            .navigationDestination(for: String.self) { destination in
                switch destination {
                case "documents":
                    DocumentsView()
                case "providers":
                    ServiceProvidersContent()
                default:
                    EmptyView()
                }
            }
        }
    }
}

#Preview {
    MoreView()
        .environment(HomeManager())
}

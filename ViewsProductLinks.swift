//
//  ViewsProductLinks.swift
//  Home Maintainer
//
//  Created by Michael Estrada on 11/11/24.
//

import SwiftUI
import SwiftData

// MARK: - Draft (used by the "Add" screens before the parent object exists)

/// A lightweight, editable stand-in for a `ProductLink` used while composing a
/// new task or project that hasn't been saved yet.
struct ProductDraft: Identifiable {
    let id = UUID()
    var name: String = ""
    var urlString: String = ""

    var isEmpty: Bool {
        name.trimmingCharacters(in: .whitespaces).isEmpty &&
        urlString.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

// MARK: - Add screens: inline editable fields bound to drafts

/// Two stacked fields: a product name (e.g. "Shock") and its link.
struct ProductLinkFieldRow: View {
    @Binding var name: String
    @Binding var urlString: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("Product (e.g. Shock)", text: $name)
            TextField("Link", text: $urlString)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
        }
    }
}

/// A "Products" section for the Add screens. Operates on an array of drafts so
/// nothing is written to the model until the parent is saved.
struct DraftProductsSection: View {
    @Binding var drafts: [ProductDraft]

    var body: some View {
        Section("Products") {
            ForEach($drafts) { $draft in
                ProductLinkFieldRow(name: $draft.name, urlString: $draft.urlString)
            }
            .onDelete { drafts.remove(atOffsets: $0) }

            Button {
                drafts.append(ProductDraft())
            } label: {
                Label("Add Product", systemImage: "plus.circle")
            }
        }
    }
}

// MARK: - Detail screens: tappable link rows + edit/add via a sheet

/// A read-only row that renders a product as a tappable link when a valid URL
/// is present, falling back to plain text otherwise.
struct ProductLinkDisplayRow: View {
    let product: ProductLink

    private var displayName: String {
        product.name.trimmingCharacters(in: .whitespaces).isEmpty ? "Product" : product.name
    }

    var body: some View {
        if let url = product.url {
            Link(destination: url) {
                HStack {
                    Text(displayName)
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "arrow.up.right.square")
                        .foregroundStyle(.blue)
                }
            }
        } else {
            HStack {
                Text(displayName)
                Spacer()
                Text(product.urlString.isEmpty ? "No link" : product.urlString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// A "Products" section for the detail screens. Shows tappable links while
/// viewing; swipe a row to edit or delete, and tap "Add Product" to add one.
/// `attach`/`detach` wire a product to (or from) its parent's relationship.
struct LiveProductsSection: View {
    @Environment(\.modelContext) private var modelContext

    let products: [ProductLink]
    let attach: (ProductLink) -> Void
    let detach: (ProductLink) -> Void

    @State private var isAddingProduct = false
    @State private var editingProduct: ProductLink?

    var body: some View {
        Section("Products") {
            ForEach(products) { product in
                ProductLinkDisplayRow(product: product)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            detach(product)
                            modelContext.delete(product)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }

                        Button {
                            editingProduct = product
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
            }

            Button {
                isAddingProduct = true
            } label: {
                Label("Add Product", systemImage: "plus.circle")
            }
        }
        .sheet(isPresented: $isAddingProduct) {
            ProductLinkEditorSheet(title: "Add Product", name: "", urlString: "") { name, urlString in
                let product = ProductLink(name: name, urlString: urlString)
                modelContext.insert(product)
                attach(product)
            }
        }
        .sheet(item: $editingProduct) { product in
            ProductLinkEditorSheet(title: "Edit Product", name: product.name, urlString: product.urlString) { name, urlString in
                product.name = name
                product.urlString = urlString
            }
        }
    }
}

/// A small modal form for entering or editing a product's name and link.
struct ProductLinkEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    @State private var name: String
    @State private var urlString: String
    let onSave: (String, String) -> Void

    init(title: String, name: String, urlString: String, onSave: @escaping (String, String) -> Void) {
        self.title = title
        self._name = State(initialValue: name)
        self._urlString = State(initialValue: urlString)
        self.onSave = onSave
    }

    private var isEmpty: Bool {
        name.trimmingCharacters(in: .whitespaces).isEmpty &&
        urlString.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Product") {
                    TextField("Name (e.g. Shock)", text: $name)
                    TextField("Link", text: $urlString)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(name, urlString)
                        dismiss()
                    }
                    .disabled(isEmpty)
                }
            }
        }
    }
}

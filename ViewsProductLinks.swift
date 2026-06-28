//
//  ViewsProductLinks.swift
//  Home Maintainer
//
//  Created by Michael Estrada on 11/11/24.
//

import SwiftUI
import SwiftData
import PhotosUI

// MARK: - Draft (used by the "Add" screens before the parent object exists)

/// A lightweight, editable stand-in for a `ProductLink` used while composing a
/// new task or project that hasn't been saved yet.
struct ProductDraft: Identifiable {
    let id = UUID()
    var name: String = ""
    var urlString: String = ""
    var imageData: Data? = nil

    var isEmpty: Bool {
        name.trimmingCharacters(in: .whitespaces).isEmpty &&
        urlString.trimmingCharacters(in: .whitespaces).isEmpty &&
        imageData == nil
    }
}

// MARK: - Reusable picture picker

/// Lets the user pick (or remove) a single picture, exposing the raw image data.
struct ProductImagePicker: View {
    @Binding var imageData: Data?
    @State private var pickerItem: PhotosPickerItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let imageData, let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            HStack {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label(imageData == nil ? "Add Picture" : "Change Picture", systemImage: "photo")
                }

                if imageData != nil {
                    Spacer()
                    Button(role: .destructive) {
                        imageData = nil
                    } label: {
                        Label("Remove", systemImage: "trash")
                    }
                }
            }
        }
        .onChange(of: pickerItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self) {
                    imageData = data
                }
            }
        }
    }
}

// MARK: - Add screens: inline editable fields bound to drafts

/// Two stacked fields: a product name (e.g. "Shock") and its link.
struct ProductLinkFieldRow: View {
    @Binding var name: String
    @Binding var urlString: String
    @Binding var imageData: Data?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Product (e.g. Shock)", text: $name)
            TextField("Link", text: $urlString)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)

            ProductImagePicker(imageData: $imageData)
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
                ProductLinkFieldRow(name: $draft.name, urlString: $draft.urlString, imageData: $draft.imageData)
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

    @State private var showingFullImage = false

    private var displayName: String {
        product.name.trimmingCharacters(in: .whitespaces).isEmpty ? "Product" : product.name
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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

            if let imageData = product.imageData, let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .onTapGesture {
                        showingFullImage = true
                    }
                    .fullScreenCover(isPresented: $showingFullImage) {
                        FullScreenImageView(uiImage: uiImage)
                    }
            }
        }
    }
}

/// A full-screen, zoomable viewer for a product picture.
struct FullScreenImageView: View {
    @Environment(\.dismiss) private var dismiss
    let uiImage: UIImage

    @State private var scale: CGFloat = 1.0

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale)
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            scale = max(1.0, value)
                        }
                        .onEnded { _ in
                            withAnimation { scale = 1.0 }
                        }
                )

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.5))
                    .padding()
            }
        }
    }
}

/// A "Products" section for the detail screens. Shows tappable links while
/// viewing; swipe a row to edit or delete, and tap "Add Product" to add one.
/// `attach`/`detach` wire a product to (or from) its parent's relationship.
/// Identifies which editor sheet to present. The detail screens own this state
/// and present a single `.sheet` at the `List` level — presenting from inside a
/// `Section` causes the List to dismiss the sheet on first appearance.
enum ProductEditorTarget: Identifiable {
    case add
    case edit(ProductLink)

    var id: String {
        switch self {
        case .add: return "add"
        case .edit(let product): return product.id.uuidString
        }
    }
}

struct LiveProductsSection: View {
    @Environment(\.modelContext) private var modelContext

    let products: [ProductLink]
    let detach: (ProductLink) -> Void
    let onAdd: () -> Void
    let onEdit: (ProductLink) -> Void

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
                            onEdit(product)
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
            }

            Button {
                onAdd()
            } label: {
                Label("Add Product", systemImage: "plus.circle")
            }
        }
    }
}

/// Builds the add/edit product sheet for a given target. Present this from the
/// detail screen's `List` via `.sheet(item:)`. `attach` wires a newly created
/// product to its parent's relationship.
struct ProductEditorSheet: View {
    @Environment(\.modelContext) private var modelContext

    let target: ProductEditorTarget
    let attach: (ProductLink) -> Void

    var body: some View {
        switch target {
        case .add:
            ProductLinkEditorSheet(title: "Add Product", name: "", urlString: "", imageData: nil) { name, urlString, imageData in
                let product = ProductLink(name: name, urlString: urlString, imageData: imageData)
                modelContext.insert(product)
                attach(product)
            }
        case .edit(let product):
            ProductLinkEditorSheet(title: "Edit Product", name: product.name, urlString: product.urlString, imageData: product.imageData) { name, urlString, imageData in
                product.name = name
                product.urlString = urlString
                product.imageData = imageData
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
    @State private var imageData: Data?
    let onSave: (String, String, Data?) -> Void

    init(title: String, name: String, urlString: String, imageData: Data?, onSave: @escaping (String, String, Data?) -> Void) {
        self.title = title
        self._name = State(initialValue: name)
        self._urlString = State(initialValue: urlString)
        self._imageData = State(initialValue: imageData)
        self.onSave = onSave
    }

    private var isEmpty: Bool {
        name.trimmingCharacters(in: .whitespaces).isEmpty &&
        urlString.trimmingCharacters(in: .whitespaces).isEmpty &&
        imageData == nil
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

                Section("Picture") {
                    ProductImagePicker(imageData: $imageData)
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
                        onSave(name, urlString, imageData)
                        dismiss()
                    }
                    .disabled(isEmpty)
                }
            }
        }
    }
}

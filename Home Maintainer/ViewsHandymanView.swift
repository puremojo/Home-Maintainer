//
//  HandymanView.swift
//  Home Maintainer
//
//  Created by Michael Estrada on 11/11/24.
//

import SwiftUI
import SwiftData

struct HandymanView: View {
    @Environment(OpenAIService.self) private var aiService
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ChatConversation.lastMessageAt, order: .reverse) private var conversations: [ChatConversation]
    
    @State private var showingSettings = false
    @State private var selectedConversation: ChatConversation?
    @State private var newConversation: ChatConversation?
    
    var body: some View {
        NavigationStack {
            if aiService.isConfigured {
                ConversationListView(
                    selectedConversation: $selectedConversation,
                    onNewChat: createNewConversation
                )
            } else {
                SetupView(showingSettings: $showingSettings)
            }
        }
        .sheet(isPresented: $showingSettings) {
            APIKeySettingsView()
        }
        .sheet(item: $selectedConversation) { conversation in
            ChatView(conversation: conversation)
        }
        .sheet(item: $newConversation) { conversation in
            ChatView(conversation: conversation)
                .onDisappear {
                    newConversation = nil
                }
        }
    }
    
    private func createNewConversation() {
        let conversation = ChatConversation()
        modelContext.insert(conversation)
        newConversation = conversation
    }
}

struct ConversationListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ChatConversation.lastMessageAt, order: .reverse) private var conversations: [ChatConversation]
    @Binding var selectedConversation: ChatConversation?
    let onNewChat: () -> Void
    @State private var showingSettings = false
    
    var body: some View {
        List {
            if conversations.isEmpty {
                ContentUnavailableView(
                    "No Conversations",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("Start a new chat to ask about your home maintenance")
                )
            } else {
                ForEach(conversations) { conversation in
                    Button {
                        selectedConversation = conversation
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(conversation.title)
                                .font(.headline)
                                .lineLimit(1)
                            
                            HStack {
                                Text(conversation.lastMessageAt, format: .dateTime.month().day().hour().minute())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                
                                Text("•")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                
                                Text("\(conversation.messages?.count ?? 0) messages")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .onDelete(perform: deleteConversations)
            }
        }
        .navigationTitle("hAIndyman")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
            }
            
            ToolbarItem(placement: .primaryAction) {
                Button {
                    onNewChat()
                } label: {
                    Image(systemName: "square.and.pencil")
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            APIKeySettingsView()
        }
    }
    
    private func deleteConversations(offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(conversations[index])
        }
    }
}

struct SetupView: View {
    @Binding var showingSettings: Bool
    
    var body: some View {
        ContentUnavailableView {
            Label("hAIndyman", systemImage: "wrench.and.screwdriver")
        } description: {
            Text("Your AI assistant for home maintenance")
        } actions: {
            Button {
                showingSettings = true
            } label: {
                Text("Add API Key")
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

struct ChatView: View {
    @Environment(OpenAIService.self) private var aiService
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(LocationManager.self) private var locationManager
    @Environment(LocalBusinessSearchService.self) private var searchService
    @Query private var tasks: [MaintenanceTask]
    @Query private var appliances: [Appliance]
    @Query private var providers: [ServiceProvider]
    
    @Bindable var conversation: ChatConversation
    
    @State private var messages: [ChatMessage] = []
    @State private var inputText = ""
    @State private var isLoading = false
    @State private var showingSettings = false
    @State private var errorMessage: String?
    @State private var showingImagePicker = false
    @State private var showingCamera = false
    @State private var selectedImages: [UIImage] = []
    
    var body: some View {
        VStack(spacing: 0) {
            // Drag Indicator
            RoundedRectangle(cornerRadius: 2.5)
                .fill(Color.secondary.opacity(0.5))
                .frame(width: 36, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 4)
            
            // Messages List
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                        
                        if isLoading {
                            HStack {
                                ProgressView()
                                    .padding(.leading)
                                Text("Thinking...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            .padding()
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) { _, _ in
                    if let lastMessage = messages.last {
                        withAnimation {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }
            
            // Error Message
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
                    .padding(.top, 4)
            }
            
            // Selected Images Preview
            if !selectedImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(selectedImages.indices, id: \.self) { index in
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: selectedImages[index])
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 80, height: 80)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                
                                Button {
                                    selectedImages.remove(at: index)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.white, .red)
                                }
                                .padding(4)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .frame(height: 90)
            }
            
            // Input Bar
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    // Attachment buttons
                    Menu {
                        Button {
                            showingCamera = true
                        } label: {
                            Label("Take Photo", systemImage: "camera")
                        }
                        
                        Button {
                            showingImagePicker = true
                        } label: {
                            Label("Choose Photo", systemImage: "photo")
                        }
                    } label: {
                        Image(systemName: "plus.circle")
                            .font(.title2)
                            .foregroundStyle(.blue)
                    }
                    .disabled(isLoading)
                    
                    TextField("Ask about your home...", text: $inputText, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...4)
                        .disabled(isLoading)
                    
                    Button {
                        sendMessage()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundStyle((inputText.isEmpty && selectedImages.isEmpty) ? .gray : .blue)
                    }
                    .disabled((inputText.isEmpty && selectedImages.isEmpty) || isLoading)
                }
                .padding()
            }
            .background(Color(.systemBackground))
        }
        .navigationTitle("hAIndyman")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.body.weight(.semibold))
                        Text("Chats")
                    }
                }
            }
            
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            APIKeySettingsView()
        }
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(selectedImages: $selectedImages)
        }
        .sheet(isPresented: $showingCamera) {
            CameraPicker(selectedImage: Binding(
                get: { nil },
                set: { if let image = $0 { selectedImages.append(image) } }
            ))
        }
        .onAppear {
            loadMessages()
        }
    }
    
    private func loadMessages() {
        // Convert saved conversation messages to chat messages
        messages = (conversation.messages ?? []).map { savedMessage in
            ChatMessage(
                role: savedMessage.messageRole == .user ? .user : .assistant,
                content: savedMessage.content,
                images: savedMessage.images
            )
        }
        
        // Add welcome message if empty
        if messages.isEmpty {
            messages.append(ChatMessage(
                role: .assistant,
                content: "Hi! I'm your AI handyman assistant. I can help you with home maintenance questions, task scheduling, and appliance care. Send me photos of issues and I'll help diagnose them!"
            ))
        }
    }
    
    private func sendMessage() {
        let userMessage = inputText
        let images = selectedImages
        inputText = ""
        selectedImages = []
        errorMessage = nil
        
        // Convert images to Data for saving
        let imageData = images.compactMap { $0.jpegData(compressionQuality: 0.8) }
        
        // Save user message to conversation
        conversation.addMessage(role: .user, content: userMessage, imageData: imageData)
        
        // Add user message to UI
        messages.append(ChatMessage(role: .user, content: userMessage, images: images))
        isLoading = true
        
        Task {
            do {
                // Build context about user's home
                let context = buildContext()
                
                // Get AI response with tool calling capability
                let response = try await aiService.sendMessage(userMessage.isEmpty ? "What do you see in this image?" : userMessage, images: imageData, context: context) { toolCall in
                    await handleToolCall(toolCall)
                }
                
                await MainActor.run {
                    // Save AI response to conversation
                    conversation.addMessage(role: .assistant, content: response)
                    
                    // Add to UI
                    messages.append(ChatMessage(role: .assistant, content: response))
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }
    
    private func handleToolCall(_ toolCall: ToolCall) async -> String {
        let functionName = toolCall.function.name
        let arguments = toolCall.function.arguments
        
        switch functionName {
        case "create_maintenance_task":
            return await createMaintenanceTask(from: arguments)
            
        case "create_appliance":
            return await createAppliance(from: arguments)
            
        case "search_local_providers":
            return await searchLocalProviders(from: arguments)
            
        case "add_service_provider":
            return await addServiceProvider(from: arguments)
            
        default:
            return "Unknown function: \(functionName)"
        }
    }
    
    private func createMaintenanceTask(from jsonString: String) async -> String {
        guard let data = jsonString.data(using: .utf8),
              let params = try? JSONDecoder().decode(TaskParams.self, from: data) else {
            return "Failed to parse task parameters"
        }
        
        await MainActor.run {
            let frequency: TaskFrequency
            switch params.frequency {
            case "daily": frequency = .daily
            case "weekly": frequency = .weekly
            case "biweekly": frequency = .biweekly
            case "monthly": frequency = .monthly
            case "quarterly": frequency = .quarterly
            case "biannually": frequency = .biannually
            case "annually": frequency = .annually
            default: frequency = .monthly
            }
            
            let task = MaintenanceTask(
                name: params.name,
                description: params.description,
                frequency: frequency
            )
            
            modelContext.insert(task)
        }
        
        return "✅ Created task: \(params.name) (scheduled \(params.frequency))"
    }
    
    private func createAppliance(from jsonString: String) async -> String {
        guard let data = jsonString.data(using: .utf8),
              let params = try? JSONDecoder().decode(ApplianceParams.self, from: data) else {
            return "Failed to parse appliance parameters"
        }
        
        await MainActor.run {
            let applianceType: ApplianceType
            switch params.type {
            case "refrigerator": applianceType = .refrigerator
            case "dishwasher": applianceType = .dishwasher
            case "washer": applianceType = .washer
            case "dryer": applianceType = .dryer
            case "oven": applianceType = .oven
            case "microwave": applianceType = .microwave
            case "hvac": applianceType = .hvac
            case "waterHeater": applianceType = .waterHeater
            case "garbageDisposal": applianceType = .garbageDisposal
            default: applianceType = .other
            }
            
            let appliance = Appliance(
                name: params.name,
                type: applianceType,
                manufacturer: params.manufacturer ?? ""
            )
            
            modelContext.insert(appliance)
        }
        
        return "✅ Added appliance: \(params.name)"
    }
    
    private func searchLocalProviders(from jsonString: String) async -> String {
        guard let data = jsonString.data(using: .utf8),
              let params = try? JSONDecoder().decode(SearchProviderParams.self, from: data) else {
            return "Failed to parse search parameters"
        }
        
        // Get user location
        guard let location = locationManager.userLocation else {
            return "Location not available. Please enable location services to search for local providers."
        }
        
        // Map category string to ServiceCategory
        let category: ServiceCategory
        switch params.category {
        case "electrician": category = .electrician
        case "plumber": category = .plumber
        case "generalContractor": category = .generalContractor
        case "roofer": category = .roofer
        case "hvac": category = .hvac
        case "carpenter": category = .carpenter
        case "painter": category = .painter
        case "landscaper": category = .landscaper
        case "handyman": category = .handyman
        case "appliance": category = .appliance
        default: category = .other
        }
        
        // Search for businesses
        await searchService.searchForLocalBusinesses(category: category, near: location)
        
        // Wait a moment for results
        try? await Task.sleep(for: .seconds(1))
        
        // Get results
        guard let mapItems = searchService.searchResults[category], !mapItems.isEmpty else {
            return "No \(category.rawValue.lowercased())s found nearby."
        }
        
        // Format results
        let results = mapItems.prefix(5).enumerated().map { index, item in
            let name = item.name ?? "Unknown"
            let phone = item.phoneNumber ?? "No phone"
            return "\(index + 1). \(name) - \(phone)"
        }
        
        return "Found \(mapItems.count) local \(category.rawValue.lowercased())s:\n" + results.joined(separator: "\n")
    }
    
    private func addServiceProvider(from jsonString: String) async -> String {
        guard let data = jsonString.data(using: .utf8),
              let params = try? JSONDecoder().decode(ServiceProviderParams.self, from: data) else {
            return "Failed to parse provider parameters"
        }
        
        await MainActor.run {
            let category: ServiceCategory
            switch params.category {
            case "electrician": category = .electrician
            case "plumber": category = .plumber
            case "generalContractor": category = .generalContractor
            case "roofer": category = .roofer
            case "hvac": category = .hvac
            case "carpenter": category = .carpenter
            case "painter": category = .painter
            case "landscaper": category = .landscaper
            case "handyman": category = .handyman
            case "appliance": category = .appliance
            default: category = .other
            }
            
            let provider = ServiceProvider(
                name: params.name,
                category: category,
                phoneNumber: params.phoneNumber ?? "",
                email: ""
            )
            
            if let address = params.address {
                provider.address = address
            }
            
            modelContext.insert(provider)
        }
        
        return "✅ Added \(params.name) to your providers"
    }
    
    private func buildContext() -> String {
        var context = ""
        
        if !tasks.isEmpty {
            context += "Tasks: "
            let taskNames = tasks.prefix(5).map { $0.name }
            context += taskNames.joined(separator: ", ")
            context += ". "
        }
        
        if !appliances.isEmpty {
            context += "Appliances: "
            let applianceNames = appliances.prefix(5).map { $0.name }
            context += applianceNames.joined(separator: ", ")
            context += ". "
        }
        
        if !providers.isEmpty {
            context += "Saved Providers: "
            let providerList = providers.prefix(5).map { "\($0.name) (\($0.category.rawValue))" }
            context += providerList.joined(separator: ", ")
            context += "."
        }
        
        return context
    }
}

struct MessageBubble: View {
    let message: ChatMessage
    
    var body: some View {
        HStack {
            if message.role == .user {
                Spacer()
            }
            
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                // Show images if present
                if !message.images.isEmpty {
                    ForEach(message.images.indices, id: \.self) { index in
                        Image(uiImage: message.images[index])
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                
                // Show text if present
                if !message.content.isEmpty {
                    Text(message.content)
                        .padding(12)
                        .background(message.role == .user ? Color.blue : Color(.systemGray5))
                        .foregroundStyle(message.role == .user ? .white : .primary)
                        .cornerRadius(16)
                }
                
                Text(message.timestamp, format: .dateTime.hour().minute())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 280, alignment: message.role == .user ? .trailing : .leading)
            
            if message.role == .assistant {
                Spacer()
            }
        }
    }
}

struct APIKeySettingsView: View {
    @Environment(OpenAIService.self) private var aiService
    @Environment(\.dismiss) private var dismiss
    
    @State private var apiKey: String = ""
    @State private var showingKey = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            if showingKey {
                                TextField("sk-proj-...", text: $apiKey)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .font(.system(.body, design: .monospaced))
                            } else {
                                SecureField("sk-proj-...", text: $apiKey)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .font(.system(.body, design: .monospaced))
                            }
                            
                            Button {
                                showingKey.toggle()
                            } label: {
                                Image(systemName: showingKey ? "eye.slash" : "eye")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        if aiService.isConfigured {
                            Label("API key is configured", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                } header: {
                    Text("OpenAI API Key")
                } footer: {
                    Text("Get your API key from platform.openai.com. Your key is stored securely on your device.")
                }
                
                Section {
                    Link(destination: URL(string: "https://platform.openai.com/api-keys")!) {
                        Label("Get API Key", systemImage: "key.fill")
                    }
                    
                    Link(destination: URL(string: "https://platform.openai.com/usage")!) {
                        Label("View Usage", systemImage: "chart.bar.fill")
                    }
                }
                
                if aiService.isConfigured {
                    Section {
                        Button(role: .destructive) {
                            aiService.deleteAPIKey()
                            apiKey = ""
                            dismiss()
                        } label: {
                            Label("Remove API Key", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        aiService.saveAPIKey(apiKey)
                        dismiss()
                    }
                    .disabled(apiKey.isEmpty)
                }
            }
            .onAppear {
                apiKey = aiService.apiKey ?? ""
            }
        }
    }
}

// MARK: - Models

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: Role
    let content: String
    let images: [UIImage]
    let timestamp = Date()
    
    init(role: Role, content: String, images: [UIImage] = []) {
        self.role = role
        self.content = content
        self.images = images
    }
    
    enum Role {
        case user
        case assistant
    }
}

struct TaskParams: Codable {
    let name: String
    let description: String
    let frequency: String
}

struct ApplianceParams: Codable {
    let name: String
    let type: String
    let manufacturer: String?
}

struct SearchProviderParams: Codable {
    let category: String
}

struct ServiceProviderParams: Codable {
    let name: String
    let category: String
    let phoneNumber: String?
    let address: String?
}

// MARK: - Image Pickers

import PhotosUI

struct ImagePicker: UIViewControllerRepresentable {
    @Binding var selectedImages: [UIImage]
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 5
        
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: ImagePicker
        
        init(_ parent: ImagePicker) {
            self.parent = parent
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.dismiss()
            
            for result in results {
                result.itemProvider.loadObject(ofClass: UIImage.self) { image, error in
                    if let image = image as? UIImage {
                        DispatchQueue.main.async {
                            self.parent.selectedImages.append(image)
                        }
                    }
                }
            }
        }
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        
        init(_ parent: CameraPicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.selectedImage = image
            }
            parent.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

#Preview {
    HandymanView()
        .environment(OpenAIService())
        .modelContainer(for: [MaintenanceTask.self, Appliance.self], inMemory: true)
}


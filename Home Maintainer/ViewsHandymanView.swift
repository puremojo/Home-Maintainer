//
//  HandymanView.swift
//  Home Maintainer
//
//  Created by Michael Estrada on 11/11/24.
//

import SwiftUI
import SwiftData

struct ConversationDestination: Identifiable, Hashable {
    let id = UUID()
    let conversation: ChatConversation
    let scrollToMessageID: UUID?

    static func == (lhs: ConversationDestination, rhs: ConversationDestination) -> Bool {
        lhs.id == rhs.id
    }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct ChatSearchResult: Identifiable {
    var id: UUID { message.id }
    let conversation: ChatConversation
    let message: ChatMessageData
    let snippet: AttributedString
}

struct HandymanView: View {
    @Environment(GeminiService.self) private var aiService
    @Environment(HomeManager.self) private var homeManager
    @Environment(\.modelContext) private var modelContext

    @State private var showingHomePicker = false
    @State private var navigationTarget: ConversationDestination?
    @State private var showingAccount = false

    var body: some View {
        NavigationStack {
            if aiService.isConfigured {
                ConversationListView(
                    homeID: homeManager.currentHome?.id,
                    navigationTarget: $navigationTarget,
                    showingHomePicker: $showingHomePicker,
                    showingAccount: $showingAccount,
                    onNewChat: createNewConversation
                )
                .navigationDestination(item: $navigationTarget) { target in
                    ChatView(conversation: target.conversation, scrollToMessageID: target.scrollToMessageID)
                }
            } else {
                SetupView()
            }
        }
        .sheet(isPresented: $showingHomePicker) {
            HomePickerView()
        }
        .sheet(isPresented: $showingAccount) {
            SubscriptionView()
        }
    }

    private func createNewConversation() {
        let conversation = ChatConversation()
        conversation.home = homeManager.currentHome
        modelContext.insert(conversation)
        navigationTarget = ConversationDestination(conversation: conversation, scrollToMessageID: nil)
    }
}

struct ConversationListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthService.self) private var authService
    @Query(sort: \ChatConversation.lastMessageAt, order: .reverse) private var allConversations: [ChatConversation]
    @Query(sort: \ChatMessageData.timestamp, order: .reverse) private var allMessages: [ChatMessageData]

    let homeID: UUID?
    @Binding var navigationTarget: ConversationDestination?
    @Binding var showingHomePicker: Bool
    @Binding var showingAccount: Bool
    let onNewChat: () -> Void

    @State private var searchText = ""

    private var conversations: [ChatConversation] {
        guard let id = homeID else { return [] }
        return allConversations.filter { $0.home?.id == id }
    }

    private var searchResults: [ChatSearchResult] {
        guard !searchText.isEmpty else { return [] }
        let query = searchText
        return allMessages.compactMap { message in
            guard let conversation = message.conversation,
                  conversation.home?.id == homeID,
                  message.content.localizedCaseInsensitiveContains(query)
            else { return nil }
            return ChatSearchResult(
                conversation: conversation,
                message: message,
                snippet: makeSnippet(content: message.content, query: query)
            )
        }
    }

    private func makeSnippet(content: String, query: String) -> AttributedString {
        guard let matchRange = content.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return AttributedString(String(content.prefix(120)))
        }
        let contextStart = content.index(matchRange.lowerBound, offsetBy: -40, limitedBy: content.startIndex) ?? content.startIndex
        let contextEnd = content.index(matchRange.upperBound, offsetBy: 80, limitedBy: content.endIndex) ?? content.endIndex
        let prefix = contextStart > content.startIndex ? "…" : ""
        let suffix = contextEnd < content.endIndex ? "…" : ""
        let window = prefix + content[contextStart..<contextEnd] + suffix

        var attributed = AttributedString(window)
        if let highlightRange = attributed.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) {
            attributed[highlightRange].font = .body.bold()
        }
        return attributed
    }

    var body: some View {
        Group {
            if homeID == nil {
                ContentUnavailableView {
                    Label("No Home Selected", systemImage: "house")
                } description: {
                    Text("Create or select a home to use hAIndyman.")
                } actions: {
                    Button("Select Home") { showingHomePicker = true }
                        .buttonStyle(.borderedProminent)
                }
            } else if !searchText.isEmpty {
                if searchResults.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    List(searchResults) { result in
                        Button {
                            navigationTarget = ConversationDestination(
                                conversation: result.conversation,
                                scrollToMessageID: result.message.id
                            )
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(result.conversation.title)
                                    .font(.headline)
                                    .lineLimit(1)
                                Text(result.snippet)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            } else {
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
                                navigationTarget = ConversationDestination(conversation: conversation, scrollToMessageID: nil)
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
            }
        }
        .searchable(text: $searchText, prompt: "Search conversations")
        .navigationTitle("hAIndyman")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                HomePickerButton(showingPicker: $showingHomePicker)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAccount = true
                } label: {
                    Image(systemName: "person.circle")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    onNewChat()
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .disabled(homeID == nil)
            }
        }
    }

    private func deleteConversations(offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(conversations[index])
        }
    }
}

struct SetupView: View {
    var body: some View {
        ContentUnavailableView {
            Label("hAIndyman", systemImage: "wrench.and.screwdriver")
        } description: {
            Text("Gemini is not available. Please ensure your Firebase project is configured correctly.")
        }
    }
}

struct ChatView: View {
    @Environment(GeminiService.self) private var aiService
    @Environment(AuthService.self) private var authService
    @Environment(\.modelContext) private var modelContext
    @Environment(HomeManager.self) private var homeManager
    @Environment(LocationManager.self) private var locationManager
    @Environment(LocalBusinessSearchService.self) private var searchService
    @Query private var tasks: [MaintenanceTask]
    @Query private var appliances: [Appliance]
    @Query private var providers: [ServiceProvider]

    @Bindable var conversation: ChatConversation
    var scrollToMessageID: UUID? = nil

    @State private var messages: [ChatMessage] = []
    @State private var scrollTargetID: UUID?
    @State private var inputText = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingImagePicker = false
    @State private var showingCamera = false
    @State private var selectedImages: [UIImage] = []
    
    var body: some View {
        VStack(spacing: 0) {
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
                .onChange(of: scrollTargetID) { _, targetID in
                    if let targetID {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            withAnimation {
                                proxy.scrollTo(targetID, anchor: .center)
                            }
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
        messages = (conversation.messages ?? []).map { savedMessage in
            let msg = ChatMessage(
                role: savedMessage.messageRole == .user ? .user : .assistant,
                content: savedMessage.content,
                images: savedMessage.images
            )
            if savedMessage.id == scrollToMessageID {
                scrollTargetID = msg.id
            }
            return msg
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
        errorMessage = nil

        guard !authService.subscriptionData.isAtLimit else {
            errorMessage = GeminiError.quotaExceeded.errorDescription
            return
        }

        inputText = ""
        selectedImages = []
        
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
                
                // Save full response to store immediately
                await MainActor.run {
                    conversation.addMessage(role: .assistant, content: response)
                    isLoading = false
                }
                
                // Animate response word-by-word
                let streamId = UUID()
                await MainActor.run {
                    messages.append(ChatMessage(role: .assistant, content: "", id: streamId))
                }
                let words = response.components(separatedBy: " ")
                let delayMs = UInt64(max(10, min(60, 4000 / max(words.count, 1))))
                var accumulated = ""
                for (i, word) in words.enumerated() {
                    accumulated += (i == 0 ? "" : " ") + word
                    let text = accumulated
                    await MainActor.run {
                        if let idx = messages.firstIndex(where: { $0.id == streamId }) {
                            messages[idx].content = text
                        }
                    }
                    try? await Task.sleep(nanoseconds: delayMs * 1_000_000)
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

        case "create_repair_project":
            return await createRepairProject(from: arguments)
            
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
            task.home = homeManager.currentHome
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
            appliance.home = homeManager.currentHome
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
            
            provider.home = homeManager.currentHome
            modelContext.insert(provider)
        }
        
        return "✅ Added \(params.name) to your providers"
    }

    private func createRepairProject(from jsonString: String) async -> String {
        guard let data = jsonString.data(using: .utf8),
              let params = try? JSONDecoder().decode(RepairProjectParams.self, from: data) else {
            return "Failed to parse project parameters"
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

            let priority: ProjectPriority
            switch params.priority ?? "medium" {
            case "low": priority = .low
            case "high": priority = .high
            default: priority = .medium
            }

            let project = RepairProject(
                title: params.title,
                description: params.description,
                category: category,
                priority: priority
            )
            project.home = homeManager.currentHome
            modelContext.insert(project)
        }

        return "✅ Created project: \(params.title)"
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
                    if message.role == .assistant {
                        let attributed = (try? AttributedString(
                            markdown: message.content,
                            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
                        )) ?? AttributedString(message.content)
                        Text(attributed)
                            .tint(.blue)
                            .textSelection(.enabled)
                            .padding(12)
                            .background(Color(.systemGray5))
                            .foregroundStyle(.primary)
                            .cornerRadius(16)
                    } else {
                        Text(message.content)
                            .padding(12)
                            .background(Color.blue)
                            .foregroundStyle(.white)
                            .cornerRadius(16)
                    }
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

// MARK: - Models

struct ChatMessage: Identifiable {
    let id: UUID
    let role: Role
    var content: String
    let images: [UIImage]
    let timestamp: Date
    
    init(role: Role, content: String, images: [UIImage] = [], id: UUID = UUID()) {
        self.id = id
        self.role = role
        self.content = content
        self.images = images
        self.timestamp = Date()
    }
    
    enum Role {
        case user
        case assistant
    }
}

private struct TaskParams: Codable {
    let name: String
    let description: String
    let frequency: String
}

private struct ApplianceParams: Codable {
    let name: String
    let type: String
    let manufacturer: String?
}

private struct SearchProviderParams: Codable {
    let category: String
}

private struct ServiceProviderParams: Codable {
    let name: String
    let category: String
    let phoneNumber: String?
    let address: String?
}

private struct RepairProjectParams: Codable {
    let title: String
    let description: String
    let category: String
    let priority: String?
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
        .environment(GeminiService())
        .modelContainer(for: [MaintenanceTask.self, Appliance.self], inMemory: true)
}


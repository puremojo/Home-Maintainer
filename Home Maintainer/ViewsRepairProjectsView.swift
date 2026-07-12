//
//  RepairProjectsView.swift
//  Home Maintainer
//
//  Created by Michael Estrada on 11/11/24.
//

import SwiftUI
import SwiftData

struct RepairProjectsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(HomeManager.self) private var homeManager
    @Query private var allProjectsRaw: [RepairProject]
    @State private var showingAddProject = false
    @State private var showingHomePicker = false
    @State private var selectedStatus: ProjectStatus?

    private var allProjects: [RepairProject] {
        guard let home = homeManager.currentHome else { return [] }
        return allProjectsRaw.filter { $0.home?.id == home.id }
    }

    var projects: [RepairProject] {
        allProjects.sorted { p1, p2 in
            if p1.priority != p2.priority { return p1.priority > p2.priority }
            if p1.status.rawValue != p2.status.rawValue { return p1.status.rawValue < p2.status.rawValue }
            return p1.createdAt > p2.createdAt
        }
    }
    
    var filteredProjects: [RepairProject] {
        if let status = selectedStatus {
            return projects.filter { $0.status == status }
        }
        return projects
    }
    
    var activeProjects: [RepairProject] {
        projects.filter { $0.status != .completed && $0.status != .cancelled }
    }
    
    var completedProjects: [RepairProject] {
        projects.filter { $0.status == .completed }
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if homeManager.currentHome == nil {
                    ContentUnavailableView {
                        Label("No Home Selected", systemImage: "house")
                    } description: {
                        Text("Create or select a home to manage repair projects.")
                    } actions: {
                        Button("Select Home") { showingHomePicker = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        if projects.isEmpty {
                            ContentUnavailableView(
                                "No Projects",
                                systemImage: "hammer",
                                description: Text("Track repair projects, quotes, and invoices")
                            )
                        } else {
                            if !activeProjects.isEmpty && selectedStatus == nil {
                                Section("Active Projects") {
                                    ForEach(activeProjects) { project in
                                        NavigationLink(destination: RepairProjectDetailView(project: project)) {
                                            ProjectRow(project: project)
                                        }
                                    }
                                    .onDelete { offsets in
                                        deleteProjects(at: offsets, from: activeProjects)
                                    }
                                }
                            }
                            if !completedProjects.isEmpty && selectedStatus == nil {
                                Section("Completed Projects") {
                                    ForEach(completedProjects) { project in
                                        NavigationLink(destination: RepairProjectDetailView(project: project)) {
                                            ProjectRow(project: project)
                                        }
                                    }
                                    .onDelete { offsets in
                                        deleteProjects(at: offsets, from: completedProjects)
                                    }
                                }
                            }
                            if selectedStatus != nil {
                                ForEach(filteredProjects) { project in
                                    NavigationLink(destination: RepairProjectDetailView(project: project)) {
                                        ProjectRow(project: project)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Repair Projects")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HomePickerButton(showingPicker: $showingHomePicker)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button("All Projects") { selectedStatus = nil }
                        Divider()
                        ForEach(ProjectStatus.allCases, id: \.self) { status in
                            Button {
                                selectedStatus = status
                            } label: {
                                Label(status.rawValue, systemImage: status.systemImage)
                            }
                        }
                    } label: {
                        Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddProject = true
                    } label: {
                        Label("Add Project", systemImage: "plus")
                    }
                    .disabled(homeManager.currentHome == nil)
                }
            }
            .sheet(isPresented: $showingAddProject) {
                AddRepairProjectView(home: homeManager.currentHome)
            }
            .sheet(isPresented: $showingHomePicker) {
                HomePickerView()
            }
        }
    }
    
    private func deleteProjects(at offsets: IndexSet, from projectList: [RepairProject]) {
        for index in offsets {
            modelContext.delete(projectList[index])
        }
    }
}

struct ProjectRow: View {
    let project: RepairProject
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(project.title)
                    .font(.headline)
                
                Spacer()
                
                HStack(spacing: 4) {
                    Image(systemName: project.priority.systemImage)
                        .font(.caption)
                        .foregroundStyle(project.priority.color)
                    
                    Image(systemName: project.status.systemImage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            HStack {
                Label(project.category.rawValue, systemImage: project.category.systemImage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Text("•")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Text(project.status.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Text("•")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                HStack(spacing: 2) {
                    Image(systemName: project.priority.systemImage)
                        .font(.caption2)
                    Text(project.priority.displayName)
                }
                .font(.caption)
                .foregroundStyle(project.priority.color)
            }
            
            if let hiredProvider = project.hiredProvider {
                Text("Hired: \(hiredProvider.name)")
                    .font(.caption)
                    .foregroundStyle(.blue)
            }
            
            if let quotesCount = project.quotes?.count, quotesCount > 0 {
                Text("\(quotesCount) quote\(quotesCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    RepairProjectsView()
        .modelContainer(for: RepairProject.self, inMemory: true)
}

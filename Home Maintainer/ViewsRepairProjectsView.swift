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
    @Query private var allProjects: [RepairProject]
    @State private var showingAddProject = false
    @State private var selectedStatus: ProjectStatus?
    
    var projects: [RepairProject] {
        // Sort by priority (high to low), then by status, then by creation date
        allProjects.sorted { project1, project2 in
            if project1.priority != project2.priority {
                return project1.priority > project2.priority  // High priority first
            }
            if project1.status.rawValue != project2.status.rawValue {
                return project1.status.rawValue < project2.status.rawValue
            }
            return project1.createdAt > project2.createdAt
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
            .navigationTitle("Repair Projects")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddProject = true
                    } label: {
                        Label("Add Project", systemImage: "plus")
                    }
                }
                
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button("All Projects") {
                            selectedStatus = nil
                        }
                        
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
            }
            .sheet(isPresented: $showingAddProject) {
                AddRepairProjectView()
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

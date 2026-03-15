//
//  ContentView.swift
//  Home Maintainer
//
//  Created by Michael Estrada on 11/11/24.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            Tab("Tasks", systemImage: "checklist") {
                MaintenanceTasksView()
            }
            
            Tab("Appliances", systemImage: "refrigerator") {
                AppliancesView()
            }
            
            Tab("Providers", systemImage: "person.2") {
                ServiceProvidersView()
            }
            
            Tab("Projects", systemImage: "hammer") {
                RepairProjectsView()
            }
            
            Tab("hAIndyman", systemImage: "wrench.and.screwdriver") {
                HandymanView()
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [
            MaintenanceTask.self,
            MaintenanceRecord.self,
            Appliance.self,
            ServiceProvider.self,
            RepairProject.self,
            ProjectContact.self,
            Quote.self,
            Invoice.self
        ], inMemory: true)
}

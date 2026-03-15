# Home Maintainer App - Architecture Overview

## Summary
This is a comprehensive home maintenance tracking app built with SwiftUI and SwiftData for iOS. It allows users to manage maintenance tasks, track appliances, maintain a directory of local service providers, and manage repair projects with quotes and invoices.

## Data Models

### MaintenanceTask
- Tracks recurring tasks (HVAC filters, lawn mowing, etc.)
- Supports various frequencies (daily, weekly, monthly, etc.)
- Automatically calculates next due dates
- Tracks completion history through MaintenanceRecord
- Can mark tasks as active/inactive
- Shows overdue status

### Appliance
- Tracks household appliances and equipment
- Stores manufacturer, model number, purchase date
- Can link to maintenance tasks
- Tracks warranty expiration

### ServiceProvider
- Local service providers by category (plumber, electrician, etc.)
- Contact information (phone, email, address, website)
- Rating system (0-5 stars)
- Favorite marking
- Searchable by category

### RepairProject
- Tracks repair/renovation projects
- Multiple status levels (planning, quotes, hired, in progress, completed)
- Links to hired provider
- Tracks multiple contacts with providers
- Stores multiple quotes
- Can have one invoice
- Tracks start and completion dates

### Supporting Models
- **MaintenanceRecord**: History of completed maintenance tasks
- **ProjectContact**: Records of contacting providers for a project
- **Quote**: Price quotes from providers for projects
- **Invoice**: Final invoice for completed work

## App Structure

### Tab-Based Navigation
1. **Tasks Tab**: View and manage all maintenance tasks
2. **Appliances Tab**: Track appliances and their maintenance
3. **Providers Tab**: Directory of local service providers
4. **Projects Tab**: Manage repair/renovation projects

### Key Features

#### Maintenance Tasks
- Add tasks with custom frequencies
- Mark tasks as completed with notes
- View overdue and upcoming tasks separately
- Track completion history

#### Appliances
- Categorized by type with custom icons
- Track warranty status
- Link to related maintenance tasks
- Full edit capability

#### Service Providers
- Organized by service category
- Filter by category
- Rate providers (5-star system)
- Mark favorites
- Click-to-call and email links

#### Repair Projects
- Track project status through lifecycle
- Record all provider contacts
- Collect multiple quotes
- Compare quote amounts
- Track which provider was hired
- Record final invoice and payment status
- Separate active and completed projects

## Data Persistence
All data is persisted using SwiftData with a shared ModelContainer configured in the app file.

## Next Steps / Potential Enhancements
- Add notifications/reminders for overdue tasks
- Photo attachments for projects/appliances
- Export project summaries/invoices
- Dashboard/home view with summary statistics
- Search functionality across all entities
- Backup/export to CSV or JSON
- Calendar view for scheduled tasks
- Widgets for upcoming tasks

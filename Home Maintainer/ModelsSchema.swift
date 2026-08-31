//
//  ModelsSchema.swift
//  Home Maintainer
//
//  Programmatic NSManagedObjectModel for the Core Data migration.
//  All 16 entities are defined here in code so no .xcdatamodeld file
//  (and therefore no project.pbxproj change) is needed.
//

import CoreData
import Foundation

enum AppDataModel {

    // MARK: - Build the managed object model

    static func buildModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()

        // MARK: Attribute helpers

        func strAttr(_ name: String, optional: Bool = false, defaultValue: String = "") -> NSAttributeDescription {
            let a = NSAttributeDescription()
            a.name = name
            a.attributeType = .stringAttributeType
            a.isOptional = optional
            if !optional { a.defaultValue = defaultValue }
            return a
        }

        func uuidAttr(_ name: String, optional: Bool = false) -> NSAttributeDescription {
            let a = NSAttributeDescription()
            a.name = name
            a.attributeType = .UUIDAttributeType
            a.isOptional = optional
            return a
        }

        func dateAttr(_ name: String, optional: Bool = false) -> NSAttributeDescription {
            let a = NSAttributeDescription()
            a.name = name
            a.attributeType = .dateAttributeType
            a.isOptional = optional
            if !optional { a.defaultValue = Date(timeIntervalSince1970: 0) }
            return a
        }

        func boolAttr(_ name: String, defaultValue: Bool = false) -> NSAttributeDescription {
            let a = NSAttributeDescription()
            a.name = name
            a.attributeType = .booleanAttributeType
            a.defaultValue = NSNumber(value: defaultValue)
            return a
        }

        func doubleAttr(_ name: String, optional: Bool = false) -> NSAttributeDescription {
            let a = NSAttributeDescription()
            a.name = name
            a.attributeType = .doubleAttributeType
            a.isOptional = optional
            if !optional { a.defaultValue = NSNumber(value: 0.0) }
            return a
        }

        func int32Attr(_ name: String, defaultValue: Int32 = 0) -> NSAttributeDescription {
            let a = NSAttributeDescription()
            a.name = name
            a.attributeType = .integer32AttributeType
            a.defaultValue = NSNumber(value: defaultValue)
            return a
        }

        func dataAttr(_ name: String, external: Bool = false) -> NSAttributeDescription {
            let a = NSAttributeDescription()
            a.name = name
            a.attributeType = .binaryDataAttributeType
            a.isOptional = true
            a.allowsExternalBinaryDataStorage = external
            return a
        }

        // MARK: Relationship helpers

        func toOne(_ name: String, dest: NSEntityDescription, optional: Bool = true,
                   deleteRule: NSDeleteRule = .nullifyDeleteRule) -> NSRelationshipDescription {
            let r = NSRelationshipDescription()
            r.name = name
            r.destinationEntity = dest
            r.isOptional = optional
            r.deleteRule = deleteRule
            r.minCount = 0
            r.maxCount = 1
            return r
        }

        func toMany(_ name: String, dest: NSEntityDescription,
                    deleteRule: NSDeleteRule = .nullifyDeleteRule) -> NSRelationshipDescription {
            let r = NSRelationshipDescription()
            r.name = name
            r.destinationEntity = dest
            r.isOptional = true
            r.deleteRule = deleteRule
            r.minCount = 0
            r.maxCount = 0
            return r
        }

        // MARK: Entity descriptions
        // managedObjectClassName uses NSStringFromClass so the module prefix is always correct.

        func ent(_ name: String, _ cls: AnyClass) -> NSEntityDescription {
            let e = NSEntityDescription()
            e.name = name
            e.managedObjectClassName = NSStringFromClass(cls)
            return e
        }

        let homeEnt      = ent("Home",              Home.self)
        let taskEnt      = ent("MaintenanceTask",   MaintenanceTask.self)
        let recordEnt    = ent("MaintenanceRecord", MaintenanceRecord.self)
        let applianceEnt = ent("Appliance",         Appliance.self)
        let photoEnt     = ent("AppliancePhoto",    AppliancePhoto.self)
        let providerEnt  = ent("ServiceProvider",   ServiceProvider.self)
        let projectEnt   = ent("RepairProject",     RepairProject.self)
        let contactEnt   = ent("ProjectContact",    ProjectContact.self)
        let quoteEnt     = ent("Quote",             Quote.self)
        let invoiceEnt   = ent("Invoice",           Invoice.self)
        let productEnt   = ent("ProductLink",       ProductLink.self)
        let sectionEnt   = ent("DocumentSection",   DocumentSection.self)
        let homeDocEnt   = ent("HomeDocument",      HomeDocument.self)
        let convEnt      = ent("ChatConversation",  ChatConversation.self)
        let msgEnt       = ent("ChatMessageData",   ChatMessageData.self)
        let imgEnt       = ent("ChatImageData",     ChatImageData.self)

        // MARK: Attributes

        homeEnt.properties = [
            uuidAttr("id"),
            strAttr("name"),
            strAttr("address"),
            dateAttr("createdDate"),
            strAttr("ownerName"),
            boolAttr("isLocallyCreated", defaultValue: true),
        ]

        taskEnt.properties = [
            uuidAttr("id"),
            strAttr("name"),
            strAttr("taskDescription"),
            strAttr("room"),
            strAttr("frequencyEncoded", defaultValue: "monthly"),
            dateAttr("lastCompleted", optional: true),
            dateAttr("nextDue", optional: true),
            boolAttr("isActive", defaultValue: true),
            dateAttr("createdAt"),
            strAttr("homeIDString", optional: true),
            strAttr("sourceProjectIDString", optional: true),
            strAttr("taskDocumentsJSON", optional: true),
        ]

        recordEnt.properties = [
            uuidAttr("id"),
            dateAttr("completedDate"),
            strAttr("notes"),
            strAttr("action", defaultValue: "Closed"),
        ]

        applianceEnt.properties = [
            uuidAttr("id"),
            strAttr("name"),
            strAttr("typeRaw", defaultValue: "Other"),
            strAttr("manufacturer"),
            strAttr("modelNumber"),
            dateAttr("purchaseDate", optional: true),
            dateAttr("warrantyExpiration", optional: true),
            strAttr("notes"),
            strAttr("room"),
            dateAttr("createdAt"),
            strAttr("homeIDString", optional: true),
            strAttr("documentsJSON", optional: true),
        ]

        photoEnt.properties = [
            uuidAttr("id"),
            dataAttr("imageData", external: true),
            dateAttr("createdAt"),
        ]

        providerEnt.properties = [
            uuidAttr("id"),
            strAttr("name"),
            strAttr("categoryRaw", defaultValue: "Other"),
            strAttr("phoneNumber"),
            strAttr("email"),
            strAttr("address"),
            strAttr("website"),
            strAttr("notes"),
            boolAttr("isFavorite"),
            int32Attr("rating"),
            dateAttr("createdAt"),
            strAttr("homeIDString", optional: true),
            strAttr("googlePlaceID", optional: true),
            doubleAttr("googleRating", optional: true),
            strAttr("googlePriceLevel", optional: true),
            strAttr("weekdayHoursJSON", optional: true),
            strAttr("businessTypesJSON", optional: true),
        ]

        projectEnt.properties = [
            uuidAttr("id"),
            strAttr("title"),
            strAttr("projectDescription"),
            strAttr("categoryRaw", defaultValue: "Other"),
            strAttr("statusRaw", defaultValue: "Planning"),
            int32Attr("priorityRaw", defaultValue: 1),
            dateAttr("startDate", optional: true),
            dateAttr("completionDate", optional: true),
            strAttr("notes"),
            dateAttr("createdAt"),
            strAttr("homeIDString", optional: true),
            doubleAttr("totalCost", optional: true),
            strAttr("projectDocumentsJSON", optional: true),
            strAttr("workDatesJSON", optional: true),
        ]

        contactEnt.properties = [
            uuidAttr("id"),
            dateAttr("contactDate"),
            strAttr("methodRaw", defaultValue: "Phone"),
            strAttr("notes"),
            boolAttr("wasHired"),
        ]

        quoteEnt.properties = [
            uuidAttr("id"),
            doubleAttr("amount"),
            dateAttr("quoteDate"),
            dateAttr("validUntil", optional: true),
            strAttr("details"),
            boolAttr("wasAccepted"),
        ]

        invoiceEnt.properties = [
            uuidAttr("id"),
            doubleAttr("amount"),
            dateAttr("invoiceDate"),
            dateAttr("dueDate", optional: true),
            dateAttr("paidDate", optional: true),
            boolAttr("isPaid"),
            strAttr("details"),
        ]

        productEnt.properties = [
            uuidAttr("id"),
            strAttr("name"),
            strAttr("urlString"),
            dataAttr("imageData", external: true),
            dateAttr("createdAt"),
        ]

        sectionEnt.properties = [
            uuidAttr("id"),
            strAttr("name"),
            int32Attr("sortOrder"),
            strAttr("homeIDString", optional: true),
            dateAttr("createdAt"),
        ]

        homeDocEnt.properties = [
            uuidAttr("id"),
            strAttr("title"),
            dataAttr("attachmentData", external: true),
            strAttr("attachmentName", optional: true),
            strAttr("attachmentContentType", optional: true),
            strAttr("linkedTaskIDsJSON", optional: true),
            strAttr("linkedProjectIDsJSON", optional: true),
            strAttr("homeIDString", optional: true),
            strAttr("sectionIDString", optional: true),
            dateAttr("createdAt"),
        ]

        convEnt.properties = [
            uuidAttr("id"),
            strAttr("title", defaultValue: "New Chat"),
            dateAttr("createdAt"),
            dateAttr("lastMessageAt"),
            uuidAttr("homeID", optional: true),
        ]

        msgEnt.properties = [
            uuidAttr("id"),
            strAttr("role", defaultValue: "user"),
            strAttr("content"),
            dateAttr("timestamp"),
        ]

        imgEnt.properties = [
            uuidAttr("id"),
            dataAttr("imageData", external: true),
        ]

        // MARK: Relationships (create both sides, wire inverses together)

        let homeTasks      = toMany("tasks",            dest: taskEnt,      deleteRule: .cascadeDeleteRule)
        let taskHome       = toOne("home",              dest: homeEnt)
        homeTasks.inverseRelationship = taskHome;       taskHome.inverseRelationship = homeTasks

        let homeApps       = toMany("appliances",       dest: applianceEnt, deleteRule: .cascadeDeleteRule)
        let appHome        = toOne("home",              dest: homeEnt)
        homeApps.inverseRelationship = appHome;         appHome.inverseRelationship = homeApps

        let homeProvs      = toMany("serviceProviders", dest: providerEnt,  deleteRule: .cascadeDeleteRule)
        let provHome       = toOne("home",              dest: homeEnt)
        homeProvs.inverseRelationship = provHome;       provHome.inverseRelationship = homeProvs

        let homeProjs      = toMany("projects",         dest: projectEnt,   deleteRule: .cascadeDeleteRule)
        let projHome       = toOne("home",              dest: homeEnt)
        homeProjs.inverseRelationship = projHome;       projHome.inverseRelationship = homeProjs

        let homeSects      = toMany("documentSections", dest: sectionEnt,   deleteRule: .cascadeDeleteRule)
        let sectHome       = toOne("home",              dest: homeEnt)
        homeSects.inverseRelationship = sectHome;       sectHome.inverseRelationship = homeSects

        let homeHDocs      = toMany("homeDocuments",    dest: homeDocEnt,   deleteRule: .cascadeDeleteRule)
        let hdocHome       = toOne("home",              dest: homeEnt)
        homeHDocs.inverseRelationship = hdocHome;       hdocHome.inverseRelationship = homeHDocs

        let taskRecs       = toMany("records",          dest: recordEnt,    deleteRule: .cascadeDeleteRule)
        let recTask        = toOne("task",              dest: taskEnt)
        taskRecs.inverseRelationship = recTask;         recTask.inverseRelationship = taskRecs

        let taskApp        = toOne("appliance",         dest: applianceEnt)
        let appTasks       = toMany("maintenanceTasks", dest: taskEnt)
        taskApp.inverseRelationship = appTasks;         appTasks.inverseRelationship = taskApp

        let taskProds      = toMany("products",         dest: productEnt,   deleteRule: .cascadeDeleteRule)
        let prodTask       = toOne("task",              dest: taskEnt)
        taskProds.inverseRelationship = prodTask;       prodTask.inverseRelationship = taskProds

        let taskSrcProj    = toOne("sourceProject",     dest: projectEnt)
        let projSubs       = toMany("subTasks",         dest: taskEnt,      deleteRule: .cascadeDeleteRule)
        taskSrcProj.inverseRelationship = projSubs;     projSubs.inverseRelationship = taskSrcProj

        let appPhotos      = toMany("photos",           dest: photoEnt,     deleteRule: .cascadeDeleteRule)
        let photoApp       = toOne("appliance",         dest: applianceEnt)
        appPhotos.inverseRelationship = photoApp;       photoApp.inverseRelationship = appPhotos

        let appHDocs       = toMany("homeDocuments",    dest: homeDocEnt)
        let hdocLinkedApp  = toOne("linkedAppliance",   dest: applianceEnt)
        appHDocs.inverseRelationship = hdocLinkedApp;   hdocLinkedApp.inverseRelationship = appHDocs

        let projConts      = toMany("contacts",         dest: contactEnt,   deleteRule: .cascadeDeleteRule)
        let contProj       = toOne("project",           dest: projectEnt)
        projConts.inverseRelationship = contProj;       contProj.inverseRelationship = projConts

        let projQuotes     = toMany("quotes",           dest: quoteEnt,     deleteRule: .cascadeDeleteRule)
        let quoteProj      = toOne("project",           dest: projectEnt)
        projQuotes.inverseRelationship = quoteProj;     quoteProj.inverseRelationship = projQuotes

        let projProds      = toMany("products",         dest: productEnt,   deleteRule: .cascadeDeleteRule)
        let prodProj       = toOne("project",           dest: projectEnt)
        projProds.inverseRelationship = prodProj;       prodProj.inverseRelationship = projProds

        let projInv        = toOne("invoice",           dest: invoiceEnt,   deleteRule: .cascadeDeleteRule)
        let invProj        = toOne("project",           dest: projectEnt)
        projInv.inverseRelationship = invProj;          invProj.inverseRelationship = projInv

        let projHiredProv  = toOne("hiredProvider",     dest: providerEnt)
        let provHiredProjs = toMany("hiredProjects",    dest: projectEnt)
        projHiredProv.inverseRelationship = provHiredProjs; provHiredProjs.inverseRelationship = projHiredProv

        let provInvs       = toMany("invoices",         dest: invoiceEnt)
        let invProv        = toOne("provider",          dest: providerEnt)
        provInvs.inverseRelationship = invProv;         invProv.inverseRelationship = provInvs

        let provConts      = toMany("projectContacts",  dest: contactEnt)
        let contProv       = toOne("provider",          dest: providerEnt)
        provConts.inverseRelationship = contProv;       contProv.inverseRelationship = provConts

        let provQuotes     = toMany("quotes",           dest: quoteEnt)
        let quoteProv      = toOne("provider",          dest: providerEnt)
        provQuotes.inverseRelationship = quoteProv;     quoteProv.inverseRelationship = provQuotes

        let sectDocs       = toMany("documents",        dest: homeDocEnt,   deleteRule: .cascadeDeleteRule)
        let hdocSect       = toOne("section",           dest: sectionEnt)
        sectDocs.inverseRelationship = hdocSect;        hdocSect.inverseRelationship = sectDocs

        let convMsgs       = toMany("messages",         dest: msgEnt,       deleteRule: .cascadeDeleteRule)
        let msgConv        = toOne("conversation",      dest: convEnt)
        convMsgs.inverseRelationship = msgConv;         msgConv.inverseRelationship = convMsgs

        let msgImgs        = toMany("imageRecords",     dest: imgEnt,       deleteRule: .cascadeDeleteRule)
        let imgMsg         = toOne("message",           dest: msgEnt)
        msgImgs.inverseRelationship = imgMsg;           imgMsg.inverseRelationship = msgImgs

        // MARK: Assign relationships

        homeEnt.properties      += [homeTasks, homeApps, homeProvs, homeProjs, homeSects, homeHDocs]
        taskEnt.properties      += [taskHome, taskRecs, taskApp, taskProds, taskSrcProj]
        recordEnt.properties    += [recTask]
        applianceEnt.properties += [appHome, appPhotos, appTasks, appHDocs]
        photoEnt.properties     += [photoApp]
        providerEnt.properties  += [provHome, provInvs, provConts, provQuotes, provHiredProjs]
        projectEnt.properties   += [projHome, projConts, projQuotes, projProds, projInv, projHiredProv, projSubs]
        contactEnt.properties   += [contProj, contProv]
        quoteEnt.properties     += [quoteProj, quoteProv]
        invoiceEnt.properties   += [invProj, invProv]
        productEnt.properties   += [prodTask, prodProj]
        sectionEnt.properties   += [sectHome, sectDocs]
        homeDocEnt.properties   += [hdocHome, hdocLinkedApp, hdocSect]
        convEnt.properties      += [convMsgs]
        msgEnt.properties       += [msgConv, msgImgs]
        imgEnt.properties       += [imgMsg]

        model.entities = [
            homeEnt, taskEnt, recordEnt, applianceEnt, photoEnt,
            providerEnt, projectEnt, contactEnt, quoteEnt, invoiceEnt, productEnt,
            sectionEnt, homeDocEnt, convEnt, msgEnt, imgEnt
        ]

        return model
    }
}

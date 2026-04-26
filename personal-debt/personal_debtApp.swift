//
//  personal_debtApp.swift
//  personal-debt
//
//  Created by Mac on 2026/4/25.
//

import SwiftData
import SwiftUI

@main
struct personal_debtApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Debt.self,
            DebtCustomRule.self,
            CalculationRuleProfile.self,
            CreditCardDebtDetail.self,
            LoanDebtDetail.self,
            PrivateLoanDebtDetail.self,
            RepaymentPlan.self,
            RepaymentRecord.self,
            OverdueEvent.self,
            ReminderTask.self,
            StrategyScenario.self,
            SubscriptionEntitlement.self,
            SubscriptionTransactionRecord.self
        ])
        let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        let storeURL = makeStoreURL()
        let modelConfiguration: ModelConfiguration
        if isRunningTests {
            modelConfiguration = ModelConfiguration("PersonalDebtStore-Test", schema: schema, isStoredInMemoryOnly: true)
        } else {
            modelConfiguration = ModelConfiguration("PersonalDebtStore", schema: schema, url: storeURL)
        }

        do {
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            if !isRunningTests {
                seedRuleProfilesIfNeeded(container: container)
            }
            return container
        } catch {
            guard !isRunningTests else {
                fatalError("Could not create in-memory ModelContainer during tests: \(error)")
            }
            resetPersistentStore(at: storeURL)
            do {
                let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
                if !isRunningTests {
                    seedRuleProfilesIfNeeded(container: container)
                }
                return container
            } catch {
                fatalError("Could not create ModelContainer: \(error)")
            }
        }
    }()

    private static func makeStoreURL() -> URL {
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let directory = applicationSupport.appendingPathComponent("PersonalDebtData", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("personal-debt.store")
    }

    private static func resetPersistentStore(at url: URL) {
        let fileManager = FileManager.default
        let sidecarExtensions = ["", "-shm", "-wal"]
        for suffix in sidecarExtensions {
            let targetURL = suffix.isEmpty
                ? url
                : url.deletingPathExtension().appendingPathExtension(url.pathExtension + suffix)
            try? fileManager.removeItem(at: targetURL)
        }
    }

    private static func seedRuleProfilesIfNeeded(container: ModelContainer) {
        let context = ModelContext(container)
        RuleTemplateCatalogService.ensureBuiltInProfiles(modelContext: context)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}

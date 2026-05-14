import Foundation

enum DebtLifecycleStatus: String, CaseIterable, Codable, Identifiable {
    case active
    case partiallyPaid
    case overdue
    case paidOff
    case archived

    var id: String { rawValue }
}

enum RecordState: String, CaseIterable, Codable, Identifiable {
    case pending
    case partiallyPaid
    case paid

    var id: String { rawValue }
}

enum DataIsolationDomain: String, CaseIterable, Codable, Identifiable {
    case actual
    case simulated

    var id: String { rawValue }
}

enum DebtKind: String, CaseIterable, Codable, Identifiable {
    case creditCard
    case loan
    case personalLending

    var id: String { rawValue }
}

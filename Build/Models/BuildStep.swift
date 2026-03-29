import Foundation

enum BuildStep: String, CaseIterable, Identifiable {
    case ingest   = "INGEST"
    case store    = "STORE"
    case convert  = "CONVERT"
    case analyze  = "ANALYZE"
    case bom      = "BOM"
    case price    = "PRICE"
    case ecn      = "ECN/ECO"
    case credits  = "CREDITS"
    case quote    = "QUOTE"
    case order    = "ORDER"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .ingest:  return ">"
        case .store:   return "#"
        case .convert: return "~"
        case .analyze: return "?"
        case .bom:     return "="
        case .price:   return "$"
        case .ecn:     return "!"
        case .credits: return "*"
        case .quote:   return "%"
        case .order:   return "@"
        }
    }
}

enum StepState {
    case pending, running, success, failed, skipped
}

struct StepStatus: Identifiable {
    let id: BuildStep
    var state: StepState = .pending
    var message: String = ""
    var startedAt: Date?
    var completedAt: Date?

    var duration: TimeInterval? {
        guard let s = startedAt, let e = completedAt else { return nil }
        return e.timeIntervalSince(s)
    }

    var durationString: String {
        guard let d = duration else { return "" }
        return String(format: "%.1fs", d)
    }
}

struct LogLine: Identifiable {
    let id = UUID()
    let timestamp: Date
    let step: BuildStep?
    let text: String
    var isError: Bool = false
    var isHighlight: Bool = false

    var formattedTime: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: timestamp)
    }
}

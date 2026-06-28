import Foundation
import Observation

enum AppTab: Hashable {
    case inbox
    case macros
}

struct ComposerRequest: Identifiable, Equatable {
    let id = UUID()
    let date: Date
    let mode: ComposerMode
}

enum ComposerMode: Equatable {
    case instant
    case system
    case future

    var title: String {
        switch self {
        case .instant:
            "Instant Capture"
        case .system:
            "Typed Capture"
        case .future:
            "Future Note"
        }
    }
}

@MainActor
@Observable
final class AppNavigation {
    var selectedTab: AppTab = .inbox
    var selectedDate: Date = .now
    var composerRequest: ComposerRequest?

    func openDailyLog(date: Date?) {
        selectedTab = .inbox
        selectedDate = date ?? .now
    }

    func openCaptureComposer(date: Date, mode: ComposerMode = .system) {
        openDailyLog(date: date)
        composerRequest = ComposerRequest(date: date, mode: mode)
    }

    func clearComposerRequest() {
        composerRequest = nil
    }
}

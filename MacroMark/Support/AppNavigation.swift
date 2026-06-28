import Foundation
import Observation

enum AppTab: Hashable {
    case inbox
    case macros
}

struct ComposerRequest: Identifiable, Equatable {
    let id = UUID()
    let date: Date
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

    func openCaptureComposer(date: Date) {
        openDailyLog(date: date)
        composerRequest = ComposerRequest(date: date)
    }

    func clearComposerRequest() {
        composerRequest = nil
    }
}

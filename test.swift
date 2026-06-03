import SwiftUI
import WatchKit

func test() {
    WKExtension.shared().visibleInterfaceController?.presentTextInputController(withSuggestions: nil, allowedInputMode: .plain) { result in
    }
}

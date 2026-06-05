//
//  MacroMarkWidgetBundle.swift
//  MacroMarkWidget
//
//  Created by Dan Fakkeldy on 2026-06-02.
//

import WidgetKit
import SwiftUI

@main
struct MacroMarkWidgetBundle: WidgetBundle {
    var body: some Widget {
        InstantCaptureWidget()
        SystemCaptureWidget()
    }
}

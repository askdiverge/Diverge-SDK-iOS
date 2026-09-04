//
//  App.swift
//  Harness
//
//  Created by Daniel Wennberg on 2026-06-26.
//

import SwiftUI

#if canImport(AppKit)
import AppKit
#endif

@main
struct HarnessApp: App {

    init() {
#if canImport(AppKit)
        // Launched from an SPM executable there is no app bundle, so the process
        // starts as an accessory and never becomes key — promote it so the
        // window can take keyboard focus.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
#endif
    }

    var body: some Scene {
        WindowGroup {
            EntryView()
        }
    }
}

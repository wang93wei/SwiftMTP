//
//  SwiftMTPApp.swift
//  SwiftMTP
//
//  Created by SwiftMTP on 2025-12-21.
//

import SwiftUI

@main
struct SwiftMTPApp: App {
    var body: some Scene {
        WindowGroup {
            MainWindowView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 1200, height: 800)
        .windowToolbarStyle(.unified)
        
        #if os(macOS)
        Settings {
            SettingsView()
        }
        #endif
    }
}

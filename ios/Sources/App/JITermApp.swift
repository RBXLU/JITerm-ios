//
//  JITermApp.swift
//  JITerm
//

import SwiftUI

@main
struct JITermApp: App {
    @StateObject private var vm = VirtualMachine.shared
    @StateObject private var appearance = AppearanceController.shared

    init() {
        SettingsDefaults.register()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(vm)
                .environmentObject(appearance)
                .preferredColorScheme(appearance.theme.isLight ? .light : .dark)
        }
    }
}

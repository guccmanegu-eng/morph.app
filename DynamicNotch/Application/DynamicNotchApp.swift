//
//  DynamicNotchApp.swift
//  DynamicNotch
//

import SwiftUI

@main
struct DynamicNotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // DynamicNotch manages its own custom overlay windows via AppDelegate and AppContainer,
        // so we use an empty Settings scene to satisfy the SwiftUI App lifecycle.
        Settings {
            EmptyView()
        }
    }
}

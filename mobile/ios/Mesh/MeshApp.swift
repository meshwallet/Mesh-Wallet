//
//  MeshApp.swift
//  Mesh
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

@main
struct MeshApp: App {
    @StateObject private var appLock = AppLockController()

    #if canImport(UIKit)
    @UIApplicationDelegateAdaptor(MeshAppDelegate.self) private var appDelegate
    #endif

    init() {
        MeshFont.register()
        #if canImport(UIKit)
        UIWindow.appearance().backgroundColor = .black
        let inputAccent = UIColor(MeshTheme.Colors.accent)
        UITextField.appearance().tintColor = inputAccent
        UITextView.appearance().tintColor = inputAccent
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appLock)
                .environmentObject(MeshLanguageStore.shared)
        }
    }
}

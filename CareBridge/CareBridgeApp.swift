//
//  CareBridgeApp.swift
//  CareBridge
//
//  Created by Hank Chen on 2026/4/9.
//

import SwiftUI

@main
struct CareBridgeApp: App {
    @State private var isLoggedIn = false

    var body: some Scene {
        WindowGroup {
            Group {
                if isLoggedIn {
                    ContentView(isLoggedIn: $isLoggedIn)
                } else {
                    LoginView(isLoggedIn: $isLoggedIn)
                }
            }
            .preferredColorScheme(.light)
        }
    }
}

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
    @State private var userRole: UserRole = .family

    // Shared DataService — swap MockDataService() → APIDataService() when backend is ready
    private let dataService: DataService = MockDataService()

    @State private var careLogStore: CareLogStore
    @State private var todoStore: TodoStore
    @State private var calendarStore: CalendarStore
    @State private var medicationStore: MedicationStore

    init() {
        let service: DataService = MockDataService()
        _careLogStore = State(initialValue: CareLogStore(service: service))
        _todoStore = State(initialValue: TodoStore(service: service))
        _calendarStore = State(initialValue: CalendarStore(service: service))
        _medicationStore = State(initialValue: MedicationStore(service: service))
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if isLoggedIn {
                    ContentView(isLoggedIn: $isLoggedIn, userRole: userRole)
                } else {
                    LoginView(isLoggedIn: $isLoggedIn, userRole: $userRole)
                }
            }
            .environment(careLogStore)
            .environment(todoStore)
            .environment(calendarStore)
            .environment(medicationStore)
            .preferredColorScheme(.light)
        }
    }
}

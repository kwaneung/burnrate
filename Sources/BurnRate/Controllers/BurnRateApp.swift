import SwiftUI

@main
struct BurnRateApp: App {
    @StateObject private var configManager = ConfigManager()
    

    var body: some Scene {
        MenuBarExtra {
            DashboardView(configManager: configManager)
        } label: {
            Image(systemName: "flame.fill")
        }
        .menuBarExtraStyle(.window)
    }
}

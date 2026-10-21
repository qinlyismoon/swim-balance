import SwiftUI

@main
struct SwimBalanceApp: App {
    private let swimmingService: any SwimmingWorkoutReading = MockSwimmingWorkoutService()

    var body: some Scene {
        WindowGroup {
            ContentView(swimmingService: swimmingService)
        }
    }
}

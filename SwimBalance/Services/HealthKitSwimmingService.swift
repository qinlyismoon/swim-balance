import Foundation

protocol SwimmingWorkoutReading: Sendable {
    func requestAuthorization() async throws
    func recentWorkouts() async throws -> [SwimmingWorkout]
}

/// Used by previews and the demo until the HealthKit capability is enabled.
/// Generates swims against the given plan so goals line up in History.
struct MockSwimmingWorkoutService: SwimmingWorkoutReading {
    var plan: WeeklyPlan = PlanGenerator.weeklyPlan(for: SwimPreferences())

    func requestAuthorization() async throws {}
    func recentWorkouts() async throws -> [SwimmingWorkout] { MockData.workouts(for: plan) }
}

/// Integration seam for HealthKit. A later iteration can implement authorization,
/// swimming workout queries, and per-length stroke metadata here.
struct HealthKitSwimmingService: SwimmingWorkoutReading {
    func requestAuthorization() async throws {
        throw HealthKitPlaceholderError.notImplemented
    }

    func recentWorkouts() async throws -> [SwimmingWorkout] {
        throw HealthKitPlaceholderError.notImplemented
    }
}

enum HealthKitPlaceholderError: LocalizedError {
    case notImplemented

    var errorDescription: String? {
        "HealthKit integration is reserved for a future iteration."
    }
}

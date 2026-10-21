import Foundation
import Observation

/// Owns the user's preferences, keeps them on device, and regenerates the
/// weekly plan whenever they change.
@MainActor
@Observable
final class TrainingStore {
    private(set) var preferences: SwimPreferences
    private(set) var weeklyPlan: WeeklyPlan
    private(set) var hasCompletedSetup: Bool
    /// Per-day session length changes, keyed by `PlanGenerator.dayKey`.
    private(set) var minuteOverrides: [String: Int]
    /// How each swim felt, keyed by `PlanGenerator.dayKey`.
    private(set) var reflections: [String: SwimReflection]

    private let defaults: UserDefaults

    private enum Key {
        static let preferences = "swim.preferences.v3"
        static let hasCompletedSetup = "swim.hasCompletedSetup"
        static let minuteOverrides = "swim.minuteOverrides"
        static let reflections = "swim.reflections"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.data(forKey: Key.preferences)
            .flatMap { try? JSONDecoder().decode(SwimPreferences.self, from: $0) }
        let preferences = (saved ?? SwimPreferences()).normalized()
        self.preferences = preferences
        self.weeklyPlan = PlanGenerator.weeklyPlan(for: preferences)
        // Older builds saved a different format; ask again rather than guess.
        self.hasCompletedSetup = saved != nil && defaults.bool(forKey: Key.hasCompletedSetup)
        self.minuteOverrides = (defaults.dictionary(forKey: Key.minuteOverrides) as? [String: Int]) ?? [:]
        self.reflections = defaults.data(forKey: Key.reflections)
            .flatMap { try? JSONDecoder().decode([String: SwimReflection].self, from: $0) } ?? [:]
    }

    func update(_ newPreferences: SwimPreferences) {
        let normalized = newPreferences.normalized()
        guard normalized != preferences else { return }
        preferences = normalized
        weeklyPlan = PlanGenerator.weeklyPlan(for: normalized)
        save()
    }

    func completeSetup(with newPreferences: SwimPreferences) {
        update(newPreferences)
        save()
        hasCompletedSetup = true
        defaults.set(true, forKey: Key.hasCompletedSetup)
    }

    /// Change the session length for one day only; nil goes back to the default.
    func setMinutes(_ minutes: Int?, on date: Date) {
        let key = PlanGenerator.dayKey(date)
        if let minutes, minutes != preferences.availableMinutes {
            minuteOverrides[key] = minutes
        } else {
            minuteOverrides.removeValue(forKey: key)
        }
        defaults.set(minuteOverrides, forKey: Key.minuteOverrides)
    }

    func setReflection(_ reflection: SwimReflection, on date: Date) {
        let key = PlanGenerator.dayKey(date)
        reflections[key] = reflection.isEmpty ? nil : reflection
        if let data = try? JSONEncoder().encode(reflections) {
            defaults.set(data, forKey: Key.reflections)
        }
    }

    /// Demo reset: forget everything and start onboarding again.
    func resetAll() {
        defaults.removeObject(forKey: Key.preferences)
        defaults.removeObject(forKey: Key.hasCompletedSetup)
        defaults.removeObject(forKey: Key.minuteOverrides)
        defaults.removeObject(forKey: Key.reflections)
        minuteOverrides = [:]
        reflections = [:]
        preferences = SwimPreferences()
        weeklyPlan = PlanGenerator.weeklyPlan(for: preferences)
        hasCompletedSetup = false
    }

    private func save() {
        if let data = try? JSONEncoder().encode(preferences) {
            defaults.set(data, forKey: Key.preferences)
        }
    }
}

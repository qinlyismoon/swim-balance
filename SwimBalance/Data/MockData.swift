import Foundation

/// Demo data. Mock swims are generated against the current plan so that the
/// History calendar shows a believable mix of met, partly met and missed goals.
enum MockData {
    /// (distance ratio, focus-stroke ratio, logged?) cycled across past swim days.
    private static let pattern: [(distance: Double, focus: Double, logged: Bool)] = [
        (1.05, 1.10, true), (1.00, 0.60, true), (0.85, 1.00, true), (1.10, 1.20, true),
        (0, 0, false), (0.70, 0.50, true), (1.00, 1.00, true), (1.02, 0.80, true),
        (0.95, 1.10, true), (1.10, 1.00, true), (0, 0, false), (1.00, 1.05, true)
    ]

    static func workouts(for plan: WeeklyPlan, now: Date = .now, days: Int = 56,
                         calendar: Calendar = .current) -> [SwimmingWorkout] {
        let today = calendar.startOfDay(for: now)
        var result: [SwimmingWorkout] = []
        var index = 0
        for offset in stride(from: days, through: 1, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today),
                  let session = plan.session(on: day, calendar: calendar) else { continue }
            let p = pattern[index % pattern.count]
            index += 1
            guard p.logged else { continue }

            let focusStroke = session.focusStroke
            let distance = roundToLength(Double(session.plan.totalDistanceMeters) * p.distance)
            let focus = min(roundToLength(Double(session.plan.meters(of: focusStroke)) * p.focus), distance)
            let base = PlanGenerator.baseStroke(for: plan.preferences, focus: focusStroke)
            var strokes: [StrokeStyle: Int] = [focusStroke: focus]
            if distance > focus { strokes[base == focusStroke ? .mixed : base, default: 0] += distance - focus }

            result.append(SwimmingWorkout(
                id: UUID(),
                date: calendar.date(bySettingHour: 18, minute: 30, second: 0, of: day) ?? day,
                durationMinutes: Int((Double(plan.preferences.availableMinutes) * min(max(p.distance, 0.8), 1.15)).rounded()),
                distanceMeters: distance,
                sourceName: "Apple Watch",
                strokeMeters: strokes
            ))
        }
        return result.reversed()
    }

    private static func roundToLength(_ meters: Double) -> Int {
        Int((meters / 25).rounded()) * 25
    }
}

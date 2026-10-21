import Foundation

/// Placeholder pacing model shared by plan generation and time estimates.
/// Assumes an easy pace with short rests between repeats.
enum SwimPace {
    static func minutesPer100m(_ stroke: StrokeStyle) -> Double {
        switch stroke {
        case .freestyle: 2.5
        case .breaststroke: 3.0
        case .backstroke: 2.75
        case .butterfly: 3.25
        case .mixed: 2.75
        }
    }

    static let restBetweenRepeats = 0.5

    static func estimatedMinutes(for set: TrainingSet) -> Double {
        let swim = Double(set.totalDistanceMeters) / 100 * minutesPer100m(set.stroke)
        let rest = Double(max(set.repetitions - 1, 0)) * restBetweenRepeats
        return swim + rest
    }

    static func estimatedMinutes(for plan: TrainingPlan) -> Double {
        plan.sets.reduce(0) { $0 + estimatedMinutes(for: $1) }
    }
}

/// Turns the swimmer's strokes, goals, session length and swim days into a week.
///
/// - Every session has the same shape — warm-up, focus-stroke practice, main set,
///   cool-down — sized to fit the time with `SwimPace`.
/// - With several goals, the week rotates through them; each goal has its own
///   rotation of session recipes.
/// - A single day's time can be changed; that session is rebuilt for the new time.
/// - Each week adapts to the two before it: mostly met goals → a little more
///   focus-stroke practice; mostly missed → a little less.
enum PlanGenerator {
    // MARK: Week

    static func weeklyPlan(for preferences: SwimPreferences, trend: WeekTrend = .steady,
                           calendar: Calendar = .current) -> WeeklyPlan {
        let prefs = preferences.normalized()
        let days = calendar.orderedWeekdays.filter(prefs.swimWeekdays.contains)
        var perFocusCount: [SwimFocus: Int] = [:]
        let sessions = days.enumerated().map { index, weekday -> ScheduledSession in
            let focus = prefs.focuses[index % prefs.focuses.count]
            let templateIndex = perFocusCount[focus, default: 0]
            perFocusCount[focus] = templateIndex + 1
            return makeSession(weekday: weekday, focus: focus, templateIndex: templateIndex,
                               minutes: prefs.availableMinutes, trend: trend, preferences: prefs)
        }
        return WeeklyPlan(preferences: prefs, sessions: sessions)
    }

    /// The session for one calendar day, including this week's adaptation and
    /// any time change made for that day. Nil on rest days.
    static func session(on date: Date, preferences: SwimPreferences, workouts: [SwimmingWorkout],
                        minuteOverrides: [String: Int], calendar: Calendar = .current) -> ScheduledSession? {
        let base = weeklyPlan(for: preferences, calendar: calendar)
        guard let planned = base.session(on: date, calendar: calendar) else { return nil }
        let trend = self.trend(forWeekContaining: date, base: base, workouts: workouts, calendar: calendar)
        let override = minuteOverrides[dayKey(date, calendar: calendar)]
        let minutes = override ?? base.preferences.availableMinutes
        var session = makeSession(weekday: planned.weekday, focus: planned.focus, templateIndex: planned.templateIndex,
                                  minutes: minutes, trend: trend, preferences: base.preferences)
        session.isTimeAdjusted = override != nil && override != base.preferences.availableMinutes
        return session
    }

    /// Stable key for per-day settings, e.g. "2026-10-20".
    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Looks at the two weeks before the week containing `date`.
    static func trend(forWeekContaining date: Date, base: WeeklyPlan, workouts: [SwimmingWorkout],
                      calendar: Calendar = .current) -> WeekTrend {
        guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: date)?.start,
              let from = calendar.date(byAdding: .day, value: -14, to: weekStart) else { return .steady }
        let outcomes = workouts
            .filter { $0.date >= from && $0.date < weekStart }
            .compactMap { workout -> GoalOutcome? in
                guard let session = base.session(on: workout.date, calendar: calendar) else { return nil }
                return WorkoutReview(workout: workout, session: session).outcome
            }
        guard outcomes.count >= 2 else { return .steady }
        let metShare = Double(outcomes.filter { $0 == .allMet }.count) / Double(outcomes.count)
        if metShare >= 0.75 { return .harder }
        if metShare <= 0.25 { return .easier }
        return .steady
    }

    // MARK: Session recipes

    /// One session's recipe.
    struct Template {
        var title: String
        var practiceTitle: String
        var practiceStroke: StrokeStyle
        var practiceShare: Double
        /// nil = one length of the pool.
        var practiceRep: Int?
        var mainTitle: String
        var mainStroke: StrokeStyle
        /// nil = continuous swim.
        var mainRep: Int?
        var mainPhase: SetPhase = .main
    }

    /// The swimmer's most comfortable stroke other than the one being worked on.
    static func baseStroke(for prefs: SwimPreferences, focus: StrokeStyle) -> StrokeStyle {
        StrokeStyle.swimmable.first { prefs.knownStrokes.contains($0) && $0 != focus } ?? focus
    }

    static func templates(for prefs: SwimPreferences, focus: SwimFocus) -> [Template] {
        let stroke = focus.stroke
        let base = baseStroke(for: prefs, focus: stroke)
        let f = stroke.rawValue

        switch focus.goal {
        case .learnStroke:
            return [
                Template(title: "\(f) technique", practiceTitle: "\(f) drills", practiceStroke: stroke,
                         practiceShare: 0.35, practiceRep: nil, mainTitle: "Main set", mainStroke: base, mainRep: nil),
                Template(title: "\(base.rawValue) endurance", practiceTitle: "\(f) practice", practiceStroke: stroke,
                         practiceShare: 0.15, practiceRep: 50, mainTitle: "Long swim", mainStroke: base, mainRep: nil,
                         mainPhase: .longSwim),
                Template(title: "Balanced swim", practiceTitle: "\(f) practice", practiceStroke: stroke,
                         practiceShare: 0.25, practiceRep: 50, mainTitle: "Main set", mainStroke: base, mainRep: 100)
            ]
        case .swimFarther:
            return [
                Template(title: "\(f) long swim", practiceTitle: "\(f) build", practiceStroke: stroke,
                         practiceShare: 0.2, practiceRep: 50, mainTitle: "Long swim", mainStroke: stroke, mainRep: nil,
                         mainPhase: .longSwim),
                Template(title: "\(f) intervals", practiceTitle: "Easy \(base.rawValue.lowercased())", practiceStroke: base,
                         practiceShare: 0.15, practiceRep: 50, mainTitle: "Intervals", mainStroke: stroke, mainRep: 100,
                         mainPhase: .intervals),
                Template(title: "Steady distance", practiceTitle: "\(f) practice", practiceStroke: stroke,
                         practiceShare: 0.3, practiceRep: 100, mainTitle: "Steady swim", mainStroke: base, mainRep: nil,
                         mainPhase: .longSwim)
            ]
        case .balanceStrokes:
            let others = StrokeStyle.swimmable.filter { prefs.knownStrokes.contains($0) && $0 != stroke }
            return (others.isEmpty ? [base] : others).map { other in
                Template(title: "\(f) & \(other.rawValue.lowercased())", practiceTitle: "\(f) practice", practiceStroke: stroke,
                         practiceShare: 0.4, practiceRep: 50, mainTitle: "Main set", mainStroke: other, mainRep: 100)
            }
        }
    }

    static func makeSession(weekday: Int, focus: SwimFocus, templateIndex: Int, minutes: Int,
                            trend: WeekTrend, preferences prefs: SwimPreferences) -> ScheduledSession {
        let cycle = templates(for: prefs, focus: focus)
        let template = cycle[templateIndex % cycle.count]
        let plan = session(from: template, focus: focus.stroke, minutes: minutes, trend: trend, preferences: prefs)
        return ScheduledSession(weekday: weekday, plan: plan, focus: focus, templateIndex: templateIndex, trend: trend)
    }

    static func session(from template: Template, focus: StrokeStyle, minutes: Int, trend: WeekTrend,
                        preferences prefs: SwimPreferences) -> TrainingPlan {
        let total = Double(minutes)
        let pool = prefs.poolLengthMeters
        let base = baseStroke(for: prefs, focus: focus)
        // Adapt: ±5% of the session moves into or out of focus practice.
        let practiceShare = min(max(template.practiceShare + 0.05 * Double(trend.rawValue), 0.1), 0.5)

        let warmUp = TrainingSet(
            title: "Warm-up", stroke: base,
            distanceMeters: meters(forMinutes: total * 0.15, stroke: base, pool: pool),
            phase: .warmUp
        )
        let practiceRep = template.practiceRep.map { max($0, pool) } ?? pool
        let practice = TrainingSet(
            title: template.practiceTitle, stroke: template.practiceStroke, distanceMeters: practiceRep,
            repetitions: repetitions(forMinutes: total * practiceShare, distance: practiceRep,
                                     stroke: template.practiceStroke, minimum: 2),
            phase: .practice
        )
        let coolDown = TrainingSet(
            title: "Cool-down", stroke: base,
            distanceMeters: meters(forMinutes: total * 0.10, stroke: base, pool: pool),
            phase: .coolDown
        )

        let used = [warmUp, practice, coolDown].reduce(0) { $0 + SwimPace.estimatedMinutes(for: $1) }
        let remaining = max(total - used, 0)

        let main: TrainingSet
        if let rep = template.mainRep.map({ max($0, pool) }) {
            main = TrainingSet(title: template.mainTitle, stroke: template.mainStroke, distanceMeters: rep,
                               repetitions: repetitions(forMinutes: remaining, distance: rep, stroke: template.mainStroke, minimum: 1),
                               phase: template.mainPhase)
        } else {
            main = TrainingSet(title: template.mainTitle, stroke: template.mainStroke,
                               distanceMeters: meters(forMinutes: remaining, stroke: template.mainStroke, pool: pool),
                               phase: template.mainPhase)
        }

        return TrainingPlan(
            title: template.title,
            availableMinutes: minutes,
            sessionsPerWeek: prefs.sessionsPerWeek,
            sets: [warmUp, practice, main, coolDown]
        )
    }

    /// Continuous distance that fits in `minutes`, rounded down to whole pool lengths.
    private static func meters(forMinutes minutes: Double, stroke: StrokeStyle, pool: Int) -> Int {
        let raw = minutes / SwimPace.minutesPer100m(stroke) * 100
        return max(Int(raw) / pool, 1) * pool
    }

    /// Number of repeats (with rest between them) that fit in `minutes`.
    private static func repetitions(forMinutes minutes: Double, distance: Int, stroke: StrokeStyle, minimum: Int) -> Int {
        let perRep = Double(distance) / 100 * SwimPace.minutesPer100m(stroke) + SwimPace.restBetweenRepeats
        return max(Int((minutes + SwimPace.restBetweenRepeats) / perRep), minimum)
    }
}

// MARK: - Coach

/// Turns a finished swim (and how it felt) into a conclusion and one next step.
/// Every sentence is built from the swim's own numbers and answers — no
/// generic encouragement.
enum Coach {
    struct Verdict {
        /// "Freestyle goal met · 175 m short overall"
        let headline: String
        /// "Next swim: keep 300 m freestyle and choose a shorter time."
        let nextStep: String
    }

    static func verdict(for review: WorkoutReview, reflection: SwimReflection,
                        distance: DistanceStyle) -> Verdict? {
        guard let distanceTarget = review.distanceTarget, let focusTarget = review.focusTarget,
              let distanceMet = review.distanceMet, let focusMet = review.focusMet else { return nil }
        let stroke = review.focusStroke.rawValue
        let strokeLower = stroke.lowercased()
        let focusAmount = distance.format(focusTarget)

        let focusPart = focusMet
            ? "\(stroke) goal met"
            : "\(stroke) \(distance.format(focusTarget - review.focusMeters)) short"
        let distancePart = distanceMet
            ? "full distance"
            : "\(distance.format(distanceTarget - review.workout.distanceMeters)) short overall"
        let headline = "\(focusPart) · \(distancePart)"

        let next: String
        if focusMet {
            if reflection.technique == .slipped || reflection.technique == .struggled {
                next = "Stay at \(focusAmount) \(strokeLower) — add more only once it feels steady to the end."
            } else if !distanceMet {
                switch reflection.shortfall {
                case .time?: next = "Keep \(focusAmount) \(strokeLower) and pick a shorter time, so the whole plan fits."
                case .tired?: next = "Keep \(focusAmount) \(strokeLower) and take the main set easier."
                case .technique?: next = "Keep \(focusAmount) \(strokeLower) and rest longer between lengths."
                case .changedPlan?: next = "Keep \(focusAmount) \(strokeLower) — that part is working."
                case nil: next = "Keep \(focusAmount) \(strokeLower). If time ran short, pick a shorter session so the plan fits."
                }
            } else if reflection.effort == .easy {
                next = "Ready for more — if this keeps up, next week adds more \(strokeLower)."
            } else {
                next = "Repeat it: \(focusAmount) \(strokeLower) is the right amount for now."
            }
        } else if distanceMet {
            next = "Swim the \(strokeLower) set first, while you're fresh."
        } else if reflection.shortfall == .time {
            next = "Start with the \(strokeLower) set, then fill whatever time is left."
        } else {
            next = "Swim the \(strokeLower) set first and ease off the main set."
        }
        return Verdict(headline: headline, nextStep: "Next swim: " + next.prefix(1).lowercased() + next.dropFirst())
    }
}

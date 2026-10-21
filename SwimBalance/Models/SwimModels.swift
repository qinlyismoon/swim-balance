import Foundation

enum StrokeStyle: String, Codable, CaseIterable, Identifiable {
    case freestyle = "Freestyle"
    case breaststroke = "Breaststroke"
    case backstroke = "Backstroke"
    case butterfly = "Butterfly"
    case mixed = "Mixed"

    var id: Self { self }

    /// Strokes a swimmer can know or learn (excludes `.mixed`).
    static let swimmable: [StrokeStyle] = [.breaststroke, .freestyle, .backstroke, .butterfly]
}

/// Where a set sits in the session. Drives the icon in workout lists.
enum SetPhase: String, Codable {
    case warmUp, practice, main, intervals, longSwim, coolDown

    /// SF Symbol name.
    var symbol: String {
        switch self {
        case .warmUp: "flame"
        case .practice: "target"
        case .main: "water.waves"
        case .intervals: "timer"
        case .longSwim: "figure.pool.swim"
        case .coolDown: "figure.cooldown"
        }
    }
}

struct TrainingSet: Identifiable, Codable {
    let id: UUID
    var title: String
    var stroke: StrokeStyle
    var distanceMeters: Int
    var repetitions: Int
    var phase: SetPhase

    init(id: UUID = UUID(), title: String, stroke: StrokeStyle, distanceMeters: Int, repetitions: Int = 1,
         phase: SetPhase = .main) {
        self.id = id
        self.title = title
        self.stroke = stroke
        self.distanceMeters = distanceMeters
        self.repetitions = repetitions
        self.phase = phase
    }

    var totalDistanceMeters: Int { distanceMeters * repetitions }
}

struct TrainingPlan: Identifiable, Codable {
    let id: UUID
    var title: String
    var availableMinutes: Int
    var sessionsPerWeek: Int
    var sets: [TrainingSet]

    init(id: UUID = UUID(), title: String, availableMinutes: Int, sessionsPerWeek: Int, sets: [TrainingSet]) {
        self.id = id
        self.title = title
        self.availableMinutes = availableMinutes
        self.sessionsPerWeek = sessionsPerWeek
        self.sets = sets
    }

    var totalDistanceMeters: Int { sets.reduce(0) { $0 + $1.totalDistanceMeters } }

    func meters(of stroke: StrokeStyle) -> Int {
        sets.filter { $0.stroke == stroke }.reduce(0) { $0 + $1.totalDistanceMeters }
    }
}

struct SwimmingWorkout: Identifiable, Codable {
    let id: UUID
    var date: Date
    var durationMinutes: Int
    var distanceMeters: Int
    var sourceName: String
    /// Distance per stroke, from the watch's per-length stroke data. Empty when unknown.
    var strokeMeters: [StrokeStyle: Int] = [:]
}

// MARK: - Preferences

/// What the swimmer is working towards.
enum SwimGoal: String, Codable, CaseIterable, Identifiable {
    case learnStroke
    case swimFarther
    case balanceStrokes

    var id: Self { self }

    var title: String {
        switch self {
        case .learnStroke: "Learn a stroke"
        case .swimFarther: "Swim farther"
        case .balanceStrokes: "Balance strokes"
        }
    }

    var detail: String {
        switch self {
        case .learnStroke: "Build technique in a stroke you can't swim yet."
        case .swimFarther: "Go longer in a stroke you already know."
        case .balanceStrokes: "Bring a weaker stroke up to your main one."
        }
    }

    /// "Learn freestyle", "Swim farther in breaststroke", …
    func summary(for stroke: StrokeStyle) -> String {
        let name = stroke.rawValue.lowercased()
        switch self {
        case .learnStroke: return "Learn \(name)"
        case .swimFarther: return "Swim farther in \(name)"
        case .balanceStrokes: return "Strengthen \(name)"
        }
    }

    /// Asset name of the goal pictogram (same family as the stroke icons).
    var iconName: String {
        switch self {
        case .learnStroke: "Goal-learn"
        case .swimFarther: "Goal-farther"
        case .balanceStrokes: "Goal-balance"
        }
    }

    var focusPrompt: String {
        switch self {
        case .learnStroke: "Stroke to learn"
        case .swimFarther: "Stroke to swim farther in"
        case .balanceStrokes: "Stroke to bring up"
        }
    }
}

/// How distances are shown: meters, or lengths of the user's pool.
enum DistanceUnit: String, Codable, CaseIterable, Identifiable {
    case meters, lengths
    var id: Self { self }
    var title: String { self == .meters ? "Meters" : "Lengths" }
}

/// One concrete thing the swimmer wants: "Learn freestyle", "Swim farther in breaststroke".
struct SwimFocus: Codable, Hashable, Identifiable {
    var goal: SwimGoal
    var stroke: StrokeStyle

    var id: String { "\(goal.rawValue)-\(stroke.rawValue)" }
    var title: String { goal.summary(for: stroke) }
}

/// Everything the user tells us during setup. The weekly plan is derived from it.
struct SwimPreferences: Codable, Equatable {
    var knownStrokes: Set<StrokeStyle> = [.breaststroke]
    /// One or more goals; the week rotates through them.
    var focuses: [SwimFocus] = [SwimFocus(goal: .learnStroke, stroke: .freestyle)]
    /// Default session length — any single day can be changed on the Swim tab.
    var availableMinutes: Int = 40
    /// Calendar weekdays (1 = Sunday … 7 = Saturday).
    var swimWeekdays: Set<Int> = [3, 7]
    var poolLengthMeters: Int = 25
    var distanceUnit: DistanceUnit = .meters

    var sessionsPerWeek: Int { swimWeekdays.count }
    /// The first goal — used where one representative goal is needed.
    var goal: SwimGoal { focuses.first?.goal ?? .learnStroke }
    var focusStroke: StrokeStyle { focuses.first?.stroke ?? .freestyle }

    init(knownStrokes: Set<StrokeStyle> = [.breaststroke],
         focuses: [SwimFocus] = [SwimFocus(goal: .learnStroke, stroke: .freestyle)],
         availableMinutes: Int = 40, swimWeekdays: Set<Int> = [3, 7],
         poolLengthMeters: Int = 25, distanceUnit: DistanceUnit = .meters) {
        self.knownStrokes = knownStrokes
        self.focuses = focuses
        self.availableMinutes = availableMinutes
        self.swimWeekdays = swimWeekdays
        self.poolLengthMeters = poolLengthMeters
        self.distanceUnit = distanceUnit
    }

    /// Tolerates fields added in later versions so saved setups survive updates.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = SwimPreferences()
        knownStrokes = try c.decodeIfPresent(Set<StrokeStyle>.self, forKey: .knownStrokes) ?? d.knownStrokes
        focuses = try c.decodeIfPresent([SwimFocus].self, forKey: .focuses) ?? d.focuses
        availableMinutes = try c.decodeIfPresent(Int.self, forKey: .availableMinutes) ?? d.availableMinutes
        swimWeekdays = try c.decodeIfPresent(Set<Int>.self, forKey: .swimWeekdays) ?? d.swimWeekdays
        poolLengthMeters = try c.decodeIfPresent(Int.self, forKey: .poolLengthMeters) ?? d.poolLengthMeters
        distanceUnit = try c.decodeIfPresent(DistanceUnit.self, forKey: .distanceUnit) ?? d.distanceUnit
    }

    static let minuteRange = 20...90
    static let minuteStep = 5
    /// Common pool lengths in meters (short course, hotel pools, 33⅓ m, Olympic).
    static let poolLengths = [15, 20, 25, 33, 50]

    /// Strokes a goal can be about, given the strokes the swimmer knows.
    func focusOptions(for goal: SwimGoal) -> [StrokeStyle] {
        switch goal {
        case .learnStroke: StrokeStyle.swimmable.filter { !knownStrokes.contains($0) }
        case .swimFarther, .balanceStrokes: StrokeStyle.swimmable.filter { knownStrokes.contains($0) }
        }
    }

    /// Goals that make sense for the strokes the swimmer knows.
    func isAvailable(_ goal: SwimGoal) -> Bool {
        switch goal {
        case .learnStroke: knownStrokes.count < StrokeStyle.swimmable.count
        case .swimFarther: !knownStrokes.isEmpty
        case .balanceStrokes: knownStrokes.count >= 2
        }
    }

    /// Every concrete goal available for the strokes the swimmer knows.
    var allFocusOptions: [SwimFocus] {
        SwimGoal.allCases
            .filter(isAvailable)
            .flatMap { goal in focusOptions(for: goal).map { SwimFocus(goal: goal, stroke: $0) } }
    }

    /// Drops goals that no longer fit the known strokes; always keeps at least one.
    func normalized() -> SwimPreferences {
        var copy = self
        if copy.knownStrokes.isEmpty { copy.knownStrokes = [.breaststroke] }
        let valid = copy.allFocusOptions
        var seen = Set<SwimFocus>()
        copy.focuses = copy.focuses.filter { valid.contains($0) && seen.insert($0).inserted }
        if copy.focuses.isEmpty, let first = valid.first { copy.focuses = [first] }
        if copy.swimWeekdays.isEmpty { copy.swimWeekdays = [7] }
        return copy
    }
}

// MARK: - Weekly plan

/// How a week adapts to the last two weeks of swims.
enum WeekTrend: Int, Codable {
    case easier = -1, steady = 0, harder = 1

    /// Short note shown on the session, or nil when nothing changed.
    func note(for stroke: StrokeStyle) -> String? {
        switch self {
        case .harder: "More \(stroke.rawValue.lowercased()) this week"
        case .easier: "Eased off this week"
        case .steady: nil
        }
    }
}

/// One session of the week, pinned to a weekday.
struct ScheduledSession: Identifiable {
    /// Calendar weekday: 1 = Sunday … 7 = Saturday.
    let weekday: Int
    let plan: TrainingPlan
    /// The goal this session works on (the week rotates through the goals).
    let focus: SwimFocus
    /// Which recipe in that goal's rotation this session uses.
    let templateIndex: Int
    var trend: WeekTrend = .steady
    /// True when the time for this one day was changed from the default.
    var isTimeAdjusted = false

    var id: UUID { plan.id }
    var focusStroke: StrokeStyle { focus.stroke }
}

/// A full week of sessions generated from the user's preferences.
struct WeeklyPlan {
    let preferences: SwimPreferences
    let sessions: [ScheduledSession]

    var focusStroke: StrokeStyle { preferences.focusStroke }
    var totalDistanceMeters: Int { sessions.reduce(0) { $0 + $1.plan.totalDistanceMeters } }
    var swimWeekdays: Set<Int> { Set(sessions.map(\.weekday)) }

    func session(on date: Date, calendar: Calendar = .current) -> ScheduledSession? {
        let weekday = calendar.component(.weekday, from: date)
        return sessions.first { $0.weekday == weekday }
    }

    /// 1-based position of a session within the week.
    func number(of session: ScheduledSession) -> Int {
        (sessions.firstIndex { $0.id == session.id } ?? 0) + 1
    }

    /// The next scheduled swim strictly after `date`.
    func nextSession(after date: Date, calendar: Calendar = .current) -> (session: ScheduledSession, date: Date)? {
        let start = calendar.startOfDay(for: date)
        for offset in 1...7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: start),
                  let session = session(on: day, calendar: calendar) else { continue }
            return (session, day)
        }
        return nil
    }
}

// MARK: - Goals

/// Every session is judged on two goals: total distance, and the core goal —
/// distance in the focus stroke.
enum GoalOutcome {
    case allMet, partlyMet, notMet

    var title: String {
        switch self {
        case .allMet: "Both goals met"
        case .partlyMet: "One goal met"
        case .notMet: "Goals not met"
        }
    }
}

struct WorkoutReview: Identifiable {
    let workout: SwimmingWorkout
    /// The session planned for that day, if any.
    let session: ScheduledSession?
    let focusStroke: StrokeStyle

    init(workout: SwimmingWorkout, session: ScheduledSession?, focusStroke: StrokeStyle? = nil) {
        self.workout = workout
        self.session = session
        self.focusStroke = focusStroke ?? session?.focusStroke ?? .freestyle
    }

    var id: UUID { workout.id }

    var distanceTarget: Int? { session?.plan.totalDistanceMeters }
    var focusTarget: Int? { session?.plan.meters(of: focusStroke) }
    var focusMeters: Int { workout.strokeMeters[focusStroke] ?? 0 }

    var distanceMet: Bool? { distanceTarget.map { workout.distanceMeters >= $0 } }
    var focusMet: Bool? { focusTarget.map { focusMeters >= $0 } }

    /// Meters swum in each planned set. Lengths are matched to sets in order,
    /// by stroke — the way a watch's per-length stroke data would line up.
    var metersBySet: [UUID: Int] {
        guard let sets = session?.plan.sets else { return [:] }
        var byStroke = workout.strokeMeters
        var unassigned = byStroke.isEmpty ? workout.distanceMeters : (byStroke.removeValue(forKey: .mixed) ?? 0)
        var result: [UUID: Int] = [:]
        for set in sets {
            var take = min(byStroke[set.stroke] ?? 0, set.totalDistanceMeters)
            byStroke[set.stroke, default: 0] -= take
            if take < set.totalDistanceMeters, unassigned > 0 {
                let extra = min(unassigned, set.totalDistanceMeters - take)
                take += extra
                unassigned -= extra
            }
            result[set.id] = take
        }
        return result
    }

    /// Nil for an unplanned (extra) swim.
    var outcome: GoalOutcome? {
        guard let distanceMet, let focusMet else { return nil }
        switch (distanceMet, focusMet) {
        case (true, true): return .allMet
        case (false, false): return .notMet
        default: return .partlyMet
        }
    }
}


// MARK: - Reflection

/// Two quick answers after a swim (and a third when it fell short). The watch
/// knows how far you swam; only you know how it felt and why it stopped.
struct SwimReflection: Codable, Equatable {
    enum Effort: String, Codable, CaseIterable, Identifiable {
        case easy, right, hard
        var id: Self { self }
        var title: String {
            switch self {
            case .easy: "Easy"
            case .right: "Just right"
            case .hard: "Hard"
            }
        }
    }

    enum Technique: String, Codable, CaseIterable, Identifiable {
        case steady, slipped, struggled
        var id: Self { self }
        var title: String {
            switch self {
            case .steady: "Steady"
            case .slipped: "Slipped late"
            case .struggled: "Hard all along"
            }
        }
    }

    enum Shortfall: String, Codable, CaseIterable, Identifiable {
        case time, tired, technique, changedPlan
        var id: Self { self }
        var title: String {
            switch self {
            case .time: "Ran out of time"
            case .tired: "Too tired"
            case .technique: "Form fell apart"
            case .changedPlan: "Changed the plan"
            }
        }
    }

    var effort: Effort?
    var technique: Technique?
    var shortfall: Shortfall?

    var isEmpty: Bool { effort == nil && technique == nil && shortfall == nil }
}

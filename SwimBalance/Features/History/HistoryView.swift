import SwiftUI

/// History answers, in order: what's left to do this week, how the last four
/// weeks went against their targets, what that suggests, and the recent swims.
/// The month calendar is one tap away (toolbar), not the main view.
struct HistoryView: View {
    let weeklyPlan: WeeklyPlan
    let workouts: [SwimmingWorkout]
    /// The session planned for a day, adapted the same way the Swim tab shows it.
    let sessionFor: (Date) -> ScheduledSession?

    enum Metric: String, CaseIterable, Identifiable {
        case swims, goal, plan
        var id: Self { self }
    }

    @State private var metric: Metric = .goal
    @Environment(\.distanceStyle) private var distance
    @Environment(\.reflections) private var reflections

    private let calendar = Calendar.current

    // MARK: Data

    private var today: Date { calendar.startOfDay(for: .now) }

    /// Nothing before the first logged swim counts as missed.
    private var firstSwimDay: Date? {
        workouts.map(\.date).min().map { calendar.startOfDay(for: $0) }
    }

    private func weekStart(_ date: Date) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    private func workout(on day: Date) -> SwimmingWorkout? {
        workouts.first { calendar.isDate($0.date, inSameDayAs: day) }
    }

    private func review(for workout: SwimmingWorkout) -> WorkoutReview {
        WorkoutReview(workout: workout, session: sessionFor(workout.date))
    }

    private var focusStrokes: Set<StrokeStyle> { Set(weeklyPlan.sessions.map(\.focusStroke)) }
    private var strokeLabel: String {
        focusStrokes.count == 1 ? (focusStrokes.first?.rawValue ?? "Goal stroke") : "Goal strokes"
    }

    private func stat(forWeekStarting start: Date) -> WeekStat {
        var stat = WeekStat(start: start, isCurrent: start == weekStart(.now))
        guard let first = firstSwimDay else { return stat }
        for offset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: start), day >= first,
                  weeklyPlan.session(on: day) != nil, let session = sessionFor(day) else { continue }
            // Past weeks count only days that have happened; this week counts the whole plan.
            if !stat.isCurrent && day > today { continue }
            stat.plannedSwims += 1
            stat.goalTarget += session.plan.meters(of: session.focusStroke)
            stat.plannedDistance += session.plan.totalDistanceMeters
            if let swim = workout(on: day) {
                let swimReview = WorkoutReview(workout: swim, session: session)
                stat.swims += 1
                stat.goalMeters += swimReview.focusMeters
                stat.swumOnPlan += min(swim.distanceMeters, session.plan.totalDistanceMeters)
            } else if day >= today {
                stat.remaining.append((day, session))
            }
        }
        return stat
    }

    private var weeks: [WeekStat] {
        guard let first = firstSwimDay else { return [] }
        let thisWeek = weekStart(.now)
        return (0..<4).reversed()
            .compactMap { calendar.date(byAdding: .weekOfYear, value: -$0, to: thisWeek) }
            .filter { (calendar.date(byAdding: .day, value: 7, to: $0) ?? $0) > first }
            .map { stat(forWeekStarting: $0) }
    }

    // MARK: Body

    var body: some View {
        let allWeeks = self.weeks
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                if let current = allWeeks.last {
                    thisWeek(current)
                    trend(allWeeks)
                    InsightCard(insight: insight(weeks: allWeeks))
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Calendar")
                        HistoryCalendar(weeklyPlan: weeklyPlan, workouts: workouts, sessionFor: sessionFor)
                    }
                } else {
                    VStack(spacing: 12) {
                        Image("EmptyHistory")
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 240)
                            .accessibilityHidden(true)
                        Text("No swims yet")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity, minHeight: 420)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .poolHeader()
        .navigationTitle("History")
        .navigationDestination(for: UUID.self) { id in
            if let workout = workouts.first(where: { $0.id == id }) {
                WorkoutDetailView(review: review(for: workout))
            }
        }
    }

    // MARK: 1. This week

    private func thisWeek(_ week: WeekStat) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "This week")
            VStack(alignment: .leading, spacing: 16) {
                progressRow("Swims", value: "\(week.swims) of \(week.plannedSwims)",
                            fraction: Double(week.swims) / Double(max(week.plannedSwims, 1)), isFocus: false)
                progressRow(strokeLabel,
                            value: "\(distance.value(week.goalMeters)) / \(distance.format(week.goalTarget))",
                            fraction: Double(week.goalMeters) / Double(max(week.goalTarget, 1)), isFocus: true)
                Callout(systemImage: "arrow.right.circle", text: weekAdvice(week))
            }
            .sectionCard()
        }
    }

    private func progressRow(_ title: String, value: String, fraction: Double, isFocus: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(value)
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }
            .font(.subheadline)
            ProgressLine(fraction: fraction, isFocus: isFocus)
        }
    }

    private func weekAdvice(_ week: WeekStat) -> String {
        let short = max(week.goalTarget - week.goalMeters, 0)
        if let next = week.remaining.first {
            let day = calendar.isDateInToday(next.day) ? "today" : next.day.formatted(.dateTime.weekday(.wide))
            let amount = next.session.plan.meters(of: next.session.focusStroke)
            let stroke = next.session.focusStroke.rawValue.lowercased()
            let left = week.remaining.count
            let swimsText = left == 1 ? "One swim left" : "\(left) swims left"
            return short <= amount
                ? "\(swimsText). Swim \(day) — \(distance.format(amount)) \(stroke) completes the week."
                : "\(swimsText). Next is \(day), with \(distance.format(amount)) \(stroke)."
        }
        if week.swims >= week.plannedSwims {
            return "Every planned swim is done this week. Rest until the next one."
        }
        return short > 0
            ? "No swims left this week, \(distance.format(short)) short. Next week starts fresh."
            : "No swims left this week, but the \(strokeLabel.lowercased()) target is met."
    }

    // MARK: 2. Last 4 weeks

    private func trend(_ weeks: [WeekStat]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Last \(weeks.count) weeks")
            VStack(alignment: .leading, spacing: 16) {
                MetricPicker(selection: $metric, title: { m in
                    switch m {
                    case .swims: "Swims"
                    case .goal: strokeLabel
                    case .plan: "Plan done"
                    }
                })
                Text(trendTakeaway(weeks))
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
                WeekTargetBars(bars: weeks.map { bar(for: $0) })
                    .frame(height: 150)
            }
            .sectionCard()
        }
        .animation(.easeInOut(duration: 0.25), value: metric)
    }

    private func bar(for week: WeekStat) -> WeekTargetBars.Bar {
        let label = week.isCurrent ? "This week" : week.start.formatted(.dateTime.month(.abbreviated).day())
        let notStarted = week.isCurrent && week.swims == 0
        switch metric {
        case .swims:
            return .init(label: label, actual: Double(week.swims), target: Double(week.plannedSwims),
                         value: notStarted ? "Not started" : "\(week.swims)/\(week.plannedSwims)",
                         isCurrent: week.isCurrent, isFocus: false)
        case .goal:
            return .init(label: label, actual: Double(week.goalMeters), target: Double(week.goalTarget),
                         value: notStarted ? "Not started" : distance.value(week.goalMeters),
                         isCurrent: week.isCurrent, isFocus: true)
        case .plan:
            let planned = week.isCurrent ? week.plannedDistance - week.remaining.reduce(0) { $0 + $1.session.plan.totalDistanceMeters }
                                         : week.plannedDistance
            let pct = planned > 0 ? Double(week.swumOnPlan) / Double(planned) : 0
            return .init(label: label, actual: pct, target: 1,
                         value: planned == 0 ? "Not started" : "\(Int((pct * 100).rounded()))%",
                         isCurrent: week.isCurrent, isFocus: false)
        }
    }

    /// One sentence that says what the bars mean.
    private func trendTakeaway(_ weeks: [WeekStat]) -> String {
        let done = weeks.filter { !$0.isCurrent && $0.plannedSwims > 0 }
        guard !done.isEmpty else { return "Targets are the dashed outlines; bars fill as you swim." }
        switch metric {
        case .swims:
            let hit = done.filter { $0.swims >= $0.plannedSwims }.count
            return "Every planned swim done in \(hit) of \(done.count) finished weeks. The outline is the plan."
        case .goal:
            let hit = done.filter { $0.goalMeters >= $0.goalTarget }.count
            return "\(strokeLabel) target reached in \(hit) of \(done.count) finished weeks. The outline is the target."
        case .plan:
            let planned = done.reduce(0) { $0 + $1.plannedDistance }
            let swum = done.reduce(0) { $0 + $1.swumOnPlan }
            let pct = planned > 0 ? Int((Double(swum) / Double(planned) * 100).rounded()) : 0
            return "You swim \(pct)% of the planned distance on average."
        }
    }

    // MARK: 3. Insight — observation → meaning → next step

    private func insight(weeks: [WeekStat]) -> Insight {
        let since = calendar.date(byAdding: .day, value: -28, to: today) ?? today
        let recent = workouts
            .filter { $0.date >= since && weeklyPlan.session(on: $0.date) != nil }
            .sorted { $0.date > $1.date }
            .map { review(for: $0) }
        let n = recent.count
        guard n >= 2 else {
            return Insight(observation: "Only \(n) swim in the last four weeks.",
                           meaning: "Too few to see a pattern yet.",
                           next: "Swim the next planned day — patterns show up after a few swims.")
        }
        let stroke = (focusStrokes.count == 1 ? focusStrokes.first?.rawValue.lowercased() : nil) ?? "goal-stroke"
        let notes = recent.map { reflections.reflection(on: $0.workout.date) }

        // 1. What the swimmer said about their form
        let slipped = notes.filter { $0.technique == .slipped || $0.technique == .struggled }.count
        if slipped >= 2 {
            return Insight(observation: "You marked your \(stroke) form slipping in \(slipped) of your last \(n) swims.",
                           meaning: "The \(stroke) amount is at the edge of what you can hold well.",
                           next: "Keep the same \(stroke) distance and rest longer between lengths — don't add more yet.")
        }

        // 2. Focus fits, total doesn't
        let focusMet = recent.filter { $0.focusMet == true }.count
        let distanceMet = recent.filter { $0.distanceMet == true }.count
        if Double(focusMet) >= Double(n) * 0.6 && distanceMet * 2 <= n {
            let timeShort = notes.filter { $0.shortfall == .time }.count
            let minutes = weeklyPlan.preferences.availableMinutes
            return Insight(observation: "You met the \(stroke) goal in \(focusMet) of \(n) swims, but swam the full distance in only \(distanceMet).",
                           meaning: "The \(stroke) part fits you; the whole plan runs long.",
                           next: timeShort > 0
                               ? "You said time ran out — try \(max(minutes - 5, SwimPreferences.minuteRange.lowerBound)) min swims in Settings › Your week."
                               : "Try a shorter time per swim so the whole plan fits — Settings › Your week.")
        }

        // 3. Cool-down skipped
        let skippedCool = recent.filter { review in
            guard let cool = review.session?.plan.sets.last(where: { $0.phase == .coolDown }) else { return false }
            return (review.metersBySet[cool.id] ?? 0) == 0
        }.count
        if skippedCool >= 2 {
            return Insight(observation: "You skipped the cool-down in \(skippedCool) of your last \(n) swims.",
                           meaning: "The plan runs out before your time does.",
                           next: "Start the cool-down about 4 minutes before you need to get out.")
        }

        // 4. A weekday that keeps getting missed
        if let first = firstSwimDay {
            var missed: [Int: Int] = [:]
            var day = max(since, first)
            while day < today {
                if weeklyPlan.session(on: day) != nil, workout(on: day) == nil {
                    missed[calendar.component(.weekday, from: day), default: 0] += 1
                }
                day = calendar.date(byAdding: .day, value: 1, to: day) ?? today
            }
            if let worst = missed.max(by: { $0.value < $1.value }), worst.value >= 2 {
                let name = calendar.weekdayName(worst.key)
                return Insight(observation: "You missed \(worst.value) \(name) swims in the last four weeks.",
                               meaning: "\(name) may not fit your week.",
                               next: "Move it to another day in Settings › Your week.")
            }
        }

        // 5. Growing focus volume
        let finished = weeks.filter { !$0.isCurrent && $0.plannedSwims > 0 }
        if let a = finished.first, let b = finished.last, finished.count >= 2, b.goalMeters > a.goalMeters {
            return Insight(observation: "\(strokeLabel) per week went from \(distance.format(a.goalMeters)) to \(distance.format(b.goalMeters)).",
                           meaning: "Your \(stroke) volume is growing with the same number of swims.",
                           next: "Keep the schedule — the plan adds more after steady weeks.")
        }

        let both = recent.filter { $0.outcome == .allMet }.count
        return Insight(observation: "You met both goals in \(both) of your last \(n) swims.",
                       meaning: both * 2 >= n ? "The plan matches what you can do." : "The plan is a little ahead of you.",
                       next: both * 2 >= n ? "Keep going — it gets harder automatically after steady weeks."
                                           : "Answer “How it went” after each swim so the advice can get specific.")
    }
}

// MARK: - Week data

private struct WeekStat: Identifiable {
    let start: Date
    let isCurrent: Bool
    var plannedSwims = 0
    var swims = 0
    var goalMeters = 0
    var goalTarget = 0
    var plannedDistance = 0
    var swumOnPlan = 0
    /// Planned days still ahead (today included) with their sessions.
    var remaining: [(day: Date, session: ScheduledSession)] = []

    var id: Date { start }

    init(start: Date, isCurrent: Bool) {
        self.start = start
        self.isCurrent = isCurrent
    }
}

private struct Insight {
    let observation: String
    let meaning: String
    let next: String
}

/// Observation, what it means, and what to do — always in that order.
private struct InsightCard: View {
    let insight: Insight

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "What it suggests")
            VStack(alignment: .leading, spacing: 10) {
                Text(insight.observation)
                    .font(.body.weight(.medium))
                Text(insight.meaning)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Callout(systemImage: "arrow.right.circle", text: insight.next)
                    .padding(.top, 4)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .sectionCard()
        }
    }
}

/// Capsule switch between the three trend measures.
private struct MetricPicker: View {
    @Binding var selection: HistoryView.Metric
    let title: (HistoryView.Metric) -> String

    var body: some View {
        HStack(spacing: 2) {
            ForEach(HistoryView.Metric.allCases) { option in
                let isOn = option == selection
                Button { selection = option } label: {
                    Text(title(option))
                        .font(.subheadline.weight(isOn ? .semibold : .regular))
                        .foregroundStyle(isOn ? Color.swimDeep : Color.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background {
                            if isOn { Capsule().fill(Color(.systemBackground)) }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.swimDeep.opacity(0.08)))
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// One column per week: the dashed outline is the target, the fill is what was
/// done. Values above, week names below, each on one shared line.
private struct WeekTargetBars: View {
    struct Bar {
        let label: String
        let actual: Double
        let target: Double
        let value: String
        let isCurrent: Bool
        let isFocus: Bool
    }

    let bars: [Bar]
    private let barWidth: CGFloat = 30

    var body: some View {
        let scale = max(bars.map { max($0.actual, $0.target) }.max() ?? 1, 0.0001)
        VStack(spacing: 6) {
            row { bar in
                Text(bar.value)
                    .font(.caption2.weight(bar.isCurrent ? .semibold : .regular))
                    .foregroundStyle(bar.isCurrent ? Color.swimDeep : Color.secondary)
            }
            GeometryReader { proxy in
                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(Array(bars.enumerated()), id: \.offset) { _, bar in
                        let h = proxy.size.height
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color.swimDeep.opacity(0.35),
                                              style: SwiftUI.StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
                                .frame(height: max(h * bar.target / scale, 4))
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(bar.isFocus || bar.isCurrent ? Color.swimDeep : Color.swimDeep.opacity(0.45))
                                .opacity(bar.actual > 0 ? 1 : 0)
                                .frame(height: max(h * bar.actual / scale, bar.actual > 0 ? 6 : 0))
                        }
                        .frame(width: barWidth, height: h, alignment: .bottom)
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            row { bar in
                Text(bar.label)
                    .font(.caption2.weight(bar.isCurrent ? .semibold : .regular))
                    .foregroundStyle(bar.isCurrent ? Color.swimDeep : Color.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(bars.map { "\($0.label): \($0.value)" }.joined(separator: ", "))
    }

    private func row<Content: View>(@ViewBuilder _ content: @escaping (Bar) -> Content) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(bars.enumerated()), id: \.offset) { _, bar in
                content(bar)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - Calendar

/// The month calendar as a time ruler: swipe for earlier months, tap a marked
/// day for that swim. Its legend is written out underneath.
private struct HistoryCalendar: View {
    let weeklyPlan: WeeklyPlan
    let workouts: [SwimmingWorkout]
    let sessionFor: (Date) -> ScheduledSession?

    @State private var visibleMonth: Int? = 0
    private let calendar = Calendar.current
    private let monthRange = -24...0

    private func monthDate(_ offset: Int) -> Date {
        calendar.date(byAdding: .month, value: offset, to: .now) ?? .now
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text(monthDate(visibleMonth ?? 0), format: .dateTime.month(.wide).year())
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.swimDeep)
                    .padding(.horizontal, 8)
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.25), value: visibleMonth)
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 0) {
                        ForEach(monthRange, id: \.self) { offset in
                            MonthGrid(month: monthDate(offset)) { day in dayCell(day) }
                                .containerRelativeFrame(.horizontal)
                                .id(offset)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $visibleMonth, anchor: .center)
                .defaultScrollAnchor(.trailing)
                .sensoryFeedback(.selection, trigger: visibleMonth)
            }
            .sectionCard(padding: 12)
            legend
        }
    }

    @ViewBuilder
    private func dayCell(_ day: Date) -> some View {
        let workout = workouts.first { calendar.isDate($0.date, inSameDayAs: day) }
        let isPast = day < calendar.startOfDay(for: .now)
        let isToday = calendar.isDateInToday(day)
        let isPlanned = weeklyPlan.session(on: day) != nil
        let marker = dayMarker(for: day, session: isPlanned ? sessionFor(day) : nil, workouts: workouts)
        let cell = VStack(spacing: 4) {
            // Today wears the same blue bead as the selected day on the Swim tab.
            Text(day, format: .dateTime.day())
                .font(.body.weight(isToday ? .semibold : .regular))
                .monospacedDigit()
                .foregroundStyle(isToday ? Color.white : (isPast ? Color.secondary : Color.primary))
                .frame(width: 36, height: 36)
                .background {
                    if isToday { Image("Bead-blue").resizable() }
                }
            DayMarker(kind: marker, isUpcomingSwim: isPlanned && !isPast)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())

        if let workout {
            NavigationLink(value: workout.id) { cell }
                .buttonStyle(.plain)
                .accessibilityLabel(day.formatted(.dateTime.month(.wide).day()))
        } else {
            cell
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(day.formatted(.dateTime.month(.wide).day()))
                .accessibilityValue(isPlanned ? (isPast ? "Not swum" : "Planned") : "")
        }
    }

    /// Drops (how a swim went) on one line, waves (no swim yet / not swum) on the next.
    private var legend: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 16) {
                legendItem(.outcome(.allMet), "Both goals met")
                legendItem(.outcome(.partlyMet), "One met")
                legendItem(.outcome(.notMet), "None met")
            }
            HStack(spacing: 16) {
                HStack(spacing: 6) {
                    DayMarker(kind: nil, isUpcomingSwim: true)
                    Text("Planned").fixedSize()
                }
                legendItem(.missed, "Not swum")
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.85)
        .padding(.horizontal, 4)
    }

    private func legendItem(_ kind: GoalMarker.Kind, _ label: String) -> some View {
        HStack(spacing: 6) {
            GoalMarker(kind: kind, size: 10)
            Text(label).fixedSize()
        }
    }
}

// MARK: - One swim

/// A past swim: its numbers, then the same sections the Swim tab shows.
struct WorkoutDetailView: View {
    let review: WorkoutReview

    @Environment(\.distanceStyle) private var distance

    private var workout: SwimmingWorkout { review.workout }

    private var pace: String {
        guard workout.distanceMeters > 0 else { return "–" }
        let seconds = Int(Double(workout.durationMinutes * 60) / Double(workout.distanceMeters) * 100)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(workout.date, format: .dateTime.weekday(.wide).month(.wide).day())
                        .font(.title2)
                        .fontWeight(.semibold)
                    WrapLayout(spacing: 8) {
                        MetaChip(systemImage: "clock", text: "\(workout.durationMinutes) min")
                        MetaChip(systemImage: "water.waves", text: distance.format(workout.distanceMeters))
                        MetaChip(systemImage: "speedometer", text: "\(pace) /100 m")
                    }
                }
                if review.session != nil {
                    PastSwimSections(review: review)
                } else {
                    Text("Extra swim — nothing was planned this day.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .navigationTitle("Swim")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One goal as a plain statement: met (filled check) or not (dashed circle),
/// with what was swum against the target. No bars — the per-set beads show
/// where a session fell short.
struct GoalProgressRow: View {
    let title: String
    let actual: Int
    let target: Int
    let accent: Bool

    @Environment(\.distanceStyle) private var distance

    private var isMet: Bool { actual >= target }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isMet ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(isMet ? Color.swimDeep : Color.secondary)
            Text(title)
            Spacer()
            Text("\(distance.value(actual)) / \(distance.format(target))")
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(isMet ? "Met" : "Not met")
    }
}

#Preview {
    let week = PlanGenerator.weeklyPlan(for: SwimPreferences())
    NavigationStack {
        HistoryView(weeklyPlan: week, workouts: MockData.workouts(for: week), sessionFor: { week.session(on: $0) })
    }
}

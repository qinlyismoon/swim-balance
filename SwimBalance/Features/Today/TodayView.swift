import SwiftUI

/// The Swim tab: the plan, one day at a time. Opens on today; swipe the week
/// strip to page through weeks, tap a day to open it.
///
/// - Today and future swim days show the planned session.
/// - Past swim days show what was swum: the goals, then every set with a row of
///   lane-rope beads (one per length) so missed parts are obvious.
/// - Rest days show an illustration.
struct TodayView: View {
    let weeklyPlan: WeeklyPlan
    let workouts: [SwimmingWorkout]
    /// The session for a given day — adapted to recent weeks and any one-day time change.
    let sessionFor: (Date) -> ScheduledSession?
    /// Change one day's length (nil = back to the default).
    let onSetMinutes: (Int?, Date) -> Void

    @State private var selectedDate = Calendar.current.startOfDay(for: .now)
    @State private var isEditingTime = false
    @State private var timeSheetHeight: CGFloat = 330
    @State private var draftMinutes = 40
    @Environment(\.distanceStyle) private var distance

    private let calendar = Calendar.current
    /// Same height for every day's illustration so switching days doesn't jump.
    private static let illustrationHeight: CGFloat = 140

    private var isToday: Bool { calendar.isDateInToday(selectedDate) }
    private var isPast: Bool { selectedDate < calendar.startOfDay(for: .now) }

    private var title: String {
        if calendar.isDateInToday(selectedDate) { return "Today" }
        if calendar.isDateInTomorrow(selectedDate) { return "Tomorrow" }
        if calendar.isDateInYesterday(selectedDate) { return "Yesterday" }
        return selectedDate.formatted(.dateTime.weekday(.wide).day())
    }

    private func workout(on day: Date) -> SwimmingWorkout? {
        workouts.first { calendar.isDate($0.date, inSameDayAs: day) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                DayStrip(selectedDate: $selectedDate, swimWeekdays: weeklyPlan.swimWeekdays) { day in
                    dayMarker(for: day, session: sessionFor(day), workouts: workouts)
                }
                // The day's details are one unit keyed by date: when the day changes
                // the old content leaves at once and the new one fades in, so
                // texts of two days never overlap or morph into each other.
                VStack(alignment: .leading, spacing: 32) {
                    if let session = sessionFor(selectedDate) {
                        sessionContent(session)
                    } else {
                        restDay
                    }
                }
                .id(calendar.startOfDay(for: selectedDate))
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .offset(y: 8))
                        .animation(.easeOut(duration: 0.25).delay(0.05)),
                    removal: .identity))
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .poolHeader()
        .navigationTitle(title)
        .toolbar {
            if !isToday {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Today") {
                        withAnimation(.easeInOut(duration: 0.3)) { selectedDate = calendar.startOfDay(for: .now) }
                    }
                }
            }
        }
    }

    // MARK: Swim day

    @ViewBuilder
    private func sessionContent(_ session: ScheduledSession) -> some View {
        let plan = session.plan
        let focus = session.focusStroke
        let swum = workout(on: selectedDate)

        VStack(alignment: .leading, spacing: 10) {
            Text(plan.title)
                .font(.title2)
                .fontWeight(.semibold)
            // Level 2: summary facts as chips. Past days show what was swum;
            // today and future days show the plan, and the time chip can be changed.
            WrapLayout(spacing: 8) {
                if isPast {
                    if let swum {
                        MetaChip(systemImage: "clock", text: "\(swum.durationMinutes) min")
                        MetaChip(systemImage: "water.waves", text: distance.format(swum.distanceMeters))
                    } else {
                        MetaChip(systemImage: "drop", text: "Not swum")
                        MetaChip(systemImage: "clock", text: "\(plan.availableMinutes) min planned")
                    }
                } else {
                    Button {
                        draftMinutes = plan.availableMinutes
                        isEditingTime = true
                    } label: {
                        MetaChip(systemImage: "clock", text: "\(plan.availableMinutes) min",
                                 style: session.isTimeAdjusted ? .accent : .neutral, showsChevron: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Changes the time for this day only")
                    MetaChip(systemImage: "water.waves", text: distance.format(plan.totalDistanceMeters))
                    if let note = session.trend.note(for: focus) {
                        MetaChip(systemImage: session.trend == .harder ? "arrow.up.right" : "arrow.down.right",
                                 text: note, style: .accent)
                    }
                }
            }
        }
        .sheet(isPresented: $isEditingTime) {
            timeSheet(default: weeklyPlan.preferences.availableMinutes)
        }

        // Every day reads the same way: a card with the stages of the swim,
        // then the sets. A finished swim adds its conclusion, next step and
        // how it felt — the same sections History shows.
        if isPast, let swum {
            PastSwimSections(review: WorkoutReview(workout: swum, session: session))
        } else {
            VStack(alignment: .leading, spacing: 12) {
                StageBar(sets: plan.sets, focus: focus, swumBySet: isPast ? [:] : nil,
                         totalMinutes: plan.availableMinutes)
                PhaseLegend(sets: plan.sets)
                Divider()
                StrokeTotals(sets: plan.sets, focus: focus)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .sectionCard()

            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: isPast ? "Planned" : "Workout")
                SetList(sets: plan.sets, focus: focus, showsEstimate: true)
                    .sectionCard(padding: 12)
            }
            .opacity(isPast ? 0.7 : 1)
        }
    }

    /// One day's time, on the same pace clock as setup.
    private func timeSheet(default defaultMinutes: Int) -> some View {
        NavigationStack {
            VStack(spacing: 20) {
                ClockDial(minutes: $draftMinutes, range: SwimPreferences.minuteRange,
                          step: SwimPreferences.minuteStep, size: 240)
                if draftMinutes != defaultMinutes {
                    Button("Use usual \(defaultMinutes) min") {
                        withAnimation(.easeInOut(duration: 0.2)) { draftMinutes = defaultMinutes }
                    }
                    .font(.subheadline)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 24)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { timeSheetHeight = $0 }
            .frame(maxHeight: .infinity, alignment: .top)
            .navigationTitle(selectedDate.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isEditingTime = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onSetMinutes(draftMinutes == defaultMinutes ? nil : draftMinutes, selectedDate)
                        isEditingTime = false
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.height(timeSheetHeight + 64)])
        .fontDesign(.rounded)
        .tint(Color.swimDeep)
    }

    private func outcomeSymbol(_ outcome: GoalOutcome?) -> String {
        switch outcome {
        case .allMet?: "drop.fill"
        case .partlyMet?: "drop.halffull"
        default: "drop"
        }
    }

    // MARK: Rest day

    private var restDay: some View {
        VStack(spacing: 16) {
            Image("RestDay")
                .resizable()
                .scaledToFit()
                .frame(height: Self.illustrationHeight)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)
            Text("Rest day")
                .font(.title2)
                .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity, minHeight: 420)
    }
}

/// The week as a page you swipe through — no buttons. Future swim days carry
/// a dot, past swim days carry the History markers, the selected day sits on a
/// colored-pencil bead. Swiping keeps the same weekday selected.
private struct DayStrip: View {
    @Binding var selectedDate: Date
    let swimWeekdays: Set<Int>
    let marker: (Date) -> GoalMarker.Kind?

    @State private var visibleWeek: Int?

    private let calendar = Calendar.current
    private let weekRange = -26...26

    private var thisWeekStart: Date {
        calendar.dateInterval(of: .weekOfYear, for: .now)?.start ?? calendar.startOfDay(for: .now)
    }

    private func weekStart(_ offset: Int) -> Date {
        calendar.date(byAdding: .weekOfYear, value: offset, to: thisWeekStart) ?? thisWeekStart
    }

    private func weekOffset(of date: Date) -> Int {
        let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
        let days = calendar.dateComponents([.day], from: thisWeekStart, to: start).day ?? 0
        return Int((Double(days) / 7).rounded())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(selectedDate, format: .dateTime.month(.wide))
                .font(.headline)
                .contentTransition(.opacity)

            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(weekRange, id: \.self) { offset in
                        HStack(spacing: 0) {
                            ForEach(calendar.week(containing: weekStart(offset)), id: \.self) { day in
                                dayButton(day)
                            }
                        }
                        .containerRelativeFrame(.horizontal)
                        .id(offset)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $visibleWeek)
            .onAppear { visibleWeek = weekOffset(of: selectedDate) }
            .onChange(of: visibleWeek) { _, week in
                guard let week else { return }
                let current = weekOffset(of: selectedDate)
                guard week != current,
                      let date = calendar.date(byAdding: .weekOfYear, value: week - current, to: selectedDate) else { return }
                selectedDate = date
            }
            .onChange(of: selectedDate) { _, date in
                let week = weekOffset(of: date)
                if week != visibleWeek {
                    withAnimation(.easeInOut(duration: 0.3)) { visibleWeek = week }
                }
            }
        }
        .sensoryFeedback(.selection, trigger: selectedDate)
    }

    private func dayButton(_ day: Date) -> some View {
        let isSelected = calendar.isDate(day, inSameDayAs: selectedDate)
        let isToday = calendar.isDateInToday(day)
        let isPast = day < calendar.startOfDay(for: .now)
        let isSwimDay = swimWeekdays.contains(calendar.component(.weekday, from: day))
        let numberColor: Color = isSelected
            ? .white
            : (isToday ? Color.swimDeep : (isPast ? Color.secondary : Color.primary))

        return Button {
            withAnimation(.easeInOut(duration: 0.25)) { selectedDate = day }
        } label: {
            VStack(spacing: 6) {
                Text(day, format: .dateTime.weekday(.narrow))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(day, format: .dateTime.day())
                    .font(.body.weight(isSelected || isToday ? .semibold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(numberColor)
                    .frame(width: 38, height: 38)
                    .background {
                        if isSelected {
                            Image("Bead-blue").resizable()
                        }
                    }
                DayMarker(kind: marker(day), isUpcomingSwim: isSwimDay && !isPast)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.formatted(.dateTime.weekday(.wide).month(.wide).day()))
        .accessibilityValue(isSwimDay ? "Swim day" : "Rest day")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    let week = PlanGenerator.weeklyPlan(for: SwimPreferences())
    NavigationStack {
        TodayView(weeklyPlan: week, workouts: MockData.workouts(for: week),
                  sessionFor: { week.session(on: $0) }, onSetMinutes: { _, _ in })
    }
}

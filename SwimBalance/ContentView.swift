import SwiftUI

struct ContentView: View {
    private enum Tab: Hashable {
        case swim, history, settings
    }

    let swimmingService: any SwimmingWorkoutReading

    @State private var selectedTab: Tab = .swim
    @State private var store = TrainingStore()
    @State private var workouts: [SwimmingWorkout] = []
    @State private var isShowingSplash = true

    var body: some View {
        ZStack {
            tabs
            if isShowingSplash {
                SplashView()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .task {
            try? await Task.sleep(for: .seconds(1.4))
            withAnimation(.easeOut(duration: 0.45)) { isShowingSplash = false }
        }
    }

    private var tabs: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                TodayView(weeklyPlan: store.weeklyPlan, workouts: workouts,
                          sessionFor: session(on:),
                          onSetMinutes: { minutes, date in store.setMinutes(minutes, on: date) })
            }
            .tabItem { Label("Swim", systemImage: "figure.pool.swim") }
            .tag(Tab.swim)

            NavigationStack {
                HistoryView(weeklyPlan: store.weeklyPlan, workouts: workouts, sessionFor: session(on:))
            }
            .tabItem { Label("History", systemImage: "calendar") }
            .tag(Tab.history)

            NavigationStack {
                SettingsView(
                    preferences: store.preferences,
                    onUpdatePreferences: { store.update($0) },
                    onReset: { store.resetAll() }
                )
            }
            .tabItem { Label("Settings", systemImage: "gearshape") }
            .tag(Tab.settings)
        }
        .tint(Color.swimDeep)
        .fontDesign(.rounded)
        .environment(\.distanceStyle, DistanceStyle(store.preferences))
        .environment(\.reflections, ReflectionBook(byDay: store.reflections,
                                                     save: { store.setReflection($0, on: $1) }))
        .task(id: store.preferences) {
            await loadWorkouts()
        }
        .fullScreenCover(isPresented: needsSetup) {
            SetupView(mode: .onboarding, initial: store.preferences) { preferences in
                store.completeSetup(with: preferences)
                selectedTab = .swim
            }
            .interactiveDismissDisabled()
        }
    }

    /// A day's session: adapted to the last two weeks, with any one-day time change.
    private func session(on date: Date) -> ScheduledSession? {
        PlanGenerator.session(on: date, preferences: store.preferences, workouts: workouts,
                              minuteOverrides: store.minuteOverrides)
    }

    /// First launch (or after a demo reset): collect strokes, goal and schedule
    /// first — once the launch screen has faded.
    private var needsSetup: Binding<Bool> {
        Binding(get: { !store.hasCompletedSetup && !isShowingSplash }, set: { _ in })
    }

    /// Demo: the mock service generates swims against the current plan so the
    /// History goals line up. A real HealthKit service is used as-is.
    private func loadWorkouts() async {
        let service: any SwimmingWorkoutReading = swimmingService is MockSwimmingWorkoutService
            ? MockSwimmingWorkoutService(plan: store.weeklyPlan)
            : swimmingService
        workouts = (try? await service.recentWorkouts()) ?? []
    }
}

/// Shown every time the app opens: the welcome illustration and the name,
/// centred, fading into the app.
private struct SplashView: View {
    @State private var isVisible = false

    var body: some View {
        VStack(spacing: 20) {
            Image("Welcome")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 300)
                .accessibilityHidden(true)
            // Hand-lettered feel to match the colored-pencil illustration.
            // Noteworthy ships with iOS — no font files or licensing needed.
            Text("Swim Balance")
                .font(.custom("Noteworthy-Bold", size: 38, relativeTo: .largeTitle))
                .tracking(0.5)
                .foregroundStyle(Color.swimDeep)
        }
        .opacity(isVisible ? 1 : 0)
        .offset(y: isVisible ? 0 : 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) { isVisible = true }
        }
    }
}

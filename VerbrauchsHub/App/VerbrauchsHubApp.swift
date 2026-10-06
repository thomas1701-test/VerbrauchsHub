import SwiftUI
import SwiftData

@main
struct VerbrauchsHubApp: App {
    let container: ModelContainer
    @State private var appState = AppState()
    @State private var license = LicenseStore()

    init() {
        do {
            let schema = Schema([
                Building.self,
                Meter.self,
                Reading.self,
                Tariff.self,
            ])
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }

        let context = ModelContext(container)
        SeedData.seedIfRequested(context)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .environment(license)
        }
        .modelContainer(container)
    }
}

struct RootView: View {
    @Environment(AppState.self) private var appState
    @Environment(LicenseStore.self) private var license
    @Environment(\.scenePhase) private var scenePhase
    @Query private var buildings: [Building]
    @State private var showReminder = false

    var body: some View {
        Group {
            switch license.state {
            case .checking:
                ProgressView()
            case .trialNotStarted:
                PaywallView(mode: .start)
            case .expired:
                PaywallView(mode: .expired)
            case .legacy, .purchased, .trial, .unknown:
                if buildings.isEmpty {
                    OnboardingView()
                } else {
                    MainTabView()
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            license.recompute()
            Task { await license.refresh() }
            remindIfDue()
        }
        .onChange(of: license.state) { remindIfDue() }
        .onAppear { remindIfDue() }
        .sheet(isPresented: $showReminder) {
            PaywallView(mode: .reminder) { showReminder = false }
        }
    }

    private func remindIfDue() {
        guard !showReminder, license.isReminderDue else { return }
        license.markReminderShown()
        showReminder = true
    }
}

struct OnboardingView: View {
    @Environment(\.modelContext) private var context
    @State private var showAddBuilding = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                .font(.system(size: 80))
                .foregroundStyle(.tint)
            Text("Willkommen bei VerbrauchsHub")
                .font(.title.bold())
                .multilineTextAlignment(.center)
            Text("Lege dein erstes Gebäude an, um Zählerstände zu erfassen.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
            Button {
                showAddBuilding = true
            } label: {
                Text("Erstes Gebäude anlegen")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 24)

            Button("Mit Beispieldaten ausprobieren") {
                SeedData.insertDemoData(context)
            }
            .padding(.bottom, 24)
        }
        .sheet(isPresented: $showAddBuilding) {
            AddBuildingSheet()
        }
    }
}

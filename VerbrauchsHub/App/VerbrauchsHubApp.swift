import SwiftUI
import SwiftData

@main
struct VerbrauchsHubApp: App {
    let container: ModelContainer
    @State private var appState = AppState()

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

        // Seed demo data on first launch only
        let context = ModelContext(container)
        SeedData.seedIfNeeded(context)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
        }
        .modelContainer(container)
    }
}

struct RootView: View {
    @Environment(AppState.self) private var appState
    @Query private var buildings: [Building]

    var body: some View {
        if buildings.isEmpty {
            OnboardingView()
        } else {
            MainTabView()
        }
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
            .padding(.bottom, 24)
        }
        .sheet(isPresented: $showAddBuilding) {
            AddBuildingSheet()
        }
    }
}

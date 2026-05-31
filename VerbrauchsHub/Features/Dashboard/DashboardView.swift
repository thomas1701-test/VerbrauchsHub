import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(AppState.self) private var appState
    @Query(sort: \Meter.createdAt, order: .forward) private var allMeters: [Meter]

    var visibleMeters: [Meter] {
        if let id = appState.selectedBuildingID {
            return allMeters.filter { $0.building?.id == id }
        }
        return allMeters
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    if visibleMeters.isEmpty {
                        ContentUnavailableView(
                            "Noch keine Zähler",
                            systemImage: "gauge.with.dots.needle.bottom.50percent",
                            description: Text("Lege im Tab Zähler deinen ersten Zähler an.")
                        )
                        .padding(.top, 60)
                    } else {
                        ForEach(visibleMeters) { meter in
                            NavigationLink {
                                MeterDetailView(meter: meter)
                            } label: {
                                MeterSummaryCard(meter: meter)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .navigationTitle("Übersicht")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    BuildingSwitcher()
                }
            }
        }
    }
}

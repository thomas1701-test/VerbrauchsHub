import SwiftUI
import SwiftData

struct MeterListView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var context
    @Query(sort: \Building.createdAt) private var buildings: [Building]
    @Query(sort: \Meter.createdAt) private var allMeters: [Meter]

    @State private var showAddMeter = false

    var groupedMeters: [(building: Building, meters: [Meter])] {
        let filtered: [Building] = {
            if let id = appState.selectedBuildingID { return buildings.filter { $0.id == id } }
            return buildings
        }()
        return filtered.map { building in
            (building, allMeters.filter { $0.building?.id == building.id })
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(groupedMeters, id: \.building.id) { group in
                    Section(group.building.name) {
                        if group.meters.isEmpty {
                            Text("Keine Zähler — über + anlegen")
                                .foregroundStyle(.secondary)
                                .italic()
                        }
                        ForEach(group.meters) { meter in
                            NavigationLink {
                                MeterDetailView(meter: meter)
                            } label: {
                                MeterRow(meter: meter)
                            }
                        }
                        .onDelete { offsets in
                            for idx in offsets {
                                let meter = group.meters[idx]
                                context.delete(meter)
                            }
                            try? context.save()
                        }
                    }
                }
            }
            .navigationTitle("Zähler")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    BuildingSwitcher()
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showAddMeter = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(buildings.isEmpty)
                }
            }
            .sheet(isPresented: $showAddMeter) {
                AddMeterSheet(defaultBuildingID: appState.selectedBuildingID ?? buildings.first?.id)
            }
        }
    }
}

struct MeterRow: View {
    let meter: Meter

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: meter.iconName)
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Color(hex: meter.colorHex) ?? .accentColor, in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(meter.displayName)
                Text("\(meter.readings.count) Ablesungen • \(meter.unitLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

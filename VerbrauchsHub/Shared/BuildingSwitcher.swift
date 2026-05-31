import SwiftUI
import SwiftData

struct BuildingSwitcher: View {
    @Query(sort: \Building.createdAt, order: .forward) private var buildings: [Building]
    @Environment(AppState.self) private var appState

    var body: some View {
        if buildings.count > 1 {
            Menu {
                Button {
                    appState.selectedBuildingID = nil
                } label: {
                    Label("Alle Gebäude", systemImage: "rectangle.stack.fill")
                }
                Divider()
                ForEach(buildings) { building in
                    Button {
                        appState.selectedBuildingID = building.id
                    } label: {
                        Label(building.name, systemImage: building.iconName)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: currentIcon())
                    Text(currentLabel())
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.thinMaterial, in: Capsule())
            }
        } else if let only = buildings.first {
            HStack(spacing: 4) {
                Image(systemName: only.iconName)
                Text(only.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
            }
            .foregroundStyle(.secondary)
        }
    }

    private func currentLabel() -> String {
        if let id = appState.selectedBuildingID, let b = buildings.first(where: { $0.id == id }) {
            return b.name
        }
        return "Alle"
    }

    private func currentIcon() -> String {
        if let id = appState.selectedBuildingID, let b = buildings.first(where: { $0.id == id }) {
            return b.iconName
        }
        return "rectangle.stack.fill"
    }
}

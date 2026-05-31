import SwiftUI
import SwiftData

struct SettingsView: View {
    @Query(sort: \Building.createdAt) private var buildings: [Building]

    var body: some View {
        NavigationStack {
            List {
                Section("Gebäude") {
                    NavigationLink {
                        BuildingsListView()
                    } label: {
                        Label("Gebäude verwalten", systemImage: "house.fill")
                            .badge(buildings.count)
                    }
                }
                Section("Tarife") {
                    NavigationLink {
                        TariffOverviewView()
                    } label: {
                        Label("Tarife pro Zähler", systemImage: "eurosign.circle")
                    }
                }
                Section("Erinnerungen") {
                    NavigationLink {
                        ReminderSettingsView()
                    } label: {
                        Label("Ablese-Erinnerungen", systemImage: "bell.badge")
                    }
                }
                Section("Daten") {
                    NavigationLink {
                        ExportImportView()
                    } label: {
                        Label("Export & Import", systemImage: "arrow.up.arrow.down.circle")
                    }
                }
                Section("App") {
                    HStack {
                        Label("Version", systemImage: "info.circle")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                            .foregroundStyle(.secondary)
                    }
                    Text("VerbrauchsHub speichert alle Daten lokal auf deinem Gerät. Keine Cloud, keine Tracker.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Einstellungen")
        }
    }
}

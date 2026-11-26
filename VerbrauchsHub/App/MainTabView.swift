import SwiftUI

import SwiftData

struct MainTabView: View {
    @Query private var meters: [Meter]
    private let navigation = AppNavigation.shared

    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Übersicht", systemImage: "square.grid.2x2.fill") }
            MeterListView()
                .tabItem { Label("Zähler", systemImage: "gauge.with.dots.needle.bottom.50percent") }
            StatisticsView()
                .tabItem { Label("Statistik", systemImage: "chart.line.uptrend.xyaxis") }
            SettingsView()
                .tabItem { Label("Einstellungen", systemImage: "gearshape.fill") }
        }
        .sheet(item: Binding(
            get: { meters.first { $0.id == navigation.addReadingMeterID } },
            set: { if $0 == nil { navigation.addReadingMeterID = nil } }
        )) { meter in
            AddReadingSheet(meter: meter)
        }
    }
}

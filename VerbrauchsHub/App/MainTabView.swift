import SwiftUI

struct MainTabView: View {
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
    }
}

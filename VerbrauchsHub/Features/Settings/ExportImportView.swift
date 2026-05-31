import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ExportImportView: View {
    @Environment(\.modelContext) private var context
    @Query private var buildings: [Building]
    @Query private var meters: [Meter]
    @Query private var readings: [Reading]
    @Query private var tariffs: [Tariff]

    @State private var exportURL: URL?
    @State private var showShare = false
    @State private var showImporter = false
    @State private var importError: String?
    @State private var importSummary: String?
    @State private var showImportConfirm = false
    @State private var importStrategy: ImportStrategy = .merge
    @State private var pendingImportURL: URL?

    enum ImportStrategy { case merge, replace }

    var body: some View {
        Form {
            Section("Export") {
                Button {
                    exportJSON()
                } label: {
                    Label("JSON exportieren (vollständig, inkl. Fotos)", systemImage: "square.and.arrow.up")
                }
                Button {
                    exportCSV()
                } label: {
                    Label("CSV exportieren (eine Datei pro Zähler)", systemImage: "tablecells")
                }
                Text("Der Export öffnet das iOS-Teilen-Sheet. Du kannst die Datei in Dateien, iCloud Drive oder per Mail speichern.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Import") {
                Button {
                    showImporter = true
                } label: {
                    Label("JSON importieren", systemImage: "square.and.arrow.down")
                }
                if let err = importError {
                    Text(err).foregroundStyle(.red).font(.caption)
                }
                if let s = importSummary {
                    Text(s).foregroundStyle(.green).font(.caption)
                }
            }
        }
        .navigationTitle("Export & Import")
        .sheet(isPresented: $showShare) {
            if let url = exportURL {
                ShareSheet(url: url)
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                pendingImportURL = url
                showImportConfirm = true
            case .failure(let err):
                importError = err.localizedDescription
            }
        }
        .confirmationDialog("Wie importieren?", isPresented: $showImportConfirm, titleVisibility: .visible) {
            Button("Zusammenführen") {
                importStrategy = .merge
                runImport()
            }
            Button("Alles ersetzen", role: .destructive) {
                importStrategy = .replace
                runImport()
            }
            Button("Abbrechen", role: .cancel) {
                pendingImportURL = nil
            }
        } message: {
            Text("Bestehende Daten zusammenführen oder komplett ersetzen?")
        }
    }

    private func exportJSON() {
        do {
            let snapshot = ExportService.makeSnapshot(buildings: buildings, meters: meters, readings: readings, tariffs: tariffs)
            let url = try ExportService.writeJSON(snapshot)
            exportURL = url
            showShare = true
        } catch {
            importError = error.localizedDescription
        }
    }

    private func exportCSV() {
        do {
            let url = try ExportService.writeCSV(meters: meters)
            exportURL = url
            showShare = true
        } catch {
            importError = error.localizedDescription
        }
    }

    private func runImport() {
        guard let url = pendingImportURL else { return }
        defer { pendingImportURL = nil }
        do {
            // Security-scoped access for files chosen via picker
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }

            let data = try Data(contentsOf: url)
            let summary = try ImportService.importSnapshot(data: data, into: context, strategy: importStrategy == .replace ? .replace : .merge)
            importSummary = summary
            importError = nil
        } catch {
            importError = "Import fehlgeschlagen: \(error.localizedDescription)"
            importSummary = nil
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

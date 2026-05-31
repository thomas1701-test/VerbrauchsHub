import SwiftUI
import SwiftData

struct AddMeterSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Building.createdAt) private var buildings: [Building]

    var defaultBuildingID: UUID?

    @State private var selectedBuildingID: UUID?
    @State private var type: MeterType = .electricity
    @State private var customName: String = ""
    @State private var customUnitLabel: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Gebäude") {
                    Picker("Gebäude", selection: $selectedBuildingID) {
                        ForEach(buildings) { b in
                            Text(b.name).tag(Optional(b.id))
                        }
                    }
                }
                Section("Zählertyp") {
                    Picker("Typ", selection: $type) {
                        ForEach(MeterType.allCases) { t in
                            Label(t.localizedName, systemImage: t.defaultIconName).tag(t)
                        }
                    }
                    .pickerStyle(.menu)
                    TextField("Eigene Bezeichnung (optional)", text: $customName)
                    if type == .custom {
                        TextField("Einheit (z. B. L)", text: $customUnitLabel)
                    }
                }
            }
            .navigationTitle("Neuer Zähler")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Anlegen") { save() }
                        .disabled(selectedBuildingID == nil)
                }
            }
            .onAppear {
                if selectedBuildingID == nil { selectedBuildingID = defaultBuildingID ?? buildings.first?.id }
            }
        }
    }

    private func save() {
        guard let id = selectedBuildingID,
              let building = buildings.first(where: { $0.id == id }) else { return }
        let meter = Meter(
            building: building,
            type: type,
            customName: customName.isEmpty ? nil : customName,
            unitCustomLabel: type == .custom ? customUnitLabel : nil
        )
        context.insert(meter)
        try? context.save()
        dismiss()
    }
}

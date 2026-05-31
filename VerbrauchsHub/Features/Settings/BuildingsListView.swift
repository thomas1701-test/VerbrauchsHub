import SwiftUI
import SwiftData

struct BuildingsListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Building.createdAt) private var buildings: [Building]
    @State private var showAdd = false

    var body: some View {
        List {
            ForEach(buildings) { b in
                HStack {
                    Image(systemName: b.iconName)
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Color(hex: b.colorHex) ?? .accentColor, in: RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading) {
                        Text(b.name)
                        if let a = b.address, !a.isEmpty {
                            Text(a).font(.caption).foregroundStyle(.secondary)
                        }
                        Text("\(b.meters.count) Zähler").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete { offsets in
                for i in offsets { context.delete(buildings[i]) }
                try? context.save()
            }
        }
        .navigationTitle("Gebäude")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showAdd = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showAdd) { AddBuildingSheet() }
    }
}

struct AddBuildingSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var address = ""
    @State private var iconName = "house.fill"
    @State private var colorHex = "#1E88E5"
    @State private var notes = ""

    private let iconOptions = ["house.fill", "building.fill", "building.2.fill", "house.lodge.fill", "leaf.fill", "tree.fill"]
    private let colorOptions = ["#1E88E5", "#43A047", "#FB8C00", "#E53935", "#8E24AA", "#00ACC1"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Name", text: $name)
                    TextField("Adresse (optional)", text: $address)
                }
                Section("Symbol") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 60))]) {
                        ForEach(iconOptions, id: \.self) { icon in
                            Button {
                                iconName = icon
                            } label: {
                                Image(systemName: icon)
                                    .font(.title2)
                                    .frame(width: 50, height: 50)
                                    .background(iconName == icon ? Color.accentColor.opacity(0.25) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Section("Farbe") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 50))]) {
                        ForEach(colorOptions, id: \.self) { hex in
                            Button {
                                colorHex = hex
                            } label: {
                                Circle()
                                    .fill(Color(hex: hex) ?? .accentColor)
                                    .frame(width: 36, height: 36)
                                    .overlay {
                                        if colorHex == hex {
                                            Image(systemName: "checkmark").foregroundStyle(.white)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Section("Notiz") {
                    TextField("optional", text: $notes, axis: .vertical)
                }
            }
            .navigationTitle("Neues Gebäude")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Anlegen") {
                        let b = Building(name: name, address: address.isEmpty ? nil : address, iconName: iconName, colorHex: colorHex, notes: notes.isEmpty ? nil : notes)
                        context.insert(b)
                        try? context.save()
                        dismiss()
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
    }
}

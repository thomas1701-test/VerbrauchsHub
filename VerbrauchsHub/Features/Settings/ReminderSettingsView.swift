import SwiftUI
import SwiftData

struct ReminderSettingsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Meter.createdAt) private var meters: [Meter]

    var body: some View {
        List {
            Section {
                Text("Lass dich monatlich an die Ablesung erinnern. Bei der ersten Aktivierung fragt iOS nach der Erlaubnis für Benachrichtigungen.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(meters) { meter in
                ReminderRow(meter: meter)
            }
        }
        .navigationTitle("Erinnerungen")
    }
}

struct ReminderRow: View {
    @Environment(\.modelContext) private var context
    @Bindable var meter: Meter

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Aktiv", isOn: Binding(
                    get: { meter.reminderEnabled },
                    set: { newValue in
                        meter.reminderEnabled = newValue
                        if newValue {
                            Task { @MainActor in
                                let ok = await NotificationService.shared.requestPermissionIfNeeded()
                                if ok {
                                    NotificationService.shared.scheduleReminder(for: meter)
                                }
                            }
                        } else {
                            NotificationService.shared.cancelReminder(for: meter)
                        }
                        try? context.save()
                    }
                ))
                if meter.reminderEnabled {
                    Picker("Tag im Monat", selection: Binding(
                        get: { meter.reminderDayOfMonth ?? 1 },
                        set: { newValue in
                            meter.reminderDayOfMonth = newValue
                            NotificationService.shared.scheduleReminder(for: meter)
                            try? context.save()
                        }
                    )) {
                        ForEach(1...28, id: \.self) { day in
                            Text("\(day).").tag(day)
                        }
                    }
                }
            }
        } label: {
            HStack {
                Image(systemName: meter.iconName)
                    .foregroundStyle(Color(hex: meter.colorHex) ?? .accentColor)
                Text(meter.displayName)
                Spacer()
                if meter.reminderEnabled {
                    Image(systemName: "bell.fill").foregroundStyle(.tint).font(.caption)
                }
            }
        }
    }
}

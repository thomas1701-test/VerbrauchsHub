import StoreKit
import SwiftUI

struct PaywallView: View {
    enum Mode {
        /// First launch of a new user: start the trial or buy right away.
        case start
        /// Trial is over: buying is the only way back into the app.
        case expired
        /// Reminder during the trial, can be dismissed.
        case reminder
    }

    let mode: Mode
    var onDismiss: (() -> Void)?

    @Environment(LicenseStore.self) private var license
    @Environment(\.purchase) private var purchase

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                header
                points
                buttons
                footnote
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 32)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .disabled(license.isWorking)
        .overlay {
            if license.isWorking {
                ProgressView()
                    .controlSize(.large)
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .licenseErrorAlert()
        .onChange(of: license.state.isFullVersion) { _, isFull in
            if isFull { onDismiss?() }
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text(title)
                .font(.title.bold())
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var points: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(pointTexts, id: \.text) { point in
                Label {
                    Text(point.text)
                } icon: {
                    Image(systemName: point.icon)
                        .foregroundStyle(.tint)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private var buttons: some View {
        VStack(spacing: 12) {
            if mode == .start {
                Button {
                    Task { await license.startTrial { try await purchase($0) } }
                } label: {
                    Text("\(LicensePolicy.trialDays) Tage kostenlos testen")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    Task { await license.buyFullVersion { try await purchase($0) } }
                } label: {
                    Text("Gleich kaufen – \(license.fullPriceText)")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            } else {
                Button {
                    Task { await license.buyFullVersion { try await purchase($0) } }
                } label: {
                    Text("Vollversion kaufen – \(license.fullPriceText)")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            Button("Kauf wiederherstellen") {
                Task { await license.restore() }
            }
            .font(.subheadline)

            if mode == .reminder {
                Button("Später") { onDismiss?() }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var footnote: some View {
        Text("Einmaliger Kauf, kein Abo. Du hast VerbrauchsHub schon früher gekauft? Dann bleibt die App für dich kostenlos – falls sie trotzdem gesperrt ist, tippe auf „Kauf wiederherstellen“.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }

    // MARK: - Texts

    private var iconName: String {
        switch mode {
        case .start: "gauge.with.dots.needle.bottom.50percent"
        case .expired: "lock.fill"
        case .reminder: "hourglass"
        }
    }

    private var title: String {
        switch mode {
        case .start:
            return "Willkommen bei VerbrauchsHub"
        case .expired:
            return "Deine Testphase ist abgelaufen"
        case .reminder:
            switch license.daysLeft ?? 0 {
            case ...1: return "Letzter Tag deiner Testphase"
            case let days: return "Noch \(days) Tage Testphase"
            }
        }
    }

    private var subtitle: String {
        switch mode {
        case .start:
            "Teste alle Funktionen \(LicensePolicy.trialDays) Tage lang kostenlos."
        case .expired:
            "Kaufe die Vollversion, um VerbrauchsHub weiter zu nutzen. Deine Daten sind vollständig erhalten."
        case .reminder:
            "Schalte die Vollversion frei, damit du nach der Testphase ohne Unterbrechung weitermachen kannst."
        }
    }

    private var pointTexts: [(icon: String, text: String)] {
        switch mode {
        case .start:
            [
                ("checkmark.circle.fill", "Alle Funktionen \(LicensePolicy.trialDays) Tage ohne Einschränkung"),
                ("eurosign.circle.fill", "Danach einmalig \(license.fullPriceText) für die Vollversion"),
                ("lock.circle.fill", "Ohne Kauf ist die App nach der Testphase gesperrt – deine Daten bleiben auf dem Gerät erhalten"),
            ]
        case .expired, .reminder:
            [
                ("checkmark.circle.fill", "Alle Funktionen dauerhaft freigeschaltet"),
                ("eurosign.circle.fill", "Einmalig \(license.fullPriceText), kein Abo"),
                ("internaldrive.fill", "Deine Zähler und Ablesungen bleiben erhalten"),
            ]
        }
    }
}

/// Compact hint on the dashboard while the trial runs.
struct TrialBanner: View {
    @Environment(LicenseStore.self) private var license
    @State private var showPaywall = false

    var body: some View {
        if let days = license.daysLeft {
            Button {
                showPaywall = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "hourglass")
                        .font(.title3)
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(days <= 1 ? "Letzter Tag der Testphase" : "Testphase: noch \(days) Tage")
                            .font(.subheadline.weight(.semibold))
                        Text("Vollversion für \(license.fullPriceText) freischalten")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showPaywall) {
                PaywallView(mode: .reminder) { showPaywall = false }
                    .presentationDetents([.large])
            }
        }
    }
}

/// License row in the settings.
struct LicenseSection: View {
    @Environment(LicenseStore.self) private var license
    @State private var showPaywall = false

    var body: some View {
        Section("Vollversion") {
            HStack {
                Label("Status", systemImage: "checkmark.seal")
                Spacer()
                Text(statusText)
                    .foregroundStyle(.secondary)
            }
            if !license.state.isFullVersion {
                Button("Vollversion kaufen – \(license.fullPriceText)") {
                    showPaywall = true
                }
                Button("Kauf wiederherstellen") {
                    Task { await license.restore() }
                }
                .disabled(license.isWorking)
            }
        }
        .licenseErrorAlert(isActive: !showPaywall)
        .sheet(isPresented: $showPaywall) {
            PaywallView(mode: .reminder) { showPaywall = false }
        }
    }

    private var statusText: String {
        switch license.state {
        case .legacy, .purchased: "Freigeschaltet"
        case .trial: license.daysLeft.map { $0 <= 1 ? "Letzter Testtag" : "Test, noch \($0) Tage" } ?? "Test"
        case .expired: "Test abgelaufen"
        case .trialNotStarted: "Nicht gestartet"
        case .checking, .unknown: "Wird geprüft"
        }
    }
}

private struct LicenseErrorAlert: ViewModifier {
    let isActive: Bool
    @Environment(LicenseStore.self) private var license

    func body(content: Content) -> some View {
        content.alert("Hinweis", isPresented: Binding(
            get: { isActive && license.errorMessage != nil },
            set: { if !$0 { license.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(license.errorMessage ?? "")
        }
    }
}

extension View {
    func licenseErrorAlert(isActive: Bool = true) -> some View {
        modifier(LicenseErrorAlert(isActive: isActive))
    }
}

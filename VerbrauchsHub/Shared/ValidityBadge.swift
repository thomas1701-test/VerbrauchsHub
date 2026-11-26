import SwiftUI

/// Small "geplant" / "aktuell" label for tariffs, advance payments and contracts.
struct ValidityBadge: View {
    let status: ValidityStatus?

    var body: some View {
        switch status {
        case .planned:
            Text("geplant").font(.caption).foregroundStyle(.orange)
        case .current:
            Text("aktuell").font(.caption).foregroundStyle(.green)
        case .ended, nil:
            EmptyView()
        }
    }
}

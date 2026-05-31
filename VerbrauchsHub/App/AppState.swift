import Foundation
import SwiftUI

@Observable
final class AppState {
    /// Selected building. `nil` means "all buildings".
    var selectedBuildingID: UUID?

    var showOnboarding: Bool = false

    init(selectedBuildingID: UUID? = nil) {
        self.selectedBuildingID = selectedBuildingID
    }
}

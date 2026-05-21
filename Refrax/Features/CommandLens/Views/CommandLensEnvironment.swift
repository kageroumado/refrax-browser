import SwiftUI

private struct CommandLensIsSmallKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var commandLensIsSmall: Bool {
        get { self[CommandLensIsSmallKey.self] }
        set { self[CommandLensIsSmallKey.self] = newValue }
    }
}

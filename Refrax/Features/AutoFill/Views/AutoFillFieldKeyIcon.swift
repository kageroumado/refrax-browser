import SwiftUI

/// Small key icon displayed at the trailing edge of credential fields.
///
/// This icon indicates that autofill is available for the field.
/// Safari displays a similar icon when focusing on password fields.
struct AutoFillFieldKeyIcon: View {
    let rect: CGRect

    var body: some View {
        Image(systemName: "key.fill")
            .font(.system(size: Constants.iconSize, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: Constants.hitArea, height: Constants.hitArea)
            .contentShape(Rectangle())
            .offset(
                x: rect.maxX - Constants.hitArea - Constants.trailingPadding,
                y: rect.minY + (rect.height - Constants.hitArea) / 2,
            )
            .allowsHitTesting(false)
    }

    private enum Constants {
        static let iconSize: CGFloat = 12
        static let hitArea: CGFloat = 20
        static let trailingPadding: CGFloat = 4
    }
}

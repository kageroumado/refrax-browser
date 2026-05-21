import SwiftUI

/// Displays Refrax's license and trademark notice.
struct LicenseAgreementView: View {
    var body: some View {
        ScrollView {
            Text(Self.licenseText)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .frame(minWidth: 400, minHeight: 300)
    }

    // swiftformat:disable indent
    private static let licenseText = """
Refrax
======

Copyright (C) 2026 kageroumado

Refrax is free software: you can redistribute it and/or modify it
under the terms of the GNU General Public License as published by
the Free Software Foundation, version 3 of the License.

Refrax is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
General Public License for more details.

The full license text is in the LICENSE file in the source
distribution, and online at <https://www.gnu.org/licenses/gpl-3.0.txt>.

THIRD-PARTY SOFTWARE
====================

Refrax includes third-party open-source software components. Their
respective licenses are available in the Acknowledgements section
of the application.

TRADEMARK
=========

"Refrax" and the Refrax icon are trademarks of kageroumado. The
GPL grants rights to the source code, not to the trademarks.

You may build and use Refrax from source for any purpose. If you
distribute a modified version, you must rebrand: choose a different
name and replace the Refrax icon. See the TRADEMARK file in the
source distribution for the full policy.

CONTACT
=======

For inquiries: requests@refrax.website
"""
    // swiftformat:enable indent
}

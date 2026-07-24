import SwiftUI

/// Displays the Refrax End User License Agreement.
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
Refrax End User License Agreement
==================================

Copyright (c) 2026 kageroumado. All rights reserved.

1. LICENSE GRANT

This software is licensed, not sold. kageroumado grants you a limited,
non-exclusive, non-transferable, revocable license to use Refrax for
personal or commercial purposes, subject to the terms of this agreement.

2. RESTRICTIONS

You may not:
- Copy, modify, or distribute this software without prior written consent
- Remove or alter any proprietary notices or labels
- Use the software for any unlawful purpose

3. DISCLAIMER OF WARRANTIES

THIS SOFTWARE IS PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND, EXPRESS
OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE, AND NONINFRINGEMENT. THE ENTIRE RISK
ARISING OUT OF THE USE OR PERFORMANCE OF THE SOFTWARE REMAINS WITH YOU.

4. LIMITATION OF LIABILITY

IN NO EVENT SHALL KAGEROUMADO BE LIABLE FOR ANY INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED
TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

5. THIRD-PARTY SOFTWARE

Refrax includes third-party open-source software components. Their
respective licenses are available in the Acknowledgements section of
the application.

6. TERMINATION

This license is effective until terminated. It will terminate automatically
if you fail to comply with any term of this agreement. Upon termination,
you must cease all use of the software and destroy all copies.

7. CONTACT

For inquiries, contact: requests@refrax.website
"""
    // swiftformat:enable indent
}

import SwiftUI
import WebKit

/// A preview view that displays a snapshot of a WebPage.
///
/// Takes an async snapshot of the web content and displays it as a static image.
/// Shows a loading indicator while the snapshot is being captured.
struct SnapshotPreviewView: View {
    let webPage: WebPage

    @State private var snapshot: NSImage?
    @State private var isLoading = true

    private enum Constants {
        static let width: CGFloat = 450
        static let height: CGFloat = 300
    }

    var body: some View {
        Group {
            if let snapshot {
                Image(nsImage: snapshot)
                    .resizable()
                    .scaledToFill()
                    .frame(width: Constants.width, height: Constants.height, alignment: .top)
                    .clipped()
            } else if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: Constants.width, height: Constants.height)
            }
        }
        .task {
            await captureSnapshot()
        }
    }

    private func captureSnapshot() async {
        let configuration = WKSnapshotConfiguration()
        configuration.afterScreenUpdates = true

        do {
            let image = try await webPage.backingWebView.takeSnapshot(configuration: configuration)
            snapshot = image
        } catch {
            Logger.warning("Failed to capture snapshot: \(error)", category: Logger.ui)
        }

        isLoading = false
    }
}

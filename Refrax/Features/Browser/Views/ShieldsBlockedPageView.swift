import SwiftUI

/// Shown over a page when Shields kept a page from opening: a filter blocks its address as a
/// document, the way uBlock Origin's strict blocking does for tracker and malware hosts.
///
/// "Go Back" returns to the previous page; "Open Anyway" lets the site's pages open until
/// Refrax quits, and loads this one.
struct ShieldsBlockedPageView: View {
    @Environment(BrowserState.self) private var browserState

    let page: WebPage
    let url: URL

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                VStack(spacing: 14) {
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 52))
                        .foregroundStyle(.secondary)
                    Text("Shields Blocked This Page")
                        .font(.title)
                        .fontWeight(.semibold)
                    Text("A filter list Shields uses blocks this address as a page, as it does for ad, tracking and malware sites.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                GroupBox {
                    Text(url.absoluteString)
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 6)
                }

                VStack(spacing: 12) {
                    Button {
                        page.shieldsBlockedURL = nil
                        page.goBack()
                    } label: {
                        Label("Go Back", systemImage: "chevron.left")
                            .frame(minWidth: 200)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!page.canGoBack)

                    Button {
                        browserState.shields.openAnyway(url)
                        page.load(url)
                    } label: {
                        Text("Open Anyway")
                            .frame(minWidth: 200)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .help("Open pages on \(url.host() ?? "this site") until Refrax quits")
                }
            }
            .padding(40)
            .frame(maxWidth: 500)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.windowBackgroundColor))
    }
}

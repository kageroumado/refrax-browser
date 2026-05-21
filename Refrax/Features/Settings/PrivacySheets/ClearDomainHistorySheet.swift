import SwiftUI

// MARK: - Clear Domain History Sheet

struct ClearDomainHistorySheet: View {
    @Environment(HistoryManager.self) private var historyManager
    @Environment(\.dismiss) private var dismiss

    @State private var domains: [String] = []
    @State private var selectedDomains: Set<String> = []
    @State private var searchText = ""
    @State private var isLoading = true
    @State private var domainCounts: [String: Int] = [:]
    @State private var countFetchTask: Task<Void, Never>?

    private var filteredDomains: [String] {
        if searchText.isEmpty { return domains }
        return domains.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading domains...")
                } else {
                    domainList
                }
            }
            .navigationTitle("Clear History by Site")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .destructiveAction) {
                    Button("Delete Selected", role: .destructive) {
                        historyManager.deleteEntries(forDomains: selectedDomains)
                        dismiss()
                    }
                    .disabled(selectedDomains.isEmpty)
                }
            }
        }
        .frame(minWidth: 450, minHeight: 500)
        .task {
            domains = await historyManager.allDomains()
            isLoading = false
        }
        .onChange(of: selectedDomains) { _, newSelection in
            countFetchTask?.cancel()
            countFetchTask = Task {
                for domain in newSelection where domainCounts[domain] == nil {
                    guard !Task.isCancelled else { return }
                    let entries = await historyManager.entries(forDomain: domain)
                    guard !Task.isCancelled else { return }
                    domainCounts[domain] = entries.count
                }
            }
        }
    }

    private var domainList: some View {
        List(filteredDomains, id: \.self, selection: $selectedDomains) { domain in
            HStack {
                Text(domain)
                Spacer()
                if let count = domainCounts[domain] {
                    Text("\(count)")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
        }
        .searchable(text: $searchText, prompt: "Filter domains")
        .overlay {
            if domains.isEmpty {
                ContentUnavailableView {
                    Label("No History", systemImage: "clock")
                } description: {
                    Text("No browsing history to clear.")
                }
            } else if filteredDomains.isEmpty {
                ContentUnavailableView {
                    Label("No Results", systemImage: "magnifyingglass")
                } description: {
                    Text("No domains match your search.")
                }
            }
        }
    }
}

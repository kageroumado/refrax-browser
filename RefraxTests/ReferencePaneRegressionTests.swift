import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import Refrax

// MARK: - Reference Pane Regression Tests

/// Tests for reference tab functionality.
@Suite("Reference Pane Regression", .tags(.tabManager), .serialized)
@MainActor
struct ReferencePaneRegressionTests {
    // MARK: - Reference Tab Tests

    @Test("Reference tab is separate from main tabs")
    func referenceTabSeparateFromMain() throws {
        let env = try TabManagerTestEnvironment()
        let context = env.modelContext
        let space = env.makeSpace()

        let mainTab = try Tab(space: space, url: #require(URL(string: "https://main.com")))
        context.insert(mainTab)

        let refTab = try Tab(space: space, url: #require(URL(string: "https://ref.com")), isReferenceTab: true)
        context.insert(refTab)

        env.browserState.indexTab(mainTab)
        env.browserState.indexTab(refTab)

        #expect(space.mainTabs.count == 1)
        #expect(space.referenceTabs.count == 1)
        #expect(space.tabs.count == 2)
    }

    @Test("Reference tab persists isReferenceTab flag")
    func referenceTabPersistsFlag() throws {
        let env = try TabManagerTestEnvironment()
        let context = env.modelContext
        let space = env.makeSpace()

        let refTab = try Tab(space: space, url: #require(URL(string: "https://ref.com")), isReferenceTab: true)
        context.insert(refTab)
        let tabID = refTab.id

        try context.save()

        let descriptor = FetchDescriptor<Refrax.Tab>(predicate: #Predicate { $0.id == tabID })
        let fetched = try context.fetch(descriptor)

        #expect(fetched.first?.isReferenceTab == true)
    }
}

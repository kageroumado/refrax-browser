import Testing
@testable import Refrax
import Foundation

@Suite(.serialized)
@MainActor
struct PageVisitTests {
    @Test func `successive looks keep the first return destination and preserve visited tabs`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let window = env.makeActiveWindowState(with: space)
        let source = env.createActiveTab(url: try #require(URL(string: "about:blank#source")), in: space, for: window)
        let first = env.tabManager.createTab(url: try #require(URL(string: "about:blank#first")), in: space, makeActive: false)
        let second = env.tabManager.createTab(url: try #require(URL(string: "about:blank#second")), in: space, makeActive: false)
        env.tabManager.look(at: first, in: window)
        env.tabManager.look(at: second, in: window)
        #expect(window.pageVisit.destination?.tabID == source.id)
        #expect(window.activeTabID == second.id)
        #expect(env.tabManager.returnFromLook(in: window))
        #expect(window.activeTabID == source.id)
        #expect(window.pageVisit.destination == nil)
        #expect(env.browserState.tab(for: first.id) != nil)
        #expect(env.browserState.tab(for: second.id) != nil)
    }

    @Test func `ordinary activation ends a visit in only its owning window`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let firstWindow = env.makeActiveWindowState(with: space)
        let secondWindow = env.makeActiveWindowState(with: space)
        let source = env.createActiveTab(url: try #require(URL(string: "about:blank#source")), in: space, for: firstWindow)
        env.tabManager.setActiveTab(source, in: secondWindow)
        let reference = env.tabManager.createTab(url: try #require(URL(string: "about:blank#reference")), in: space, makeActive: false)
        env.tabManager.look(at: reference, in: firstWindow)
        env.tabManager.look(at: reference, in: secondWindow)
        env.tabManager.setActiveTab(source, in: firstWindow)
        #expect(firstWindow.pageVisit.destination == nil)
        #expect(secondWindow.pageVisit.destination?.tabID == source.id)
    }

    @Test func `return restores the original space after a cross space look`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let other = env.makeSpace(name: "Reference")
        let window = env.makeActiveWindowState(with: space)
        let source = env.createActiveTab(url: try #require(URL(string: "about:blank#source")), in: space, for: window)
        let reference = env.tabManager.createTab(url: try #require(URL(string: "about:blank#reference")), in: other, makeActive: false)
        env.tabManager.look(at: reference, in: window)
        #expect(window.activeSpaceID == other.id)
        #expect(window.activeTabID == reference.id)
        #expect(env.tabManager.returnFromLook(in: window))
        #expect(window.activeSpaceID == space.id)
        #expect(window.activeTabID == source.id)
    }

    @Test func `closed destination ends the visit without choosing another page`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let window = env.makeActiveWindowState(with: space)
        let source = env.createActiveTab(url: try #require(URL(string: "about:blank#source")), in: space, for: window)
        let reference = env.tabManager.createTab(url: try #require(URL(string: "about:blank#reference")), in: space, makeActive: false)
        env.tabManager.look(at: reference, in: window)
        env.tabManager.closeTab(source)
        #expect(!env.tabManager.returnFromLook(in: window))
        #expect(window.activeTabID == reference.id)
        #expect(window.pageVisit.destination == nil)
    }
}

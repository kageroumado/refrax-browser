import Foundation
import Testing
@testable import Refrax

@Suite("WebKitRuleCompiler Chunking", .tags(.filterParser))
struct WebKitRuleCompilerChunkingTests {
    let compiler = WebKitRuleCompiler()
    let parser = FilterParser()

    /// A filter list of `count` distinct network rules.
    private func filterList(ruleCount count: Int) -> FilterParser.ParseResult {
        let lines = (0 ..< count).map { "||tracker\($0).example.com/pixel" }
        return parser.parse(lines.joined(separator: "\n"))
    }

    private func ruleCount(inChunk json: String) throws -> Int {
        let data = try #require(json.data(using: .utf8))
        let rules = try #require(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        return rules.count
    }

    @Test("Per-list limit matches WebKit's maxRuleCount")
    func limitMatchesWebKit() {
        #expect(WebKitRuleCompiler.maxRulesPerList == 150_000)
    }

    @Test("Splits rules into full chunks with the remainder last")
    func splitsIntoFullChunks() throws {
        let parseResult = filterList(ruleCount: 25)
        let total = try ruleCount(inChunk: compiler.compile(parseResult))
        #expect(total == 25)

        let chunks = compiler.compileInChunks(parseResult, maxRulesPerChunk: 10)
        let counts = try chunks.map { try ruleCount(inChunk: $0) }
        #expect(counts == [10, 10, 5])
    }

    @Test("A rule count equal to the limit fits one chunk")
    func exactLimitFitsOneChunk() throws {
        let chunks = compiler.compileInChunks(filterList(ruleCount: 10), maxRulesPerChunk: 10)
        #expect(chunks.count == 1)
        #expect(try ruleCount(inChunk: chunks[0]) == 10)
    }

    @Test("Chunks preserve filter-list order across boundaries")
    func preservesOrder() throws {
        let chunks = compiler.compileInChunks(filterList(ruleCount: 7), maxRulesPerChunk: 3)
        let filters = try chunks.flatMap { json -> [String] in
            let data = try #require(json.data(using: .utf8))
            let rules = try #require(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
            return rules.compactMap { ($0["trigger"] as? [String: Any])?["url-filter"] as? String }
        }
        #expect(filters.count == 7)
        for (index, filter) in filters.enumerated() {
            #expect(filter.contains("tracker\(index)"))
        }
    }

    @Test("An empty filter list compiles to no chunks")
    func emptyListHasNoChunks() {
        #expect(compiler.compileInChunks(parser.parse("")).isEmpty)
    }

    @Test("The default chunk size keeps a mid-size list in one chunk")
    func defaultChunkSizeKeepsOneChunk() {
        #expect(compiler.compileInChunks(filterList(ruleCount: 60_000)).count == 1)
    }
}

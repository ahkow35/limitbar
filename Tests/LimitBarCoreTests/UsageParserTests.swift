import Testing
import Foundation
@testable import LimitBarCore

struct UsageParserTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    @Test func testScopedFableAllowanceUsesItsOwnPercent() throws {
        let data = Data(#"{"five_hour":{"utilization":4},"seven_day":{"utilization":33},"seven_day_breakdown":{"fable":{"utilization":99}},"limits":[{"kind":"weekly_scoped","group":"weekly","percent":67,"resets_at":"2026-10-29T02:00:00Z","scope":{"model":{"id":"opaque-model-id","display_name":"Fable"}}}]}"#.utf8)
        let result = try UsageParser.claude(data: data, plan: "Max")
        #expect(result.windows.count == 3)
        #expect(!result.windows.contains { $0.id == "seven_day_breakdown" })
        let fable = try #require(result.windows.first { $0.isFable })
        #expect(fable.usedPercent == 67)
        #expect(fable.remainingPercent == 33)
        #expect(fable.resetsAt != nil)
    }
    @Test func testSharedUsageCannotInventFableAllowance() throws {
        let result = try UsageParser.claude(data: Data(#"{"seven_day":{"utilization":20},"seven_day_breakdown":{"details":[]}}"#.utf8), plan: "Max")
        #expect(result.windows.count == 1)
        #expect(!result.windows.contains { $0.isFable })
    }
    @Test func testMalformedScopedSiblingsAndDuplicateEntries() throws {
        let valid = #"{"kind":"weekly_scoped","group":"weekly","percent":0,"scope":{"model":{"id":"fable","display_name":"Fable"}}}"#
        let data = Data((#"{"limits":[null,false,{"kind":"weekly_scoped","group":"weekly","percent":true,"scope":{"model":{"id":"bad-fable","display_name":"Fable"}}},{"kind":"weekly_scoped","group":"weekly","percent":10,"scope":{"model":{"id":"all-models","display_name":"All models"}}},"# + valid + "," + valid + "]}").utf8)
        let result = try UsageParser.claude(data: data, plan: "Max")
        #expect(result.windows.count == 1)
        #expect(result.windows[0].remainingPercent == 100)
        #expect(result.windows[0].isFable)
    }
    @Test func testInvalidScopedValuesStayUnavailable() {
        for value in ["null", "false", "\"20\"", "-1", "101"] {
            let data = Data((#"{"limits":[{"kind":"weekly_scoped","group":"weekly","percent":"# + value + #", "scope":{"model":{"id":"fable","display_name":"Fable"}}}]}"#).utf8)
            #expect(throws: (any Error).self) { try UsageParser.claude(data: data, plan: "Max") }
        }
    }
    @Test func testAttentionBoundariesUseConsumedAllowance() {
        for (used, expected) in [(0.0, UsageWindow.AttentionLevel.normal), (69.9, .normal), (70, .warning), (90, .warning), (90.1, .critical), (100, .critical)] {
            let window = UsageWindow(id: "fable", title: "Fable", usedPercent: used, resetsAt: nil, modelScope: "fable")
            #expect(window.attentionLevel == expected)
            #expect(window.remainingPercent == 100 - used)
        }
    }
    @Test func testClaudePercentMeansUsedAndUnknownIsNotZero() throws {
        let data = Data(#"{"five_hour":{"utilization":24,"resets_at":"2026-10-22T12:00:00.000Z"},"seven_day":{"utilization":null,"resets_at":null},"seven_day_sonnet":{"utilization":0,"resets_at":"2026-10-25T12:00:00Z"}}"#.utf8)
        let result = try UsageParser.claude(data: data, plan: "Max", now: now)
        #expect(result.windows.count == 3)
        #expect(result.windows[0].usedPercent == 24)
        #expect(result.windows[0].remainingPercent == 76)
        #expect(result.windows[0].resetsAt != nil)
        #expect(result.windows[1].usedPercent == nil)
        #expect(result.windows[1].remainingPercent == nil)
        #expect(result.windows[2].usedPercent == 0)
        #expect(result.windows[2].resetsAt != nil)
    }
    @Test func testInvalidPercentagesCannotBecomeLegitimateLimits() throws {
        for value in ["true", "false", "\"32\"", "-1", "101", "null"] {
            let data = Data("{\"five_hour\":{\"utilization\":\(value)}}".utf8)
            #expect(try UsageParser.claude(data: data, plan: "Max").windows[0].usedPercent == nil)
        }
    }
    @Test func testCodexActualWindowDurationAndMultipleBuckets() throws {
        let data = Data(#"{"result":{"rateLimits":{"primary":{"usedPercent":99}},"rateLimitsByLimitId":{"codex":{"planType":"pro","primary":{"usedPercent":25,"windowDurationMins":300,"resetsAt":1790001000},"secondary":{"usedPercent":40,"windowDurationMins":10080,"resetsAt":1790500000}},"review":{"limitName":"Code review","primary":{"usedPercent":8,"windowDurationMins":60,"resetsAt":1790002000}}},"rateLimitResetCredits":{"availableCount":3}}}"#.utf8)
        let result = try UsageParser.codex(data: data, now: now)
        #expect(result.windows.count == 3)
        #expect(result.windows[0].title == "5-hour session")
        #expect(result.windows[0].usedPercent == 25)
        #expect(result.windows[0].remainingPercent == 75)
        #expect(result.windows[0].resetsAt == Date(timeIntervalSince1970: 1_790_001_000))
        #expect(result.windows[1].title == "Weekly")
        #expect(result.windows[2].title == "Code review · 1-hour session")
        #expect(result.plan == "ChatGPT · Pro")
        #expect(result.note == "3 saved resets available")
    }
    @Test func testCodexLegacyResponseAndAbsentSecondary() throws {
        let result = try UsageParser.codex(data: Data(#"{"rateLimits":{"primary":{"usedPercent":0,"windowDurationMins":15},"secondary":null}}"#.utf8), plan: "plus")
        #expect(result.windows.count == 1)
        #expect(result.windows[0].title == "15-minute window")
        #expect(result.windows[0].usedPercent == 0)
        #expect(result.windows[0].resetsAt == nil)
        #expect(result.plan == "ChatGPT · Plus")
    }
    @Test func testEmptyAndErrorResponsesDoNotLookLikeUnusedQuota() {
        for json in ["{}", "{\"error\":\"Unauthorized\"}", "{\"rateLimits\":null}"] {
            #expect(throws: (any Error).self) { try UsageParser.codex(data: Data(json.utf8)) }
            #expect(throws: (any Error).self) { try UsageParser.claude(data: Data(json.utf8), plan: "Max") }
        }
    }
    @Test func testResetDoesNotInventAnEmptyWindow() {
        let window = UsageWindow(id: "test", title: "Session", usedPercent: 98, resetsAt: now.addingTimeInterval(-1))
        #expect(window.needsRefresh(at: now))
        #expect(window.usedPercent == 98)
        #expect(window.resetDescription(at: now) == "Reset due · awaiting refresh")
    }
    @Test func testCountdownAndUnknownReset() {
        #expect(UsageWindow(id: "a", title: "", usedPercent: 10, resetsAt: now.addingTimeInterval(3601)).resetDescription(at: now) == "Resets in 1h 1m")
        #expect(UsageWindow(id: "b", title: "", usedPercent: nil, resetsAt: nil).resetDescription(at: now) == "Reset time unavailable")
    }
}

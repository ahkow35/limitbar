import Foundation

public enum ProviderID: String, CaseIterable, Identifiable, Sendable {
    case claude, codex
    public var id: String { rawValue }
    public var name: String { self == .claude ? "Claude" : "Codex" }
    public var dashboard: URL {
        URL(string: self == .claude ? "https://claude.ai/settings/usage" : "https://chatgpt.com/codex/settings/usage")!
    }
}

public struct UsageWindow: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let usedPercent: Double?
    public let resetsAt: Date?
    public let modelScope: String?
    public init(id: String, title: String, usedPercent: Double?, resetsAt: Date?, modelScope: String? = nil) {
        self.id = id
        self.title = title
        self.usedPercent = usedPercent.flatMap { $0.isFinite && (0...100).contains($0) ? $0 : nil }
        self.resetsAt = resetsAt
        self.modelScope = modelScope
    }
    public var isFable: Bool {
        guard let modelScope else { return false }
        return modelScope.range(of: "(^|[^a-z])fable([^a-z]|$)", options: [.regularExpression, .caseInsensitive]) != nil
    }
    public var remainingPercent: Double? { usedPercent.map { 100 - $0 } }
    public enum AttentionLevel { case normal, warning, critical }
    public var attentionLevel: AttentionLevel {
        guard let usedPercent else { return .normal }
        if usedPercent > 90 { return .critical }
        if usedPercent >= 70 { return .warning }
        return .normal
    }
    // A passed reset is not evidence of a new, empty quota window.
    public func needsRefresh(at now: Date) -> Bool { resetsAt.map { $0 <= now } ?? false }
    public func resetDescription(at now: Date) -> String {
        guard let date = resetsAt else { return "Reset time unavailable" }
        let seconds = date.timeIntervalSince(now)
        guard seconds > 0 else { return "Reset due · awaiting refresh" }
        let minutes = max(1, Int(ceil(seconds / 60)))
        if minutes >= 1440 { return "Resets in \(minutes / 1440)d \((minutes % 1440) / 60)h" }
        if minutes >= 60 { return "Resets in \(minutes / 60)h \(minutes % 60)m" }
        return "Resets in \(minutes)m"
    }
}

public struct UsageSnapshot: Sendable {
    public let provider: ProviderID
    public let plan: String
    public let windows: [UsageWindow]
    public let updatedAt: Date
    public let source: String
    public let note: String?
    public init(provider: ProviderID, plan: String, windows: [UsageWindow], updatedAt: Date = Date(), source: String, note: String? = nil) {
        self.provider = provider; self.plan = plan; self.windows = windows
        self.updatedAt = updatedAt; self.source = source; self.note = note
    }
}

public struct ProviderFailure: LocalizedError, Sendable {
    public enum Kind: Sendable { case authentication, unavailable, network, malformed }
    public let kind: Kind
    public let message: String
    public init(_ kind: Kind, _ message: String) { self.kind = kind; self.message = message }
    public var errorDescription: String? { message }
}

public protocol UsageProvider: Sendable {
    var id: ProviderID { get }
    func fetch(allowInteraction: Bool) async throws -> UsageSnapshot
}

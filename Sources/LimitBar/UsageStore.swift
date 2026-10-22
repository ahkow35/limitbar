import AppKit
import Combine
import ServiceManagement
import LimitBarCore

struct ProviderState: Identifiable {
    let id: ProviderID
    var snapshot: UsageSnapshot?
    var error: String?
    var refreshing = false
    func isStale(at date: Date) -> Bool {
        error != nil || snapshot.map { date.timeIntervalSince($0.updatedAt) > 600 } ?? true
    }
}

@MainActor final class UsageStore: ObservableObject {
    @Published var states = ProviderID.allCases.map { ProviderState(id: $0) }
    @Published var pinned = false
    @Published var settingsOpen = false
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published var settingsError: String?
    @Published var showRemaining = UserDefaults.standard.bool(forKey: "showRemaining") {
        didSet { UserDefaults.standard.set(showRemaining, forKey: "showRemaining") }
    }
    @Published var now = Date()
    let providers: [any UsageProvider] = [ClaudeProvider(), CodexProvider()]
    private var timer: Timer?
    private var nextRefresh = Date.distantPast
    let preview: Bool

    init(preview: Bool = false) {
        self.preview = preview
        if preview {
            let now = Date()
            let alerts = CommandLine.arguments.contains("--preview-alerts")
            states = [
                ProviderState(id: .claude, snapshot: UsageSnapshot(provider: .claude, plan: "Max", windows: [
                    UsageWindow(id: "session", title: "5-hour session", usedPercent: alerts ? 74 : 24, resetsAt: now.addingTimeInterval(8460)),
                    UsageWindow(id: "weekly", title: "Weekly · all models", usedPercent: alerts ? 93 : 58, resetsAt: now.addingTimeInterval(218400)),
                    UsageWindow(id: "claude.scoped.fable", title: "Fable", usedPercent: 67, resetsAt: now.addingTimeInterval(218400), modelScope: "fable")
                ], source: "Sample data")),
                ProviderState(id: .codex, snapshot: UsageSnapshot(provider: .codex, plan: "ChatGPT · Plus", windows: [
                    UsageWindow(id: "session", title: "5-hour session", usedPercent: 12, resetsAt: now.addingTimeInterval(12360)),
                    UsageWindow(id: "weekly", title: "Weekly", usedPercent: 31, resetsAt: now.addingTimeInterval(363600))
                ], source: "Sample data", note: "3 saved resets available"))
            ]
        }
    }
    var refreshing: Bool { states.contains { $0.refreshing } }
    var connectedCount: Int { states.filter { $0.snapshot != nil && $0.error == nil }.count }
    func start() {
        guard !preview else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.now = Date()
                if self.now >= self.nextRefresh { self.refresh() }
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }
    func refresh(_ id: ProviderID? = nil, allowInteraction: Bool = false) {
        guard !preview else { return }
        nextRefresh = Date().addingTimeInterval(300)
        for provider in providers where id == nil || id == provider.id {
            guard let index = states.firstIndex(where: { $0.id == provider.id }), !states[index].refreshing else { continue }
            states[index].refreshing = true
            Task {
                do {
                    let snapshot = try await provider.fetch(allowInteraction: allowInteraction)
                    states[index].snapshot = snapshot
                    states[index].error = nil
                } catch {
                    states[index].error = (error as? ProviderFailure)?.message ?? "Usage check failed. Try refreshing."
                    if let failure = error as? ProviderFailure, failure.kind == .authentication || failure.kind == .malformed {
                        states[index].snapshot = nil
                    }
                }
                states[index].refreshing = false
                now = Date()
            }
        }
    }
    func toggleLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchAtLogin = SMAppService.mainApp.status == .enabled
            settingsError = SMAppService.mainApp.status == .requiresApproval ? "Allow LimitBar in System Settings → General → Login Items." : nil
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            settingsError = "Couldn’t change launch at login. Move LimitBar to Applications and try again."
        }
    }
    func menuText(for id: ProviderID) -> String {
        guard let state = states.first(where: { $0.id == id }), !state.isStale(at: now), let snapshot = state.snapshot else { return "—" }
        let windows = snapshot.windows
        guard !windows.contains(where: { $0.needsRefresh(at: now) }), let mostUsed = windows.compactMap(\.usedPercent).max() else { return "—" }
        return "\(Int((showRemaining ? 100 - mostUsed : mostUsed).rounded()))%"
    }
}

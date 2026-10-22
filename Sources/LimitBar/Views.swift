import SwiftUI
import AppKit
import LimitBarCore

private let secondaryInk = Color.white.opacity(0.60)
private let quietInk = Color.white.opacity(0.42)

extension ProviderID {
    var tint: Color {
        self == .claude ? Color(red: 0.96, green: 0.65, blue: 0.47) : Color(red: 0.68, green: 0.80, blue: 1)
    }
}

enum BrandAssets {
    static let openAI: NSImage = {
        let url = Bundle.main.url(forResource: "openai", withExtension: "svg")
            ?? Bundle.module.url(forResource: "openai", withExtension: "svg")
        let image = url.flatMap { NSImage(contentsOf: $0) } ?? NSImage()
        image.isTemplate = true
        return image
    }()
    static func menuMark(_ provider: ProviderID) -> NSImage {
        if provider == .codex {
            let copy = openAI.copy() as! NSImage
            copy.size = NSSize(width: 14, height: 14)
            return copy
        }
        let image = NSImage(size: NSSize(width: 14, height: 14), flipped: false) { _ in
            NSColor.labelColor.setStroke()
            for index in 0..<12 {
                let angle = Double(index) * .pi / 6
                let path = NSBezierPath()
                path.move(to: NSPoint(x: 7 + cos(angle) * 1.7, y: 7 + sin(angle) * 1.7))
                path.line(to: NSPoint(x: 7 + cos(angle) * 6, y: 7 + sin(angle) * 6))
                path.lineWidth = 1.15; path.lineCapStyle = .round
                path.stroke()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}

struct BrandMark: View {
    let provider: ProviderID
    var body: some View {
        Group {
            if provider == .claude {
                Canvas { context, size in
                    let center = CGPoint(x: size.width / 2, y: size.height / 2)
                    for index in 0..<12 {
                        let angle = Double(index) * .pi / 6
                        let inner: CGFloat = index % 2 == 0 ? 3 : 4
                        let outer: CGFloat = index % 3 == 0 ? 11 : 9.5
                        var path = Path()
                        path.move(to: CGPoint(x: center.x + cos(angle) * inner, y: center.y + sin(angle) * inner))
                        path.addLine(to: CGPoint(x: center.x + cos(angle) * outer, y: center.y + sin(angle) * outer))
                        context.stroke(path, with: .color(.white.opacity(0.85)), style: StrokeStyle(lineWidth: 1.9, lineCap: .round))
                    }
                }
            } else {
                Image(nsImage: BrandAssets.openAI).resizable().renderingMode(.template)
                    .scaledToFit().foregroundStyle(.white.opacity(0.93)).padding(1)
            }
        }.frame(width: 25, height: 25).accessibilityHidden(true)
    }
}

struct LimitBarView: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        VStack(spacing: 0) {
            header
            hairline
            if store.settingsOpen {
                settings.padding(16)
            } else if store.states.reduce(0, { $0 + ($1.snapshot?.windows.count ?? 0) }) > 8 {
                ScrollView { providerSections }
                    .scrollIndicators(.hidden)
                    .frame(height: max(180, (NSScreen.main?.visibleFrame.height ?? 800) - 160))
            } else {
                providerSections
            }
            hairline
            footer
        }
        .frame(width: 320)
        .fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(Color.white.opacity(0.94))
        .background {
            // AppKit supplies the actual glass behind this transparent hosting view.
            LinearGradient(colors: [.white.opacity(0.055), .clear, .black.opacity(0.025)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .allowsHitTesting(false)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.32), .white.opacity(0.06), .white.opacity(0.13)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.7)
                .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .preferredColorScheme(.dark)
    }
    private var providerSections: some View {
        VStack(spacing: 0) {
            ForEach(Array(store.states.enumerated()), id: \.element.id) { index, state in
                if index > 0 { hairline.padding(.horizontal, 16) }
                ProviderSection(state: state, now: store.now, remaining: store.showRemaining) {
                    store.refresh(state.id, allowInteraction: true)
                }.padding(16)
            }
        }
    }
    private var hairline: some View {
        Rectangle().fill(.white.opacity(0.16)).frame(maxWidth: .infinity).frame(height: 1)
    }
    private var header: some View {
        ZStack {
            Text(store.settingsOpen ? "Preferences" : (store.showRemaining ? "Remaining" : "Usage"))
                .font(.system(size: 13, weight: .semibold))
            HStack {
                Image(systemName: "chart.bar.fill").font(.system(size: 12)).foregroundStyle(secondaryInk).frame(width: 22)
                Spacer()
                Button { store.pinned.toggle() } label: {
                    Image(systemName: store.pinned ? "pin.fill" : "pin").font(.system(size: 11))
                        .foregroundStyle(store.pinned ? Color.white : secondaryInk)
                }.buttonStyle(QuietButtonStyle()).help(store.pinned ? "Unpin panel" : "Keep panel open").accessibilityLabel("Pin panel")
            }
        }.padding(.horizontal, 12).padding(.vertical, 11)
    }
    private var settings: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle("Show remaining", isOn: $store.showRemaining).toggleStyle(.switch).controlSize(.mini)
            Toggle("Launch at login", isOn: Binding(get: { store.launchAtLogin }, set: { store.toggleLaunchAtLogin($0) }))
                .toggleStyle(.switch).controlSize(.mini)
            Text("Usage refreshes every 5 minutes. The menu bar shows the most constrained allowance for each provider.")
                .font(.system(size: 11)).foregroundStyle(secondaryInk).fixedSize(horizontal: false, vertical: true)
            if let error = store.settingsError { Text(error).font(.system(size: 11)).foregroundStyle(.orange) }
            HStack {
                Button("Back to usage") { store.settingsOpen = false }.buttonStyle(.plain)
                Spacer()
                Button("Quit LimitBar") { NSApp.terminate(nil) }.buttonStyle(.plain).foregroundStyle(secondaryInk).keyboardShortcut("q")
            }
        }.font(.system(size: 12)).tint(Color.white.opacity(0.8))
    }
    private var updateLabel: String {
        if store.preview { return "Sample data" }
        guard let oldest = store.states.compactMap({ $0.snapshot?.updatedAt }).min() else { return "" }
        let minutes = max(0, Int(store.now.timeIntervalSince(oldest) / 60))
        return minutes < 1 ? "Updated just now" : "Updated \(minutes)m ago"
    }
    private var updateTooltip: String {
        if store.preview { return "Sample data — not live usage" }
        return store.states.compactMap { state in
            state.snapshot.map { "\(state.id.name): updated " + absoluteDate($0.updatedAt) }
        }.joined(separator: "\n")
    }
    private var footer: some View {
        HStack(spacing: 7) {
            Button { store.refresh(allowInteraction: true) } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise").font(.system(size: 10, weight: .medium))
                    Text(store.refreshing ? "Refreshing…" : "Refresh").font(.system(size: 10, weight: .medium))
                }.foregroundStyle(secondaryInk)
            }.buttonStyle(QuietButtonStyle()).disabled(store.refreshing || store.preview).keyboardShortcut("r")
            Spacer()
            Text(updateLabel).font(.system(size: 10)).foregroundStyle(quietInk).help(updateTooltip)
            Button { store.settingsOpen.toggle() } label: {
                Image(systemName: store.settingsOpen ? "chevron.left" : "gearshape").font(.system(size: 11)).foregroundStyle(secondaryInk)
            }.buttonStyle(QuietButtonStyle()).help(store.settingsOpen ? "Back to usage" : "Preferences").accessibilityLabel("Preferences")
        }.padding(.horizontal, 14).padding(.vertical, 8)
    }
}

private struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.padding(5)
            .background(RoundedRectangle(cornerRadius: 7).fill(.white.opacity(configuration.isPressed ? 0.14 : 0)))
            .contentShape(Rectangle()).opacity(configuration.isPressed ? 0.7 : 1)
    }
}

private struct ProviderSection: View {
    let state: ProviderState
    let now: Date
    let remaining: Bool
    let reconnect: () -> Void
    @State private var hovering = false
    private var sectionTooltip: String {
        var lines = ["Open \(state.id.name) usage dashboard"]
        if let snapshot = state.snapshot {
            if let note = snapshot.note { lines.append(note) }
            lines.append("Updated " + absoluteDate(snapshot.updatedAt))
        }
        return lines.joined(separator: "\n")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button { NSWorkspace.shared.open(state.id.dashboard) } label: {
                HStack(spacing: 8) {
                    BrandMark(provider: state.id)
                    Text(state.id.name).font(.system(size: 13, weight: .semibold))
                    Spacer()
                    if state.refreshing {
                        ProgressView().controlSize(.mini).scaleEffect(0.7).frame(width: 12, height: 12)
                    } else if state.isStale(at: now) && state.snapshot != nil {
                        Text("Stale").font(.system(size: 10)).foregroundStyle(.orange)
                    }
                    if let plan = state.snapshot?.plan {
                        HStack(spacing: 4) {
                            Text(plan.replacingOccurrences(of: "ChatGPT · ", with: ""))
                            Image(systemName: "arrow.up.right").font(.system(size: 8, weight: .medium))
                        }.font(.system(size: 10)).foregroundStyle(hovering ? Color.white : secondaryInk)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .overlay(Capsule().strokeBorder(.white.opacity(0.20), lineWidth: 0.5))
                    }
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).onHover { hovering = $0 }.help(sectionTooltip)
            if let snapshot = state.snapshot {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(snapshot.windows.filter { $0.usedPercent != nil }) { window in
                        MeterRow(window: window, now: now, remaining: window.isFable || remaining, stale: state.isStale(at: now))
                    }
                    if snapshot.windows.allSatisfy({ $0.usedPercent == nil }) {
                        Text("No usage data reported").font(.system(size: 11)).foregroundStyle(secondaryInk)
                    }
                    if state.id == .claude && !snapshot.windows.contains(where: { $0.isFable && $0.usedPercent != nil }) {
                        Text("Fable allowance not reported").font(.system(size: 10)).foregroundStyle(quietInk)
                            .help("Fable is shown only when Claude reports its model-specific allowance; shared weekly usage cannot establish it.")
                    }
                }
            }
            if let error = state.error {
                VStack(alignment: .leading, spacing: 9) {
                    Text(error).font(.system(size: 11)).foregroundStyle(secondaryInk).fixedSize(horizontal: false, vertical: true)
                    Button(action: reconnect) {
                        Text(state.refreshing ? "Connecting…" : (state.snapshot == nil ? "Connect \(state.id.name)" : "Try again"))
                            .font(.system(size: 11, weight: .medium)).foregroundStyle(state.id.tint)
                    }.buttonStyle(.plain).disabled(state.refreshing)
                }
            } else if state.snapshot == nil {
                Text("Checking subscription…").font(.system(size: 11)).foregroundStyle(secondaryInk).padding(.vertical, 6)
            }
        }
    }
}

private func absoluteDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "EEE d MMM, HH:mm z"
    return formatter.string(from: date)
}

private struct MeterRow: View {
    let window: UsageWindow
    let now: Date
    let remaining: Bool
    let stale: Bool
    private var expired: Bool { window.needsRefresh(at: now) }
    private var value: Double? { remaining ? window.remainingPercent : window.usedPercent }
    private var barColor: Color {
        if stale || expired { return Color.gray.opacity(0.6) }
        switch window.attentionLevel {
        case .critical: return Color(red: 1, green: 0.36, blue: 0.38)
        case .warning: return Color(red: 1, green: 0.73, blue: 0.30)
        case .normal: return Color.white.opacity(0.50)
        }
    }
    private var title: String {
        if window.isFable { return window.title.replacingOccurrences(of: "Weekly · ", with: "") + " · left" }
        if window.title == "Weekly · all models" { return "Weekly" }
        return window.title.replacingOccurrences(of: " session", with: "")
    }
    private var tooltip: String {
        var lines = [window.title]
        if let reset = window.resetsAt { lines.append("Resets " + absoluteDate(reset)) }
        if window.isFable { lines.append("Fable-specific allowance remaining. Shared session and weekly limits also apply.") }
        return lines.joined(separator: "\n")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title).font(.system(size: 11)).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
                Spacer(minLength: 8)
                Text(value.map { "\(Int($0.rounded()))%" } ?? "—")
                    .font(.system(size: 12, weight: .medium)).monospacedDigit()
                    .foregroundStyle(expired || stale ? secondaryInk : Color.white.opacity(0.95))
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.10))
                    if let value, value > 0 {
                        Capsule().fill(barColor)
                            .frame(width: max(3, proxy.size.width * value / 100))
                    }
                }
            }.frame(height: 4)
            if window.resetsAt != nil {
                Text((expired || stale ? "Last seen · " : "") + window.resetDescription(at: now))
                    .font(.system(size: 10)).foregroundStyle(secondaryInk).lineLimit(1)
            }
        }
        .help(tooltip)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(window.title), \(value.map { String(Int($0.rounded())) + " percent " + (remaining ? "remaining" : "used") } ?? "unavailable")\(expired || stale ? ", last seen" : ""), \(window.resetDescription(at: now))")
    }
}

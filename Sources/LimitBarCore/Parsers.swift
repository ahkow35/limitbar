import Foundation
import CoreFoundation

public enum UsageParser {
    private static func number(_ value: Any?) -> Double? {
        guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite else { return nil }
        return value.doubleValue
    }
    private static func percent(_ value: Any?) -> Double? {
        number(value).flatMap { (0...100).contains($0) ? $0 : nil }
    }
    private static func date(_ value: Any?) -> Date? {
        guard let string = value as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
    public static func claude(data: Data, plan: String, now: Date = Date()) throws -> UsageSnapshot {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderFailure(.malformed, "Claude returned an unreadable usage response.")
        }
        let known = [("five_hour", "5-hour session"), ("seven_day", "Weekly · all models"),
                     ("seven_day_sonnet", "Weekly · Sonnet"), ("seven_day_opus", "Weekly · Opus")]
        var windows: [UsageWindow] = known.compactMap { key, title in
            guard let row = object[key] as? [String: Any] else { return nil }
            return UsageWindow(id: key, title: title, usedPercent: percent(row["utilization"]), resetsAt: date(row["resets_at"]))
        }
        // Preserve future provider-specific quota windows without hard-coding model versions.
        for key in object.keys.sorted() where key.hasPrefix("seven_day_") && !known.contains(where: { $0.0 == key }) {
            // A breakdown object is not a quota. Only accept scalar measured utilization.
            guard let row = object[key] as? [String: Any], let used = percent(row["utilization"]) else { continue }
            windows.append(UsageWindow(id: key, title: "Weekly · " + key.replacingOccurrences(of: "seven_day_", with: "").replacingOccurrences(of: "_", with: " ").capitalized,
                                       usedPercent: used, resetsAt: date(row["resets_at"]), modelScope: key.replacingOccurrences(of: "seven_day_", with: "")))
        }
        // Claude's model limits are separate scoped entries, not values to infer
        // from total weekly usage. Parse siblings independently so malformed extras
        // cannot discard a valid Fable allowance.
        var seenScopes = Set(windows.compactMap(\.modelScope))
        for entry in object["limits"] as? [Any] ?? [] {
            guard let row = entry as? [String: Any], row["kind"] as? String == "weekly_scoped",
                  row["group"] as? String == "weekly",
                  let scope = row["scope"] as? [String: Any], let model = scope["model"] as? [String: Any],
                  let name = (model["display_name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty,
                  let used = percent(row["percent"]) else { continue }
            let identity = ((model["id"] as? String) ?? name).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let generic = [identity, name.lowercased()].contains { $0.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ") == "all models" }
            guard !identity.isEmpty, !generic, seenScopes.insert(identity).inserted else { continue }
            windows.append(UsageWindow(id: "claude.scoped." + identity, title: name,
                                       usedPercent: used, resetsAt: date(row["resets_at"]), modelScope: identity + " " + name))
        }
        guard !windows.isEmpty else { throw ProviderFailure(.malformed, "Claude returned no subscription limits. Open the usage dashboard to check your account.") }
        return UsageSnapshot(provider: .claude, plan: plan, windows: windows, updatedAt: now, source: "Claude subscription")
    }

    public static func codex(data: Data, plan: String? = nil, now: Date = Date()) throws -> UsageSnapshot {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderFailure(.malformed, "Codex returned an unreadable usage response.")
        }
        let result = object["result"] as? [String: Any] ?? object
        let buckets = result["rateLimitsByLimitId"] as? [String: [String: Any]]
        var windows: [UsageWindow] = []
        var reportedPlan: String?
        func add(_ bucket: [String: Any], id: String, prefix: String) {
            if id == "codex" || reportedPlan == nil { reportedPlan = bucket["planType"] as? String }
            for (key, fallback) in [("primary", "Session"), ("secondary", "Weekly")] {
                guard let row = bucket[key] as? [String: Any] else { continue }
                var title = fallback
                if let mins = number(row["windowDurationMins"]), mins > 0 {
                    if mins == 10080 { title = "Weekly" }
                    else if mins.truncatingRemainder(dividingBy: 1440) == 0 { title = "\(Int(mins / 1440))-day" }
                    else if mins.truncatingRemainder(dividingBy: 60) == 0 { title = "\(Int(mins / 60))-hour session" }
                    else { title = "\(Int(mins))-minute window" }
                }
                let reset = number(row["resetsAt"]).flatMap { $0 > 0 ? Date(timeIntervalSince1970: $0) : nil }
                windows.append(UsageWindow(id: "\(id).\(key)", title: prefix + title,
                                           usedPercent: percent(row["usedPercent"]), resetsAt: reset))
            }
        }
        if let buckets, !buckets.isEmpty {
            for key in buckets.keys.sorted(by: { a, b in a == "codex" ? b != "codex" : (b == "codex" ? false : a < b) }) {
                guard let bucket = buckets[key] else { continue }
                let label = bucket["limitName"] as? String ?? key
                add(bucket, id: key, prefix: key == "codex" ? "" : label + " · ")
            }
        } else if let bucket = result["rateLimits"] as? [String: Any] {
            add(bucket, id: "codex", prefix: "")
        }
        guard !windows.isEmpty else { throw ProviderFailure(.unavailable, "No subscription limits returned. Sign in to Codex with a ChatGPT subscription.") }
        var note: String?
        if let credits = result["rateLimitResetCredits"] as? [String: Any], let count = number(credits["availableCount"]), count >= 0 {
            note = "\(Int(count)) saved reset\(count == 1 ? "" : "s") available"
        }
        let name = (reportedPlan ?? plan)?.replacingOccurrences(of: "_", with: " ").capitalized
        return UsageSnapshot(provider: .codex, plan: name.map { "ChatGPT · " + $0 } ?? "ChatGPT subscription",
                             windows: windows, updatedAt: now, source: "Codex app server", note: note)
    }
}

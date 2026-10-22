import AppKit
import SwiftUI

final class GlassPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor enum GlassSurface {
    static func make(content: NSView) -> NSView {
        // Use the public macOS 26 class dynamically so this project also builds
        // with the installed macOS 15 SDK. Older systems use AppKit vibrancy.
        if #available(macOS 26, *), let type = NSClassFromString("NSGlassEffectView") as? NSView.Type {
            let glass = type.init(frame: content.frame)
            glass.setValue(22.0, forKey: "cornerRadius")
            glass.setValue(content, forKey: "contentView")
            glass.appearance = NSAppearance(named: .darkAqua)
            return glass
        }
        let material = NSVisualEffectView(frame: content.frame)
        material.material = .hudWindow
        material.blendingMode = .behindWindow
        material.state = .active
        material.wantsLayer = true
        material.layer?.cornerRadius = 22
        material.layer?.masksToBounds = true
        material.addSubview(content)
        content.autoresizingMask = [.width, .height]
        return material
    }
}

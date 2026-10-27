import AppKit
import SwiftUI

/// Liquid Glass 背景。現有工具鏈只有 macOS 15.5 SDK，沒有 SwiftUI 的 `glassEffect`，
/// 所以在執行期直接建立 AppKit 的 `NSGlassEffectView`；舊系統退回 `NSVisualEffectView`。
struct GlassBackground: NSViewRepresentable {
    var cornerRadius: CGFloat
    var tint: Color?

    init(cornerRadius: CGFloat, tint: Color? = nil) {
        self.cornerRadius = cornerRadius
        self.tint = tint
    }

    func makeNSView(context: Context) -> PassthroughView {
        let glass: NSView
        if let glassClass = NSClassFromString("NSGlassEffectView") as? NSView.Type {
            glass = glassClass.init(frame: .zero)
        } else {
            let effect = NSVisualEffectView()
            effect.material = .popover
            effect.blendingMode = .behindWindow
            effect.state = .active
            effect.wantsLayer = true
            effect.layer?.masksToBounds = true
            glass = effect
        }
        let container = PassthroughView()
        glass.frame = container.bounds
        glass.autoresizingMask = [.width, .height]
        container.addSubview(glass)
        return container
    }

    func updateNSView(_ container: PassthroughView, context: Context) {
        guard let glass = container.subviews.first else { return }
        if let effect = glass as? NSVisualEffectView {
            effect.layer?.cornerRadius = cornerRadius
            effect.layer?.backgroundColor = tint.map { NSColor($0).withAlphaComponent(0.85).cgColor }
        } else {
            glass.setValue(cornerRadius, forKey: "cornerRadius")
            glass.setValue(tint.map { NSColor($0) }, forKey: "tintColor")
        }
    }
}

/// 玻璃只負責畫面，滑鼠事件交給上層的 SwiftUI 控制項。
final class PassthroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

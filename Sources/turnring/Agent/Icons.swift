#if os(macOS)
import AppKit

/// The menu bar glyphs ship as SVGs in the bundle's Resources (see Resources/icon).
enum Icons {
    static func menuBar(paused: Bool) -> NSImage? {
        let name = paused ? "MenuBarPaused" : "MenuBar"
        guard let url = Bundle.main.url(forResource: name, withExtension: "svg"),
              let image = NSImage(contentsOf: url) else {
            return NSImage(systemSymbolName: paused ? "bell.slash" : "bell", accessibilityDescription: "Turnring")
        }
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        image.accessibilityDescription = paused ? "Turnring, paused" : "Turnring"
        return image
    }
}
#endif

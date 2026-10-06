// Renders AppIcon.svg into AppIcon.icns and previews the menu bar glyphs. Run: swift render.swift
import AppKit
func png(_ svg: String, _ px: Int, _ out: String) {
    let img = NSImage(data: try! Data(contentsOf: URL(fileURLWithPath: svg)))!
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    img.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
}
let set = "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: set, withIntermediateDirectories: true)
for s in [16, 32, 128, 256, 512] {
    png("AppIcon.svg", s, "\(set)/icon_\(s)x\(s).png")
    png("AppIcon.svg", s * 2, "\(set)/icon_\(s)x\(s)@2x.png")
}
if CommandLine.arguments.contains("--preview") {
    png("MenuBar.svg", 144, "preview-menubar.png")
    png("MenuBarPaused.svg", 144, "preview-menubar-paused.png")
    png("AppIcon.svg", 512, "preview-appicon.png")
}

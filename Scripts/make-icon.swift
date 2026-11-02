// SPDX-License-Identifier: GPL-3.0-or-later
// Reproducible original monochrome icon; no external artwork or font assets.
import AppKit
let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Build/NOIR.iconset")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let transform = NSAffineTransform(); transform.scale(by: CGFloat(pixels) / 1024); transform.concat()
        let panel = NSBezierPath(roundedRect: NSRect(x: 48, y: 48, width: 928, height: 928), xRadius: 218, yRadius: 218)
        NSGradient(starting: NSColor(white: 0.17, alpha: 1), ending: NSColor(white: 0.025, alpha: 1))!.draw(in: panel, angle: -90)
        NSColor(white: 0.5, alpha: 0.5).setStroke(); panel.lineWidth = 3; panel.stroke()
        let heights: [CGFloat] = [180, 350, 540, 350, 180]
        for (index, height) in heights.enumerated() {
            let x = 288 + CGFloat(index) * 112
            let bar = NSBezierPath(); bar.lineCapStyle = .round; bar.lineWidth = 45
            bar.move(to: NSPoint(x: x, y: 512 - height / 2)); bar.line(to: NSPoint(x: x, y: 512 + height / 2))
            NSColor(white: index == 2 ? 1 : 0.87, alpha: 1).setStroke(); bar.stroke()
        }
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
    }
}

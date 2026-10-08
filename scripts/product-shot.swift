#!/usr/bin/env swift
// Takes a product screenshot of MTA Menu: the menu bar item with its
// dropdown open, composited onto a gradient backdrop with rounded corners and
// a soft shadow.
//
// Usage:  swift scripts/product-shot.swift [output.png]
// Requires the app to be running (./scripts/run.sh). No Accessibility
// permission is needed: the app opens its own menu when it receives SIGUSR1.
import AppKit
import Foundation

let output = CommandLine.arguments.dropFirst().first ?? "docs/mta-menu.png"
let appName = "MTAMenu"

func shell(_ args: [String]) -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    p.arguments = args
    let pipe = Pipe()
    p.standardOutput = pipe
    try! p.run()
    p.waitUntilExit()
    return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
}

guard let pid = Int32(shell(["pgrep", "-x", appName]).trimmingCharacters(in: .whitespacesAndNewlines)) else {
    print("error: \(appName) is not running. Start it with ./scripts/run.sh"); exit(1)
}

// 1. Put a clean backdrop behind the menu so the shot doesn't show your desktop.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

/// Finds the app's menu window (CoreGraphics coordinates: origin top-left of the main display).
func menuRect() -> CGRect? {
    let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    var union: CGRect? = nil
    for w in windows where (w[kCGWindowOwnerPID as String] as? Int32) == pid {
        guard let b = w[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
        let r = CGRect(x: b["X"]!, y: b["Y"]!, width: b["Width"]!, height: b["Height"]!)
        union = union.map { $0.union(r) } ?? r
    }
    return union
}

/// NSScreen frames use a bottom-left origin; convert to CoreGraphics' top-left origin.
func cgFrame(of screen: NSScreen) -> CGRect {
    let mainHeight = NSScreen.screens[0].frame.height
    let f = screen.frame
    return CGRect(x: f.minX, y: mainHeight - f.maxY, width: f.width, height: f.height)
}

// 2. Open the menu once to learn which display it lives on (the menu bar
//    item sits on whichever display is active), then let it close.
kill(pid, SIGUSR1)
RunLoop.main.run(until: Date().addingTimeInterval(1.0))
guard let probe = menuRect(),
      let screen = NSScreen.screens.first(where: { cgFrame(of: $0).contains(CGPoint(x: probe.midX, y: probe.midY)) }) else {
    print("error: couldn't find \(appName)'s menu; is the app running?"); exit(1)
}
RunLoop.main.run(until: Date().addingTimeInterval(3.5))

// 3. Put a clean backdrop on that display so the shot doesn't show your desktop.
let backdrop = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
backdrop.level = .normal
backdrop.backgroundColor = NSColor(srgbRed: 0.96, green: 0.96, blue: 0.97, alpha: 1)
backdrop.orderFrontRegardless()
RunLoop.main.run(until: Date().addingTimeInterval(0.6))

// 4. Open the menu again for the real capture.
kill(pid, SIGUSR1)
RunLoop.main.run(until: Date().addingTimeInterval(1.2))
guard var region = menuRect() else { print("error: menu did not open"); exit(1) }
// Extend up to the top of that display so the menu bar item itself is included.
let top = cgFrame(of: screen).minY
region = CGRect(x: region.minX - 140, y: top, width: region.width + 280, height: region.maxY - top + 24)

// 4. Capture that region (in points; screencapture produces a Retina PNG).
let raw = NSTemporaryDirectory() + "mta-menu-raw.png"
_ = shell(["screencapture", "-x", "-R", "\(Int(region.minX)),\(Int(region.minY)),\(Int(region.width)),\(Int(region.height))", raw])
Thread.sleep(forTimeInterval: 0.3)
backdrop.orderOut(nil)

// 6. Composite onto a gradient.
guard let shot = NSImage(contentsOfFile: raw), let rep = shot.representations.first else {
    print("error: capture failed"); exit(1)
}
let shotW = CGFloat(rep.pixelsWide), shotH = CGFloat(rep.pixelsHigh)
let pad: CGFloat = 160, corner: CGFloat = 28
let canvas = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(shotW + pad * 2), pixelsHigh: Int(shotH + pad * 2),
                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                              colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: canvas)
let full = NSRect(x: 0, y: 0, width: canvas.pixelsWide, height: canvas.pixelsHigh)
NSGradient(colorsAndLocations:
    (NSColor(srgbRed: 0.07, green: 0.05, blue: 0.30, alpha: 1), 0.0),
    (NSColor(srgbRed: 0.35, green: 0.15, blue: 0.75, alpha: 1), 0.55),
    (NSColor(srgbRed: 0.72, green: 0.70, blue: 0.98, alpha: 1), 1.0))!
    .draw(in: full, angle: -50)

let frame = NSRect(x: pad, y: pad, width: shotW, height: shotH)
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
shadow.shadowBlurRadius = 60
shadow.shadowOffset = NSSize(width: 0, height: -24)
shadow.set()
NSColor.black.setFill()
NSBezierPath(roundedRect: frame, xRadius: corner, yRadius: corner).fill()
NSShadow().set()

NSBezierPath(roundedRect: frame, xRadius: corner, yRadius: corner).addClip()
shot.draw(in: frame, from: .zero, operation: .sourceOver, fraction: 1)
NSGraphicsContext.restoreGraphicsState()

try! canvas.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
print("wrote \(output) (\(canvas.pixelsWide)×\(canvas.pixelsHigh))")

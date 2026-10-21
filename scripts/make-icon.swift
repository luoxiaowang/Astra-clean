import AppKit
import Foundation

let destination = CommandLine.arguments[1]
let image = NSImage(size: NSSize(width: 1024, height: 1024))
image.lockFocus()
let background = NSBezierPath(roundedRect: NSRect(x: 24, y: 24, width: 976, height: 976), xRadius: 218, yRadius: 218)
NSGradient(starting: NSColor(calibratedRed: 0.12, green: 0.18, blue: 0.19, alpha: 1),
           ending: NSColor(calibratedRed: 0.04, green: 0.06, blue: 0.08, alpha: 1))!.draw(in: background, angle: -70)
let mint = NSColor(calibratedRed: 0.65, green: 0.88, blue: 0.72, alpha: 1)
for radius: CGFloat in [190, 285, 380] {
    mint.withAlphaComponent(0.2).setStroke()
    let orbit = NSBezierPath(ovalIn: NSRect(x: 512-radius, y: 512-radius, width: radius*2, height: radius*2))
    orbit.lineWidth = 3; orbit.stroke()
}
let star = NSBezierPath()
star.move(to: NSPoint(x: 512, y: 756))
star.curve(to: NSPoint(x: 756, y: 512), controlPoint1: NSPoint(x: 548, y: 548), controlPoint2: NSPoint(x: 548, y: 548))
star.curve(to: NSPoint(x: 512, y: 268), controlPoint1: NSPoint(x: 548, y: 476), controlPoint2: NSPoint(x: 548, y: 476))
star.curve(to: NSPoint(x: 268, y: 512), controlPoint1: NSPoint(x: 476, y: 476), controlPoint2: NSPoint(x: 476, y: 476))
star.curve(to: NSPoint(x: 512, y: 756), controlPoint1: NSPoint(x: 476, y: 548), controlPoint2: NSPoint(x: 476, y: 548))
star.close(); mint.setFill(); star.fill()
NSBezierPath(ovalIn: NSRect(x: 773, y: 737, width: 46, height: 46)).fill()
mint.withAlphaComponent(0.55).setFill()
NSBezierPath(ovalIn: NSRect(x: 257, y: 319, width: 24, height: 24)).fill()
image.unlockFocus()
let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: destination))

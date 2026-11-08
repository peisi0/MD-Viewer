import AppKit
import CoreGraphics
import Foundation

// Generates a 1024x1024 Liquid-Glass-flavoured app icon for MD Viewer.
let S: CGFloat = 1024
let out = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "MDViewer/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

let cs = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: Int(S), height: Int(S),
                          bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fatalError("cannot create bitmap context")
}

// Flip so (0,0) is top-left, like SwiftUI/AppKit.
ctx.translateBy(x: 0, y: S)
ctx.scaleBy(x: 1, y: -1)
NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)

func rounded(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

// 1. Base diagonal gradient
let base = CGGradient(colorsSpace: cs, colors: [
    rgb(16, 20, 48), rgb(43, 27, 92), rgb(24, 74, 110), rgb(12, 26, 62)
] as CFArray, locations: [0, 0.38, 0.72, 1])!
ctx.drawLinearGradient(base, start: CGPoint(x: 0, y: 0), end: CGPoint(x: S, y: S), options: [])

// 2. Soft colour blooms behind the glass (gives the glass something to refract)
func bloom(_ c: CGPoint, _ r: CGFloat, _ inner: CGColor) {
    let g = CGGradient(colorsSpace: cs, colors: [inner, inner.copy(alpha: 0)!] as CFArray,
                       locations: [0, 1])!
    ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: r, options: [])
}
bloom(CGPoint(x: 190, y: 170), 560, rgb(126, 92, 255, 0.95))
bloom(CGPoint(x: 850, y: 300), 480, rgb(64, 200, 232, 0.85))
bloom(CGPoint(x: 520, y: 930), 520, rgb(255, 105, 180, 0.62))
bloom(CGPoint(x: 900, y: 880), 380, rgb(88, 232, 190, 0.55))

// 3. The glass sheet
let sheet = CGRect(x: 108, y: 150, width: 808, height: 724)
ctx.saveGState()
ctx.addPath(rounded(sheet, 168))
ctx.clip()
let sheen = CGGradient(colorsSpace: cs, colors: [
    rgb(255, 255, 255, 0.30), rgb(255, 255, 255, 0.07), rgb(255, 255, 255, 0.16)
] as CFArray, locations: [0, 0.55, 1])!
ctx.drawLinearGradient(sheen, start: CGPoint(x: sheet.minX, y: sheet.minY),
                       end: CGPoint(x: sheet.maxX, y: sheet.maxY), options: [])
// diagonal specular streak
let streak = CGGradient(colorsSpace: cs, colors: [
    rgb(255, 255, 255, 0), rgb(255, 255, 255, 0.26), rgb(255, 255, 255, 0)
] as CFArray, locations: [0, 0.5, 1])!
ctx.drawLinearGradient(streak, start: CGPoint(x: 60, y: 650), end: CGPoint(x: 700, y: 40), options: [])
ctx.restoreGState()

// rim light
ctx.addPath(rounded(sheet, 168))
ctx.setStrokeColor(rgb(255, 255, 255, 0.70))
ctx.setLineWidth(7)
ctx.strokePath()
ctx.addPath(rounded(sheet.insetBy(dx: 12, dy: 12), 156))
ctx.setStrokeColor(rgb(255, 255, 255, 0.20))
ctx.setLineWidth(3)
ctx.strokePath()

// 4. Wordmark
let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .center
let mdFont = NSFont.systemFont(ofSize: 320, weight: .heavy)
let mdAttrs: [NSAttributedString.Key: Any] = [
    .font: mdFont,
    .foregroundColor: NSColor.white,
    .paragraphStyle: paragraph,
    .kern: -12
]
let md = NSAttributedString(string: "MD", attributes: mdAttrs)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: 12), blur: 34,
              color: rgb(10, 12, 40, 0.55))
md.draw(in: CGRect(x: 130, y: 278, width: 764, height: 380))
ctx.restoreGState()

// 5. Caption pill
let pill = CGRect(x: 342, y: 668, width: 340, height: 84)
ctx.addPath(rounded(pill, 42))
ctx.setFillColor(rgb(255, 255, 255, 0.24))
ctx.fillPath()
ctx.addPath(rounded(pill, 42))
ctx.setStrokeColor(rgb(255, 255, 255, 0.65))
ctx.setLineWidth(3)
ctx.strokePath()

let caption = NSAttributedString(string: "VIEWER", attributes: [
    .font: NSFont.systemFont(ofSize: 42, weight: .semibold),
    .foregroundColor: NSColor.white,
    .paragraphStyle: paragraph,
    .kern: 9
])
caption.draw(in: CGRect(x: pill.minX, y: pill.minY + 20, width: pill.width, height: 52))

// 6. Small "glassy" markdown glyph at the top of the sheet
ctx.setStrokeColor(rgb(255, 255, 255, 0.72))
ctx.setLineWidth(11)
ctx.setLineCap(.round)
for (i, len) in [(0, 128), (1, 92), (2, 112)] as [(Int, CGFloat)] {
    let y: CGFloat = 218 + CGFloat(i) * 30
    ctx.move(to: CGPoint(x: 452, y: y))
    ctx.addLine(to: CGPoint(x: 452 + len, y: y))
    ctx.strokePath()
}

NSGraphicsContext.current = nil
guard let cgImage = ctx.makeImage() else { fatalError("cannot make image") }
let rep = NSBitmapImageRep(cgImage: cgImage)
guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("png failed") }
try png.write(to: URL(fileURLWithPath: out), options: .atomic)
print("wrote \(out) (\(png.count) bytes)")

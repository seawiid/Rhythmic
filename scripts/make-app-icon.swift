// Renders the app icon: a white "R" with a gold ring at cap height on slate.
// Usage: swift scripts/make-app-icon.swift App/Rhythmic/Assets.xcassets/AppIcon.appiconset/AppIcon.png
import AppKit
import CoreText
import ImageIO

let size = 1024
let slate = NSColor(srgbRed: 0x38/255, green: 0x40/255, blue: 0x50/255, alpha: 1)
let gold = NSColor(srgbRed: 0xCB/255, green: 0xA6/255, blue: 0x5B/255, alpha: 1)   // Palette.brand (light)

let capHeight: CGFloat = 350
let ringDiameter: CGFloat = 150
let ringStroke: CGFloat = 34
let gap: CGFloat = 6

// Opaque sRGB bitmap: App Store icons must not have an alpha channel.
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!

ctx.setFillColor(slate.cgColor)
ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

// Size the font so the R's cap height is exactly `capHeight`.
let probe = NSFont.systemFont(ofSize: 100, weight: .regular)
let font = NSFont.systemFont(ofSize: 100 * capHeight / probe.capHeight, weight: .regular)
let line = CTLineCreateWithAttributedString(NSAttributedString(string: "R", attributes: [.font: font, .foregroundColor: NSColor.white]))
let glyph = CTLineGetImageBounds(line, ctx)

// Centre [R, gap, ring] horizontally and the cap height vertically.
let total = glyph.width + gap + ringDiameter
let originX = (CGFloat(size) - total) / 2
let baseline = (CGFloat(size) - capHeight) / 2
ctx.textPosition = CGPoint(x: originX - glyph.minX, y: baseline)
CTLineDraw(line, ctx)

let ringRect = CGRect(x: originX + glyph.width + gap, y: baseline + capHeight - ringDiameter,
                      width: ringDiameter, height: ringDiameter).insetBy(dx: ringStroke / 2, dy: ringStroke / 2)
ctx.setStrokeColor(gold.cgColor)
ctx.setLineWidth(ringStroke)
ctx.strokeEllipse(in: ringRect)

let url = URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL
let dest = CGImageDestinationCreateWithURL(url, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
precondition(CGImageDestinationFinalize(dest))

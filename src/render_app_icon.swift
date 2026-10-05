import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let space = CGColorSpaceCreateDeviceRGB()
let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
guard let context = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8,
    bytesPerRow: 0, space: space, bitmapInfo: bitmapInfo
) else { fatalError("Could not create icon canvas") }

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [red, green, blue, alpha])!
}

func gradient(_ colors: [CGColor], _ locations: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: space, colors: colors as CFArray, locations: locations)!
}

let tile = CGPath(
    roundedRect: CGRect(x: 64, y: 64, width: 896, height: 896),
    cornerWidth: 202, cornerHeight: 202, transform: nil
)
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -18), blur: 38, color: color(0, 0, 0, 0.28))
context.addPath(tile)
context.setFillColor(color(0.10, 0.10, 0.11))
context.fillPath()
context.restoreGState()

context.saveGState()
context.addPath(tile)
context.clip()
context.drawLinearGradient(
    gradient([color(0.21, 0.18, 0.17), color(0.09, 0.10, 0.12)], [0, 1]),
    start: CGPoint(x: 156, y: 922), end: CGPoint(x: 870, y: 82),
    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
)
context.restoreGState()

context.addPath(tile)
context.setStrokeColor(color(1, 0.83, 0.64, 0.12))
context.setLineWidth(5)
context.strokePath()

// The handle sits behind the side-view cup body.
let handle = CGMutablePath()
handle.move(to: CGPoint(x: 650, y: 564))
handle.addCurve(
    to: CGPoint(x: 658, y: 344),
    control1: CGPoint(x: 850, y: 630),
    control2: CGPoint(x: 876, y: 315)
)
context.saveGState()
context.addPath(handle)
context.setStrokeColor(color(0.99, 0.63, 0.36))
context.setLineWidth(58)
context.setLineCap(.round)
context.strokePath()
context.restoreGState()

let cup = CGMutablePath()
cup.move(to: CGPoint(x: 270, y: 606))
cup.addLine(to: CGPoint(x: 678, y: 606))
cup.addLine(to: CGPoint(x: 646, y: 354))
cup.addCurve(
    to: CGPoint(x: 565, y: 266),
    control1: CGPoint(x: 636, y: 298),
    control2: CGPoint(x: 610, y: 266)
)
cup.addLine(to: CGPoint(x: 387, y: 266))
cup.addCurve(
    to: CGPoint(x: 304, y: 354),
    control1: CGPoint(x: 341, y: 266),
    control2: CGPoint(x: 313, y: 298)
)
cup.closeSubpath()
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -12), blur: 22, color: color(0, 0, 0, 0.24))
context.addPath(cup)
context.setFillColor(color(0.95, 0.55, 0.29))
context.fillPath()
context.restoreGState()

context.saveGState()
context.addPath(cup)
context.clip()
context.drawLinearGradient(
    gradient([color(1.0, 0.81, 0.55), color(0.94, 0.48, 0.27)], [0, 1]),
    start: CGPoint(x: 390, y: 610), end: CGPoint(x: 610, y: 255),
    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
)
context.restoreGState()

// A clean rim makes the side-view silhouette readable at small sizes.
context.move(to: CGPoint(x: 270, y: 606))
context.addLine(to: CGPoint(x: 678, y: 606))
context.setStrokeColor(color(1.0, 0.85, 0.67))
context.setLineWidth(26)
context.setLineCap(.round)
context.strokePath()

for offset: CGFloat in [0, 150] {
    let steam = CGMutablePath()
    steam.move(to: CGPoint(x: 384 + offset, y: 666))
    steam.addCurve(
        to: CGPoint(x: 399 + offset, y: 828),
        control1: CGPoint(x: 323 + offset, y: 730),
        control2: CGPoint(x: 445 + offset, y: 764)
    )
    context.addPath(steam)
    context.setStrokeColor(color(1.0, 0.88, 0.72))
    context.setLineWidth(37)
    context.setLineCap(.round)
    context.strokePath()
}

guard let image = context.makeImage() else { fatalError("Could not render icon") }
let url = URL(fileURLWithPath: CommandLine.arguments[1])
guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    fatalError("Could not create PNG")
}
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("Could not save PNG") }

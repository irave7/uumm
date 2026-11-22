import AppKit
import CoreGraphics

let size = 1024
guard CommandLine.arguments.count == 2,
      let canvas = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                             space: CGColorSpace(name: CGColorSpace.sRGB)!,
                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fatalError("用法：swift DrawIcon.swift <输出 PNG>")
}

func color(_ rgb: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255, alpha: alpha)
}

func fill(_ path: CGPath, _ color: CGColor) {
    canvas.addPath(path)
    canvas.setFillColor(color)
    canvas.fillPath()
}

func roundRect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: CGRect(x: x, y: y, width: width, height: height),
           cornerWidth: radius, cornerHeight: radius, transform: nil)
}

canvas.translateBy(x: 0, y: CGFloat(size))
canvas.scaleBy(x: 1, y: -1)
fill(roundRect(96, 96, 832, 832, 188), color(0xFFFFFF))
fill(roundRect(330, 188, 366, 656, 88), color(0x0849EB))

// 左侧折面穿过蓝色机身，在机身上的交叠自然变深。
let fold = CGMutablePath()
fold.move(to: CGPoint(x: 363, y: 530))
fold.addLine(to: CGPoint(x: 190, y: 630))
fold.addQuadCurve(to: CGPoint(x: 190, y: 682), control: CGPoint(x: 159, y: 654))
fold.addLine(to: CGPoint(x: 330, y: 763))
fold.addLine(to: CGPoint(x: 620, y: 597))
fold.addLine(to: CGPoint(x: 620, y: 530))
fold.closeSubpath()
fill(fold, color(0x00DAF5, alpha: 0.87))

let screen = roundRect(360, 282, 306, 504, 52)
fill(screen, color(0x08E6F7))
canvas.saveGState()
canvas.addPath(screen)
canvas.clip()
let foldedScreen = CGMutablePath()
foldedScreen.move(to: CGPoint(x: 360, y: 746))
foldedScreen.addLine(to: CGPoint(x: 666, y: 570))
foldedScreen.addLine(to: CGPoint(x: 666, y: 786))
foldedScreen.addLine(to: CGPoint(x: 360, y: 786))
foldedScreen.closeSubpath()
fill(foldedScreen, color(0x0578EC))
canvas.restoreGState()
fill(roundRect(462, 223, 102, 25, 12.5), color(0xFFFFFF))

guard let image = canvas.makeImage(),
      let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
    fatalError("无法生成图标 PNG")
}
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]), options: .atomic)

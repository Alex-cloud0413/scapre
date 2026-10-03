#!/usr/bin/env swift

import AppKit

let size = 1024
let rect = CGRect(x: 0, y: 0, width: size, height: size)

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: size, pixelsHigh: size,
    bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false,
    colorSpaceName: .calibratedRGB,
    bytesPerRow: 0, bitsPerPixel: 0
) else { exit(1) }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// ── 1. 圆角方形背景（深蓝紫渐变，现代感）──
let bgPath = NSBezierPath(roundedRect: rect.insetBy(dx: 36, dy: 36),
                          xRadius: 180, yRadius: 180)
let gradient = NSGradient(colorsAndLocations:
    (NSColor(red: 0.20, green: 0.30, blue: 0.72, alpha: 1.0), 0.0),   // 亮蓝紫
    (NSColor(red: 0.12, green: 0.15, blue: 0.50, alpha: 1.0), 0.5),   // 深蓝
    (NSColor(red: 0.08, green: 0.06, blue: 0.30, alpha: 1.0), 1.0))   // 暗紫
gradient?.draw(in: bgPath, angle: -45)

// ── 2. 取景框（白色圆角方形，截图框的感觉）──
let boxInset: CGFloat = 240
let box = rect.insetBy(dx: boxInset, dy: boxInset)
let cornerRadius: CGFloat = 32

let framePath = NSBezierPath(roundedRect: box, xRadius: cornerRadius, yRadius: cornerRadius)
framePath.lineWidth = 24
framePath.lineCapStyle = .round
framePath.lineJoinStyle = .round
NSColor.white.setStroke()
framePath.stroke()

// ── 3. 取景框四个角的高亮标记 ──
let dotSize: CGFloat = 48
let dotInset: CGFloat = 40

func dot(at point: CGPoint) {
    let dotRect = CGRect(x: point.x - dotSize/2, y: point.y - dotSize/2,
                         width: dotSize, height: dotSize)
    let dotPath = NSBezierPath(ovalIn: dotRect)
    NSColor(red: 0.35, green: 0.80, blue: 0.55, alpha: 1.0).setFill()  // 绿色
    dotPath.fill()
}

// 四个角的圆点
dot(at: CGPoint(x: box.minX + dotInset, y: box.maxY - dotInset))  // 左上
dot(at: CGPoint(x: box.maxX - dotInset, y: box.maxY - dotInset))  // 右上
dot(at: CGPoint(x: box.minX + dotInset, y: box.minY + dotInset))  // 左下
dot(at: CGPoint(x: box.maxX - dotInset, y: box.minY + dotInset))  // 右下

// ── 4. 中心相机图标（SF Symbol camera.viewfinder）──
let symbolCenter = NSPoint(x: size/2, y: size/2)
let symbolSize: CGFloat = 200
let sConfig = NSImage.SymbolConfiguration(pointSize: symbolSize, weight: .medium)
if let symbol = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: nil)?
    .withSymbolConfiguration(sConfig) {
    symbol.isTemplate = true
    let symbolRect = CGRect(x: symbolCenter.x - symbolSize/2,
                            y: symbolCenter.y - symbolSize/2,
                            width: symbolSize, height: symbolSize)
    NSColor.white.set()
    symbol.draw(in: symbolRect)
}

// ── 5. 顶部状态栏红点（模拟截图录制的感觉）──
let recordDotCenter = NSPoint(x: size/2 + 40, y: size/2 + 70)
let recordDotRadius: CGFloat = 14
let recordDotPath = NSBezierPath(ovalIn: CGRect(
    x: recordDotCenter.x - recordDotRadius,
    y: recordDotCenter.y - recordDotRadius,
    width: recordDotRadius * 2,
    height: recordDotRadius * 2))
NSColor(red: 1.0, green: 0.27, blue: 0.23, alpha: 1.0).setFill()  // 红色录制指示
recordDotPath.fill()

NSGraphicsContext.restoreGraphicsState()

// ── 输出 ──
let iconDir = NSString(string: "~").expandingTildeInPath
    + "/Desktop/Scapare/Scapare/Assets.xcassets/AppIcon.appiconset"

let pngPath = iconDir + "/icon_1024.png"
try rep.representation(using: NSBitmapImageRep.FileType.png, properties: [:])?
    .write(to: URL(fileURLWithPath: pngPath))
print("✅ 图标已生成: \(pngPath)")

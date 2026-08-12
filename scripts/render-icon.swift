#!/usr/bin/env swift
// ============================================================
// TokenWatch 图标渲染脚本(纯 CoreGraphics)
// 用法: swift scripts/render-icon.swift [输出目录]
// 输出: 1024px 主图 + iconset 全部尺寸 PNG
// 设计: 蓝紫渐变底 + 白色包裹箱(2.5D)+ 三根上升柱(今日/近7日/累计)
// 坐标: 绘制坐标系 y 向上,CGContext 标准翻转输出直立图像
// ============================================================
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let S = 1024
let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/icon"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func cgcolor(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: r, green: g, blue: b, alpha: a)
}
let rgb = CGColorSpaceCreateDeviceRGB()

func render(size: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                        bytesPerRow: 0, space: rgb,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let u = CGFloat(size)
    // 标准翻转:绘制坐标 y 向上,输出图像直立
    ctx.translateBy(x: 0, y: u)
    ctx.scaleBy(x: 1, y: -1)

    // ---- 背景:蓝(左上)→ 紫(右下)对角渐变 ----
    let bg = CGGradient(colorsSpace: rgb, colors: [
        cgcolor(0.36, 0.55, 1.00),   // #5B8CFF
        cgcolor(0.55, 0.36, 0.96)    // #8B5CF6
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: u), end: CGPoint(x: u, y: 0), options: [])

    // 左上柔光
    let glow = CGGradient(colorsSpace: rgb, colors: [
        cgcolor(1, 1, 1, 0.22), cgcolor(1, 1, 1, 0)
    ] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 0.22 * u, y: 0.79 * u), startRadius: 0,
                           endCenter: CGPoint(x: 0.22 * u, y: 0.79 * u), endRadius: 0.66 * u, options: [])

    // 地面柔影(径向,黑 14%)
    let ground = CGGradient(colorsSpace: rgb, colors: [
        cgcolor(0, 0, 0, 0.14), cgcolor(0, 0, 0, 0)
    ] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(ground, startCenter: CGPoint(x: 0.5 * u, y: 0.64 * u), startRadius: 0,
                           endCenter: CGPoint(x: 0.5 * u, y: 0.64 * u), endRadius: 0.32 * u, options: [])

    let s = u / CGFloat(S)  // 缩放系数(尺寸变化时按比例)

    // ---- 包裹箱(2.5D)----
    // 顶面
    let tp = CGMutablePath()
    tp.move(to: CGPoint(x: 250 * s, y: 260 * s))
    tp.addLine(to: CGPoint(x: 700 * s, y: 260 * s))
    tp.addLine(to: CGPoint(x: 760 * s, y: 190 * s))
    tp.addLine(to: CGPoint(x: 310 * s, y: 190 * s))
    tp.closeSubpath()
    ctx.addPath(tp); ctx.setFillColor(cgcolor(0.867, 0.902, 0.961)); ctx.fillPath()   // #DDE6F4

    // 右侧面
    let rp = CGMutablePath()
    rp.move(to: CGPoint(x: 700 * s, y: 260 * s))
    rp.addLine(to: CGPoint(x: 700 * s, y: 610 * s))
    rp.addLine(to: CGPoint(x: 760 * s, y: 540 * s))
    rp.addLine(to: CGPoint(x: 760 * s, y: 190 * s))
    rp.closeSubpath()
    ctx.addPath(rp); ctx.setFillColor(cgcolor(0.761, 0.816, 0.902)); ctx.fillPath()   // #C2D0E6

    // 前面(白渐变,带阴影)
    let front = CGPath(roundedRect: CGRect(x: 250 * s, y: 260 * s, width: 450 * s, height: 350 * s),
                       cornerWidth: 48 * s, cornerHeight: 48 * s, transform: nil)
    ctx.setShadow(offset: CGSize(width: 0, height: -10 * s), blur: 50 * s, color: cgcolor(0, 0, 0, 0.22))
    ctx.addPath(front)
    let frontG = CGGradient(colorsSpace: rgb, colors: [
        cgcolor(1, 1, 1), cgcolor(0.929, 0.949, 0.980)   // #FFFFFF → #EDF2FA
    ] as CFArray, locations: [0, 1])!
    ctx.clip()
    ctx.drawLinearGradient(frontG, start: CGPoint(x: 250 * s, y: 610 * s), end: CGPoint(x: 250 * s, y: 260 * s), options: [])
    ctx.setShadow(offset: .zero, blur: 0, color: nil)     // 清除阴影

    // 箱盖带(前面上部加深,裁剪到前面路径)
    ctx.addPath(front); ctx.clip()
    ctx.setFillColor(cgcolor(0.902, 0.925, 0.969))        // #E6ECF7
    ctx.fill(CGRect(x: 250 * s, y: 430 * s, width: 450 * s, height: 180 * s))
    // 分隔线
    ctx.setStrokeColor(cgcolor(0.80, 0.84, 0.91))
    ctx.setLineWidth(6 * s)
    ctx.move(to: CGPoint(x: 268 * s, y: 430 * s))
    ctx.addLine(to: CGPoint(x: 682 * s, y: 430 * s))
    ctx.strokePath()
    ctx.resetClip()

    // ---- 三根上升柱 ----
    func bar(x: CGFloat, height: CGFloat) {
        let bottom: CGFloat = 700
        let w: CGFloat = 88
        let top = bottom - height
        let path = CGMutablePath()
        path.move(to: CGPoint(x: x * s, y: bottom * s))
        path.addLine(to: CGPoint(x: x * s, y: (top + 44) * s))
        path.addArc(center: CGPoint(x: (x + 44) * s, y: (top + 44) * s), radius: 44 * s,
                    startAngle: .pi, endAngle: 0, clockwise: false)   // y-up 空间 π→0 逆时针过顶部
        path.addLine(to: CGPoint(x: (x + w) * s, y: bottom * s))
        path.closeSubpath()
        ctx.setShadow(offset: CGSize(width: 0, height: -8 * s), blur: 40 * s, color: cgcolor(0, 0, 0, 0.25))
        ctx.addPath(path)
        let g = CGGradient(colorsSpace: rgb, colors: [
            cgcolor(0.02, 0.59, 0.41),   // #059669 深
            cgcolor(0.43, 0.91, 0.72)    // #6EE7B7 亮
        ] as CFArray, locations: [0, 1])!
        ctx.clip()
        ctx.drawLinearGradient(g, start: CGPoint(x: x * s, y: bottom * s),
                                  end: CGPoint(x: x * s, y: top * s), options: [])
        ctx.resetClip()
        ctx.setShadow(offset: .zero, blur: 0, color: nil)
    }
    bar(x: 320, height: 130)
    bar(x: 432, height: 215)
    bar(x: 544, height: 300)

    return ctx.makeImage()!
}

// ---- 输出 ----
func write(_ image: CGImage, to name: String) {
    let url = URL(fileURLWithPath: "\(outDir)/\(name)") as CFURL
    let dest = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

let master = render(size: S)
write(master, to: "icon_512x512@2x.png")
print("✅ 主图 1024px 已生成")

// 其余尺寸用缩略图方式生成
func downscale(_ px: Int, _ name: String) {
    let src = CGImageSourceCreateWithData(
        (try! Data(contentsOf: URL(fileURLWithPath: "\(outDir)/icon_512x512@2x.png"))) as CFData, nil)!
    let thumb = CGImageSourceCreateThumbnailAtIndex(src, 0, [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceThumbnailMaxPixelSize: px
    ] as CFDictionary)!
    write(thumb, to: name)
}
let sizes: [(Int, String)] = [
    (16, "icon_16x16.png"), (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"), (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"), (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"), (512, "icon_512x512.png"),
]
for (px, name) in sizes { downscale(px, name) }
print("✅ 全部 \(sizes.count + 1) 个 PNG 输出到 \(outDir)")

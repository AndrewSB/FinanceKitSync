#!/usr/bin/env swift
//
//  make-icon.swift
//  FinanceKitSync
//
//  Renders Assets.xcassets/AppIcon.appiconset/icon-1024.png.
//
//  A script rather than a committed binary asset nobody can edit: the icon is
//  ~40 lines of geometry, and regenerating it after a tweak is one command.
//
//      swift app/Supporting/make-icon.swift
//
//  Design: two arrows chasing each other around a circle — the sync loop — over
//  a deep green field. Reads at 40pt because it's one shape with one hole, no
//  text, and no fine detail.
//
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024.0
let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : FileManager.default.currentDirectoryPath
        + "/app/FinanceKitSync/Assets.xcassets/AppIcon.appiconset/icon-1024.png"

guard let context = CGContext(
    data: nil, width: Int(size), height: Int(size),
    bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    // noneSkipLast: App Store icons must be fully opaque. An alpha channel here
    // is an automatic rejection at upload.
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
) else {
    FileHandle.standardError.write(Data("could not create bitmap context\n".utf8))
    exit(1)
}

// MARK: - Background

let bgColors = [
    CGColor(red: 0.106, green: 0.318, blue: 0.231, alpha: 1),   // deep green
    CGColor(red: 0.180, green: 0.478, blue: 0.353, alpha: 1),   // the app accent
] as CFArray
if let gradient = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: bgColors, locations: [0, 1]
) {
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0),
        options: []
    )
}

// MARK: - Sync loop

let center = CGPoint(x: size / 2, y: size / 2)
let radius = size * 0.27
let lineWidth = size * 0.085
let ink = CGColor(red: 0.965, green: 0.976, blue: 0.969, alpha: 1)

context.setStrokeColor(ink)
context.setFillColor(ink)
context.setLineWidth(lineWidth)
context.setLineCap(.butt)

/// One arc plus a triangular arrowhead at its leading end.
///
/// The head is built in polar terms: its two base corners sit at the same
/// angle as the arc's end, offset radially to either side of the stroke, and
/// its tip sits further along the arc at the mean radius. That keeps it
/// pointing *along* the circle rather than away from it.
func arm(startDegrees: Double, sweepDegrees: Double) {
    let start = startDegrees * .pi / 180
    let end = (startDegrees + sweepDegrees) * .pi / 180

    // How far past the arc's end the tip reaches, in radians. Derived from the
    // stroke width so the head stays proportional if lineWidth changes.
    let headSweep = (lineWidth * 2.1) / radius

    // Stop the arc where the head's base begins, so the two don't overlap and
    // fatten the joint.
    context.addArc(center: center, radius: radius,
                   startAngle: start, endAngle: end, clockwise: false)
    context.strokePath()

    let halfWidth = lineWidth * 0.9
    func point(angle: Double, radius r: Double) -> CGPoint {
        CGPoint(x: center.x + cos(angle) * r, y: center.y + sin(angle) * r)
    }

    context.move(to: point(angle: end, radius: radius - halfWidth))
    context.addLine(to: point(angle: end, radius: radius + halfWidth))
    context.addLine(to: point(angle: end + headSweep, radius: radius))
    context.closePath()
    context.fillPath()
}

// Two 120° arms plus ~35° of arrowhead, leaving ~25° gaps — enough gap to stay legible when scaled down.
arm(startDegrees: 25, sweepDegrees: 120)
arm(startDegrees: 205, sweepDegrees: 120)

// MARK: - Write

guard let image = context.makeImage() else {
    FileHandle.standardError.write(Data("could not render image\n".utf8))
    exit(1)
}
let url = URL(fileURLWithPath: outputPath)
guard let destination = CGImageDestinationCreateWithURL(
    url as CFURL, UTType.png.identifier as CFString, 1, nil
) else {
    FileHandle.standardError.write(Data("could not open \(outputPath)\n".utf8))
    exit(1)
}
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else {
    FileHandle.standardError.write(Data("could not write \(outputPath)\n".utf8))
    exit(1)
}
print("wrote \(outputPath)")

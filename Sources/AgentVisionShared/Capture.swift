import Foundation
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers
import ScreenCaptureKit

public enum CaptureError: Error, CustomStringConvertible {
    case captureFailedNoImage
    case cannotCreateDestination(String)
    case writeFailed(String)
    case noDisplayFound

    public var description: String {
        switch self {
        case .captureFailedNoImage:
            return "Screen capture failed — no image returned. Check Screen Recording permission."
        case .cannotCreateDestination(let path):
            return "Cannot create image file at \(path)"
        case .writeFailed(let path):
            return "Failed to write image to \(path)"
        case .noDisplayFound:
            return "No display found for capture area."
        }
    }
}

/// Captures a screen region using ScreenCaptureKit. Returns a CGImage at native (Retina) resolution.
public func captureScreenRect(_ rect: CGRect) throws -> CGImage {
    let semaphore = DispatchSemaphore(value: 0)
    nonisolated(unsafe) var capturedImage: CGImage?
    nonisolated(unsafe) var capturedError: Error?

    Task { @Sendable in
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

            // Find the display that contains the capture rect
            guard let display = content.displays.first(where: { display in
                let displayRect = CGRect(x: CGFloat(display.frame.origin.x),
                                         y: CGFloat(display.frame.origin.y),
                                         width: CGFloat(display.width),
                                         height: CGFloat(display.height))
                return displayRect.intersects(rect)
            }) ?? content.displays.first else {
                capturedError = CaptureError.noDisplayFound
                semaphore.signal()
                return
            }

            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()

            // sourceRect is in display-local coordinates
            let displayOrigin = display.frame.origin
            config.sourceRect = CGRect(
                x: rect.origin.x - displayOrigin.x,
                y: rect.origin.y - displayOrigin.y,
                width: rect.width,
                height: rect.height
            )

            // Output at native Retina resolution
            let scaleFactor = max(Int(display.frame.width) > 0 ? CGFloat(display.width) / display.frame.width : 2.0, 1.0)
            config.width = Int(rect.width * scaleFactor)
            config.height = Int(rect.height * scaleFactor)
            config.scalesToFit = false
            config.showsCursor = false
            config.capturesShadowsOnly = false

            capturedImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        } catch {
            capturedError = error
        }
        semaphore.signal()
    }

    semaphore.wait()

    if let error = capturedError {
        throw error
    }
    guard let image = capturedImage else {
        throw CaptureError.captureFailedNoImage
    }
    return image
}

public enum ScreenCapture {
    public static func capture(area: CaptureArea, to outputURL: URL) throws {
        let rect = CGRect(x: area.x, y: area.y, width: area.width, height: area.height)
        let image = try captureScreenRect(rect)
        try saveImage(image, to: outputURL)
    }

    /// Capture with four crosshair markers at known positions for coordinate calibration.
    /// Crosshairs are labeled with area-relative screen-point coordinates (matching `control click --at`).
    public static func captureWithCalibration(area: CaptureArea, to outputURL: URL) throws {
        let rect = CGRect(x: area.x, y: area.y, width: area.width, height: area.height)
        let image = try captureScreenRect(rect)

        let pw = image.width   // pixel width (e.g. 1600 on Retina)
        let ph = image.height
        let scaleX = CGFloat(pw) / CGFloat(area.width)   // typically 2.0 on Retina
        let scaleY = CGFloat(ph) / CGFloat(area.height)

        guard let ctx = createContext(width: pw, height: ph) else {
            throw CaptureError.cannotCreateDestination(outputURL.path)
        }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: pw, height: ph))

        // Four crosshairs at 25%/75% of area dimensions (in screen points)
        let areaW = Int(area.width)
        let areaH = Int(area.height)
        let positions: [(Int, Int)] = [
            (areaW / 4,     areaH / 4),
            (areaW * 3 / 4, areaH / 4),
            (areaW / 4,     areaH * 3 / 4),
            (areaW * 3 / 4, areaH * 3 / 4),
        ]

        let armLength: CGFloat = 14 * scaleX
        let color = CGColor(red: 1, green: 0.15, blue: 0.3, alpha: 0.9)
        let fontSize: CGFloat = 11 * scaleX
        let font = CTFontCreateWithName("Menlo-Bold" as CFString, fontSize, nil)

        for (ptX, ptY) in positions {
            // Convert screen points to pixel coordinates
            let cx = CGFloat(ptX) * scaleX
            let cy = CGFloat(ph) - CGFloat(ptY) * scaleY  // flip Y

            drawCrosshair(in: ctx, at: (cx, cy), armLength: armLength, dotRadius: 3 * scaleX, color: color, lineWidth: 2 * scaleX)

            // Coordinate label (shows screen-point coords, not pixel coords)
            let label = "(\(ptX),\(ptY))" as CFString
            let attrs = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: color] as CFDictionary
            let attrStr = CFAttributedStringCreate(nil, label, attrs)!
            let line = CTLineCreateWithAttributedString(attrStr)
            let textBounds = CTLineGetBoundsWithOptions(line, [])

            let labelX: CGFloat = ptX > areaW / 2
                ? cx - armLength - textBounds.width - 4 * scaleX
                : cx + armLength + 4 * scaleX
            let labelY = cy - textBounds.height / 2

            ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.65))
            ctx.fill(CGRect(x: labelX - 3 * scaleX, y: labelY - 2 * scaleY,
                            width: textBounds.width + 6 * scaleX, height: textBounds.height + 4 * scaleY))

            ctx.saveGState()
            ctx.textPosition = CGPoint(x: labelX, y: labelY)
            CTLineDraw(line, ctx)
            ctx.restoreGState()
        }

        guard let result = ctx.makeImage() else {
            throw CaptureError.writeFailed(outputURL.path)
        }
        try saveImage(result, to: outputURL)
    }

    /// Capture with a small marker dot at the target position for click verification.
    /// Input coordinates are in screen points (area-relative), same as `control click --at`.
    public static func captureWithPreview(area: CaptureArea, at point: (x: Int, y: Int), to outputURL: URL) throws {
        let rect = CGRect(x: area.x, y: area.y, width: area.width, height: area.height)
        let image = try captureScreenRect(rect)

        let pw = image.width
        let ph = image.height
        let scaleX = CGFloat(pw) / CGFloat(area.width)
        let scaleY = CGFloat(ph) / CGFloat(area.height)

        guard let ctx = createContext(width: pw, height: ph) else {
            throw CaptureError.cannotCreateDestination(outputURL.path)
        }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: pw, height: ph))

        let cx = CGFloat(point.x) * scaleX
        let cy = CGFloat(ph) - CGFloat(point.y) * scaleY

        // Small dot with black outline for contrast on any background
        let green = CGColor(red: 0, green: 1, blue: 0.3, alpha: 1.0)
        let black = CGColor(red: 0, green: 0, blue: 0, alpha: 0.8)
        let r: CGFloat = 5 * scaleX

        ctx.setFillColor(black)
        ctx.fillEllipse(in: CGRect(x: cx - r - 1.5, y: cy - r - 1.5,
                                   width: (r + 1.5) * 2, height: (r + 1.5) * 2))
        ctx.setFillColor(green)
        ctx.fillEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))

        // Coordinate label offset from dot so it never overlaps
        let fontSize: CGFloat = 10 * scaleX
        let font = CTFontCreateWithName("Menlo-Bold" as CFString, fontSize, nil)
        let label = "(\(point.x),\(point.y))" as CFString
        let attrs = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: green] as CFDictionary
        let attrStr = CFAttributedStringCreate(nil, label, attrs)!
        let line = CTLineCreateWithAttributedString(attrStr)
        let tb = CTLineGetBoundsWithOptions(line, [])
        let gap: CGFloat = 10 * scaleX

        var lx = cx + gap
        var ly = cy - gap - tb.height
        if lx + tb.width + 6 * scaleX > CGFloat(pw) { lx = cx - gap - tb.width }
        if ly - 4 * scaleY < 0 { ly = cy + gap }

        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.75))
        ctx.fill(CGRect(x: lx - 3 * scaleX, y: ly - 2 * scaleY,
                         width: tb.width + 6 * scaleX, height: tb.height + 4 * scaleY))
        ctx.saveGState()
        ctx.textPosition = CGPoint(x: lx, y: ly)
        CTLineDraw(line, ctx)
        ctx.restoreGState()

        guard let result = ctx.makeImage() else {
            throw CaptureError.writeFailed(outputURL.path)
        }
        try saveImage(result, to: outputURL)
    }

    /// Capture with numbered badges overlaid on discovered elements.
    public static func captureWithElements(area: CaptureArea, elements: [DiscoveredElement], to outputURL: URL) throws {
        let rect = CGRect(x: area.x, y: area.y, width: area.width, height: area.height)
        let image = try captureScreenRect(rect)

        let pw = image.width
        let ph = image.height
        let scaleX = CGFloat(pw) / CGFloat(area.width)
        let scaleY = CGFloat(ph) / CGFloat(area.height)

        guard let ctx = createContext(width: pw, height: ph) else {
            throw CaptureError.cannotCreateDestination(outputURL.path)
        }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: pw, height: ph))

        let badgeSize: CGFloat = 20 * scaleX
        let fontSize: CGFloat = 11 * scaleX
        let font = CTFontCreateWithName("Menlo-Bold" as CFString, fontSize, nil)

        // Track badge positions for collision avoidance
        var placedBadges: [CGRect] = []

        for element in elements {
            let blue = CGColor(red: 0.2, green: 0.5, blue: 1.0, alpha: 1.0)
            let orange = CGColor(red: 1.0, green: 0.6, blue: 0.2, alpha: 1.0)
            let badgeColor = element.source == .accessibility ? blue : orange

            // Element bounds in pixel coords
            let bx = CGFloat(element.bounds.x) * scaleX
            let by = CGFloat(ph) - CGFloat(element.bounds.y + element.bounds.height) * scaleY
            let bw = CGFloat(element.bounds.width) * scaleX
            let bh = CGFloat(element.bounds.height) * scaleY

            // Draw element bounds outline
            ctx.setStrokeColor(badgeColor.copy(alpha: 0.4)!)
            ctx.setLineWidth(1.5 * scaleX)
            ctx.stroke(CGRect(x: bx, y: by, width: bw, height: bh))

            // Badge position: top-left of element, with collision avoidance
            let badgeX = bx
            let badgeY = by + bh - badgeSize // top-left in flipped coords

            // Simple collision avoidance: shift right, then down
            var finalRect = CGRect(x: badgeX, y: badgeY, width: badgeSize, height: badgeSize)
            for placed in placedBadges {
                if finalRect.intersects(placed) {
                    finalRect.origin.x = placed.maxX + 2 * scaleX
                    if finalRect.maxX > CGFloat(pw) {
                        finalRect.origin.x = bx
                        finalRect.origin.y -= badgeSize + 2 * scaleX
                    }
                }
            }
            placedBadges.append(finalRect)

            // Draw badge background
            let badgePath = CGPath(roundedRect: finalRect, cornerWidth: 4 * scaleX, cornerHeight: 4 * scaleX, transform: nil)
            ctx.setFillColor(badgeColor)
            ctx.addPath(badgePath)
            ctx.fillPath()

            // Draw badge number
            let numberStr = "\(element.index)" as CFString
            let attrs = [kCTFontAttributeName: font,
                         kCTForegroundColorAttributeName: CGColor(red: 1, green: 1, blue: 1, alpha: 1)] as CFDictionary
            let attrStr = CFAttributedStringCreate(nil, numberStr, attrs)!
            let line = CTLineCreateWithAttributedString(attrStr)
            let textBounds = CTLineGetBoundsWithOptions(line, [])

            ctx.saveGState()
            ctx.textPosition = CGPoint(
                x: finalRect.midX - textBounds.width / 2,
                y: finalRect.midY - textBounds.height / 2
            )
            CTLineDraw(line, ctx)
            ctx.restoreGState()
        }

        guard let result = ctx.makeImage() else {
            throw CaptureError.writeFailed(outputURL.path)
        }
        try saveImage(result, to: outputURL)
    }

    public static func captureToTemp(area: CaptureArea) throws -> String {
        let filename = "agent-vision-capture-\(Int(Date().timeIntervalSince1970)).png"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try capture(area: area, to: url)
        return url.path
    }

    // MARK: - Helpers

    private static func createContext(width: Int, height: Int) -> CGContext? {
        CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }

    private static func drawCrosshair(in ctx: CGContext, at center: (x: CGFloat, y: CGFloat),
                                       armLength: CGFloat, dotRadius: CGFloat, color: CGColor, lineWidth: CGFloat) {
        let (cx, cy) = center
        ctx.setStrokeColor(color)
        ctx.setLineWidth(lineWidth)
        ctx.move(to: CGPoint(x: cx - armLength, y: cy))
        ctx.addLine(to: CGPoint(x: cx + armLength, y: cy))
        ctx.move(to: CGPoint(x: cx, y: cy - armLength))
        ctx.addLine(to: CGPoint(x: cx, y: cy + armLength))
        ctx.strokePath()

        ctx.setFillColor(color)
        ctx.fillEllipse(in: CGRect(x: cx - dotRadius, y: cy - dotRadius, width: dotRadius * 2, height: dotRadius * 2))
    }

    private static func saveImage(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil
        ) else {
            throw CaptureError.cannotCreateDestination(url.path)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw CaptureError.writeFailed(url.path)
        }
    }
}

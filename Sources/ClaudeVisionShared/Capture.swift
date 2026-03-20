import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

public enum CaptureError: Error, CustomStringConvertible {
    case captureFailedNoImage
    case cannotCreateDestination(String)
    case writeFailed(String)

    public var description: String {
        switch self {
        case .captureFailedNoImage:
            return "Screen capture failed — no image returned. Check Screen Recording permission."
        case .cannotCreateDestination(let path):
            return "Cannot create image file at \(path)"
        case .writeFailed(let path):
            return "Failed to write image to \(path)"
        }
    }
}

public enum ScreenCapture {
    public static func capture(area: CaptureArea, to outputURL: URL) throws {
        let rect = CGRect(x: area.x, y: area.y, width: area.width, height: area.height)

        guard let image = CGWindowListCreateImage(
            rect,
            .optionOnScreenOnly,
            kCGNullWindowID,
            .bestResolution
        ) else {
            throw CaptureError.captureFailedNoImage
        }

        guard let destination = CGImageDestinationCreateWithURL(
            outputURL as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw CaptureError.cannotCreateDestination(outputURL.path)
        }

        CGImageDestinationAddImage(destination, image, nil)

        guard CGImageDestinationFinalize(destination) else {
            throw CaptureError.writeFailed(outputURL.path)
        }
    }

    public static func captureToTemp(area: CaptureArea) throws -> String {
        let filename = "claude-vision-capture-\(Int(Date().timeIntervalSince1970)).png"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try capture(area: area, to: url)
        return url.path
    }
}

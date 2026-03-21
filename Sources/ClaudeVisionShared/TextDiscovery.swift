import Foundation
import CoreGraphics
import Vision

public enum TextDiscovery {

    public struct ConvertedBounds: Sendable {
        public let center: Point
        public let bounds: ElementBounds
    }

    /// Convert Vision normalized coordinates (0-1, bottom-left origin) to area-relative screen points.
    public static func convertVisionBounds(
        midX: Double, midY: Double,
        x: Double, y: Double, width: Double, height: Double,
        areaWidth: Double, areaHeight: Double, scaleFactor: Double
    ) -> ConvertedBounds {
        let centerX = (midX * areaWidth) / scaleFactor
        let centerY = (areaHeight - midY * areaHeight) / scaleFactor
        let boundsX = (x * areaWidth) / scaleFactor
        let boundsY = (areaHeight - (y + height) * areaHeight) / scaleFactor
        let boundsW = (width * areaWidth) / scaleFactor
        let boundsH = (height * areaHeight) / scaleFactor

        return ConvertedBounds(
            center: Point(x: centerX, y: centerY),
            bounds: ElementBounds(x: boundsX, y: boundsY, width: boundsW, height: boundsH)
        )
    }

    /// Check if an OCR text result should be deduplicated against existing AX elements.
    public static func shouldDeduplicate(ocrText: String, ocrBounds: ElementBounds,
                                          against axElements: [DiscoveredElement]) -> Bool {
        let ocrLower = ocrText.lowercased()
        for ax in axElements {
            guard let axLabel = ax.label?.lowercased(), axLabel.contains(ocrLower) else { continue }
            let overlap = ocrBounds.intersectionArea(with: ax.bounds)
            if ocrBounds.area > 0 && overlap / ocrBounds.area > 0.5 {
                return true
            }
        }
        return false
    }

    /// Run OCR on a captured image and return discovered text elements.
    public static func discover(image: CGImage, areaWidth: Double, areaHeight: Double,
                                 existingElements: [DiscoveredElement], startIndex: Int) -> [DiscoveredElement] {
        let scaleFactor = Double(image.width) / areaWidth
        let imageWidth = Double(image.width)
        let imageHeight = Double(image.height)

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return []
        }

        guard let observations = request.results else { return [] }

        var results: [DiscoveredElement] = []
        var currentIndex = startIndex

        for observation in observations {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let text = candidate.string
            let box = observation.boundingBox

            let converted = convertVisionBounds(
                midX: box.midX, midY: box.midY,
                x: box.origin.x, y: box.origin.y, width: box.width, height: box.height,
                areaWidth: imageWidth, areaHeight: imageHeight, scaleFactor: scaleFactor
            )

            if shouldDeduplicate(ocrText: text, ocrBounds: converted.bounds, against: existingElements) {
                continue
            }

            results.append(DiscoveredElement(
                index: currentIndex,
                source: .ocr,
                role: .staticText,
                label: text,
                center: converted.center,
                bounds: converted.bounds
            ))
            currentIndex += 1
        }

        return results
    }
}

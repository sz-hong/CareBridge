import Foundation
import UIKit
import Vision

struct PrivacyFinding: Codable {
    var type: String
    var confidence: Float
}

struct RedactedImage {
    var data: Data
    var mimeType: String
    var localFindings: [PrivacyFinding]
}

protocol PrivacyRedactionServicing {
    func redactImageForUpload(_ image: UIImage) async throws -> RedactedImage
    func stripMetadata(from data: Data, mimeType: String) throws -> Data
}

struct DefaultPrivacyRedactionService: PrivacyRedactionServicing {
    func redactImageForUpload(_ image: UIImage) async throws -> RedactedImage {
        let normalized = image.normalizedUp()
        guard let cgImage = normalized.cgImage else { throw APIError.emptyResponse }

        let detections = try await detectPrivacyRegions(in: cgImage)
        let redacted = drawRedactions(on: normalized, boxes: detections.boxes)
        guard let data = redacted.jpegData(compressionQuality: 0.85) else {
            throw APIError.emptyResponse
        }
        return RedactedImage(
            data: data,
            mimeType: "image/jpeg",
            localFindings: detections.findings
        )
    }

    func stripMetadata(from data: Data, mimeType: String) throws -> Data {
        guard mimeType.starts(with: "image/"), let image = UIImage(data: data) else {
            return data
        }
        if mimeType == "image/png", let png = image.pngData() {
            return png
        }
        return image.jpegData(compressionQuality: 0.9) ?? data
    }

    private func detectPrivacyRegions(in cgImage: CGImage) async throws -> (boxes: [CGRect], findings: [PrivacyFinding]) {
        let faceRequest = VNDetectFaceRectanglesRequest()
        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .accurate
        textRequest.usesLanguageCorrection = false

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([faceRequest, textRequest])

        var boxes: [CGRect] = []
        var findings: [PrivacyFinding] = []

        for observation in faceRequest.results ?? [] {
            boxes.append(observation.boundingBox)
            findings.append(PrivacyFinding(type: "FACE", confidence: observation.confidence))
        }

        for observation in textRequest.results ?? [] {
            guard let candidate = observation.topCandidates(1).first,
                  Self.containsSensitiveText(candidate.string) else { continue }
            boxes.append(observation.boundingBox)
            findings.append(PrivacyFinding(type: "TEXT_PII", confidence: observation.confidence))
        }

        return (boxes, findings)
    }

    private func drawRedactions(on image: UIImage, boxes: [CGRect]) -> UIImage {
        guard !boxes.isEmpty else { return image }
        let renderer = UIGraphicsImageRenderer(size: image.size)
        return renderer.image { context in
            image.draw(in: CGRect(origin: .zero, size: image.size))
            UIColor.black.setFill()
            for box in boxes {
                let rect = CGRect(
                    x: box.minX * image.size.width,
                    y: (1 - box.maxY) * image.size.height,
                    width: box.width * image.size.width,
                    height: box.height * image.size.height
                ).insetBy(dx: -4, dy: -4)
                context.cgContext.fill(rect)
            }
        }
    }

    private static func containsSensitiveText(_ text: String) -> Bool {
        let patterns = [
            #"\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b"#,
            #"(?<!\d)(?:\+?886[-\s]?)?0?9\d{2}[-\s]?\d{3}[-\s]?\d{3}(?!\d)"#,
            #"\b[A-Z][12]\d{8}\b"#,
            #"\b(?:\d[ -]*?){13,19}\b"#,
        ]
        return patterns.contains { pattern in
            text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }
    }
}

private extension UIImage {
    func normalizedUp() -> UIImage {
        guard imageOrientation != .up else { return self }
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

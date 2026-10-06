import Foundation
import UIKit
import Vision

/// Reads the counter value from a photo of a meter.
enum MeterValueRecognizer {
    /// Recognised values, most plausible first.
    static func recognize(imageData: Data, previous: Decimal?) async -> [Decimal] {
        guard let image = UIImage(data: imageData), let cgImage = image.cgImage else { return [] }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        let texts: [String] = await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
            guard (try? handler.perform([request])) != nil else { return [] }
            return (request.results ?? []).flatMap { $0.topCandidates(3).map(\.string) }
        }.value
        return candidates(from: texts, previous: previous)
    }

    /// Extracts counter values from recognised text lines.
    ///
    /// Mechanical counters often show the decimal places in a separate red box, which OCR
    /// reads as one long number ("216128" for 21612,8). With a previous reading the decimal
    /// point is placed so the value lands just above it.
    static func candidates(from texts: [String], previous: Decimal?) -> [Decimal] {
        var values: [Decimal] = []
        for text in texts {
            for token in numberTokens(in: text) {
                values.append(contentsOf: interpretations(of: token, previous: previous))
            }
        }

        var unique: [Decimal] = []
        for value in values where !unique.contains(value) { unique.append(value) }

        guard let previous else {
            // Without history, longer numbers are more likely the counter than labels like "1" or "50 Hz".
            return unique.sorted { digitCount($0) > digitCount($1) }.prefix(5).map { $0 }
        }
        let plausible = unique.filter { $0 >= previous && ($0 - previous) <= max(previous, 1000) }
        let rest = unique.filter { !plausible.contains($0) }.sorted { digitCount($0) > digitCount($1) }
        return (plausible.sorted { $0 - previous < $1 - previous } + rest).prefix(5).map { $0 }
    }

    // MARK: - Private

    /// Digit groups with an optional decimal part; spaces between digits are joined
    /// because OCR often splits the drum digits ("0 2 1 6 1 2").
    private static func numberTokens(in text: String) -> [String] {
        let normalized = text
            .replacingOccurrences(of: "O", with: "0")
            .replacingOccurrences(of: "o", with: "0")
            .replacingOccurrences(of: "l", with: "1")
            .replacingOccurrences(of: "I", with: "1")
        let joined = normalized.replacingOccurrences(of: #"(?<=\d)\s+(?=\d)"#, with: "", options: .regularExpression)
        guard let regex = try? NSRegularExpression(pattern: #"\d+(?:[.,]\d+)?"#) else { return [] }
        let range = NSRange(joined.startIndex..., in: joined)
        return regex.matches(in: joined, range: range).compactMap {
            Range($0.range, in: joined).map { String(joined[$0]) }
        }
    }

    private static func interpretations(of token: String, previous: Decimal?) -> [Decimal] {
        if token.contains(",") || token.contains(".") {
            let value = Decimal(string: token.replacingOccurrences(of: ",", with: "."), locale: Locale(identifier: "en_US_POSIX"))
            return value.map { [$0] } ?? []
        }
        guard token.count >= 3, let whole = Decimal(string: token) else { return [] }
        guard let previous else { return [whole] }
        // Try 0–3 decimal places and keep those that fit the history.
        var result: [Decimal] = []
        var divisor: Decimal = 1
        for _ in 0...3 {
            result.append(whole / divisor)
            divisor *= 10
        }
        let fitting = result.filter { $0 >= previous && ($0 - previous) <= max(previous, 1000) }
        return fitting.isEmpty ? [whole] : fitting
    }

    private static func digitCount(_ value: Decimal) -> Int {
        NSDecimalNumber(decimal: value).stringValue.filter(\.isNumber).count
    }
}

private extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}

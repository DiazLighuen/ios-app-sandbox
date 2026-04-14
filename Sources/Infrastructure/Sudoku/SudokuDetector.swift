import Vision
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

struct SudokuDetector {

    enum DetectionError: LocalizedError {
        case noGridFound
        case ocrFailed

        var errorDescription: String? {
            switch self {
            case .noGridFound: return "No se detectó un tablero de Sudoku en la imagen."
            case .ocrFailed:   return "No se pudieron leer los dígitos del tablero."
            }
        }
    }

    // MARK: - Public

    /// Detects a Sudoku grid in the given image and returns a 9×9 matrix.
    static func detect(in image: UIImage) async throws -> SudokuGrid {
        guard let ciImage = CIImage(image: image) else { throw DetectionError.noGridFound }

        let corrected = try await perspectiveCorrected(ciImage)
        let cells = try await recognizeDigits(in: corrected)
        return SudokuGrid(cells: cells)
    }

    // MARK: - Step 1: Rectangle detection + perspective correction

    private static func perspectiveCorrected(_ image: CIImage) async throws -> CIImage {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNDetectRectanglesRequest { request, error in
                if let error { return continuation.resume(throwing: error) }

                guard let obs = (request.results as? [VNRectangleObservation])?
                    .sorted(by: { $0.confidence > $1.confidence })
                    .first(where: { isSquarish($0) })
                else {
                    return continuation.resume(throwing: DetectionError.noGridFound)
                }

                let corrected = applyPerspective(to: image, observation: obs)
                continuation.resume(returning: corrected)
            }

            request.minimumAspectRatio  = 0.75
            request.maximumAspectRatio  = 1.25
            request.minimumSize         = 0.25
            request.maximumObservations = 1
            request.minimumConfidence   = 0.7

            let handler = VNImageRequestHandler(ciImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private static func isSquarish(_ obs: VNRectangleObservation) -> Bool {
        let w = obs.boundingBox.width
        let h = obs.boundingBox.height
        guard w > 0, h > 0 else { return false }
        let ratio = w / h
        return ratio > 0.75 && ratio < 1.25
    }

    private static func applyPerspective(to image: CIImage, observation obs: VNRectangleObservation) -> CIImage {
        let size = image.extent.size
        // VNRectangleObservation uses normalized coords (0–1, bottom-left origin)
        func point(_ p: CGPoint) -> CGPoint {
            CGPoint(x: p.x * size.width, y: p.y * size.height)
        }

        let filter = CIFilter.perspectiveCorrection()
        filter.inputImage   = image
        filter.topLeft      = point(obs.topLeft)
        filter.topRight     = point(obs.topRight)
        filter.bottomLeft   = point(obs.bottomLeft)
        filter.bottomRight  = point(obs.bottomRight)
        return filter.outputImage ?? image
    }

    // MARK: - Step 2: Crop 81 cells + OCR

    private static func recognizeDigits(in image: CIImage) async throws -> [[Int]] {
        let context = CIContext()
        guard let cgFull = context.createCGImage(image, from: image.extent) else {
            throw DetectionError.ocrFailed
        }

        let size   = image.extent.size
        let cellW  = size.width  / 9
        let cellH  = size.height / 9
        // Small inset to avoid reading grid lines as digits
        let inset  = max(cellW, cellH) * 0.1

        var matrix = Array(repeating: Array(repeating: 0, count: 9), count: 9)

        for row in 0..<9 {
            for col in 0..<9 {
                // CIImage origin is bottom-left; CGImage is top-left → flip row
                let flippedRow = 8 - row
                let rect = CGRect(
                    x: CGFloat(col) * cellW + inset,
                    y: CGFloat(flippedRow) * cellH + inset,
                    width:  cellW - 2 * inset,
                    height: cellH - 2 * inset
                )
                guard let cellCG = cgFull.cropping(to: rect) else { continue }
                let digit = await ocrDigit(cgImage: cellCG)
                matrix[row][col] = digit
            }
        }
        return matrix
    }

    private static func ocrDigit(cgImage: CGImage) async -> Int {
        await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let candidates = (request.results as? [VNRecognizedTextObservation])?
                    .compactMap { $0.topCandidates(1).first?.string.trimmingCharacters(in: .whitespaces) }
                    .first { $0.count == 1 }

                if let str = candidates, let digit = Int(str), (1...9).contains(digit) {
                    continuation.resume(returning: digit)
                } else {
                    continuation.resume(returning: 0)
                }
            }
            request.recognitionLevel     = .accurate
            request.usesLanguageCorrection = false
            request.customWords          = ["1","2","3","4","5","6","7","8","9"]

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([request])
        }
    }
}

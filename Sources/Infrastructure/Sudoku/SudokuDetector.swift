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

    static func detect(in image: UIImage) async throws -> SudokuGrid {
        guard let ciImage = CIImage(image: image) else { throw DetectionError.noGridFound }
        let preprocessed = preprocess(ciImage)
        let corrected = await bestGridRegion(preprocessed)
        let cells = try await recognizeDigits(in: corrected)
        return SudokuGrid(cells: cells)
    }

    // MARK: - Step 0: Preprocess (grayscale + contrast boost)

    private static func preprocess(_ image: CIImage) -> CIImage {
        let mono = image.applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: 0,
            kCIInputContrastKey: 1.2
        ])
        return mono
    }

    // MARK: - Step 1: Find grid region (with fallback to full image)

    /// Tries increasingly relaxed rectangle detection strategies.
    /// Falls back to the full image if nothing is found.
    private static func bestGridRegion(_ image: CIImage) async -> CIImage {
        // Strategy 1: strict square (typical clean screenshot)
        if let obs = await detectRectangle(in: image, minSize: 0.2, minConfidence: 0.4, maxObs: 10),
           isSquarish(obs) {
            return applyPerspective(to: image, observation: obs)
        }

        // Strategy 2: relaxed — any large rectangle, pick biggest area
        if let obs = await detectRectangle(in: image, minSize: 0.1, minConfidence: 0.1, maxObs: 20) {
            return applyPerspective(to: image, observation: obs)
        }

        // Strategy 3: assume the whole image is the grid (crop to largest centered square)
        return centerSquareCrop(image)
    }

    private static func detectRectangle(
        in image: CIImage,
        minSize: Float,
        minConfidence: Float,
        maxObs: Int
    ) async -> VNRectangleObservation? {
        await withCheckedContinuation { continuation in
            let request = VNDetectRectanglesRequest { req, _ in
                // Pick the observation with the largest bounding-box area
                let best = (req.results as? [VNRectangleObservation])?
                    .max(by: { a, b in
                        a.boundingBox.width * a.boundingBox.height <
                        b.boundingBox.width * b.boundingBox.height
                    })
                continuation.resume(returning: best)
            }
            request.minimumAspectRatio  = 0.6
            request.maximumAspectRatio  = 1.4
            request.minimumSize         = minSize
            request.maximumObservations = maxObs
            request.minimumConfidence   = minConfidence

            let handler = VNImageRequestHandler(ciImage: image, options: [:])
            try? handler.perform([request])
        }
    }

    private static func isSquarish(_ obs: VNRectangleObservation) -> Bool {
        let w = obs.boundingBox.width
        let h = obs.boundingBox.height
        guard w > 0, h > 0 else { return false }
        let ratio = w / h
        return ratio > 0.7 && ratio < 1.3
    }

    private static func applyPerspective(to image: CIImage, observation obs: VNRectangleObservation) -> CIImage {
        let size = image.extent.size
        func pt(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * size.width, y: p.y * size.height) }

        let filter = CIFilter.perspectiveCorrection()
        filter.inputImage  = image
        filter.topLeft     = pt(obs.topLeft)
        filter.topRight    = pt(obs.topRight)
        filter.bottomLeft  = pt(obs.bottomLeft)
        filter.bottomRight = pt(obs.bottomRight)
        return filter.outputImage ?? image
    }

    /// Crops the image to the largest centered square (removes letterbox / UI chrome).
    private static func centerSquareCrop(_ image: CIImage) -> CIImage {
        let ext  = image.extent
        let side = min(ext.width, ext.height)
        let x    = ext.minX + (ext.width  - side) / 2
        let y    = ext.minY + (ext.height - side) / 2
        return image.cropped(to: CGRect(x: x, y: y, width: side, height: side))
    }

    // MARK: - Step 2: Crop 81 cells + OCR

    private static func recognizeDigits(in image: CIImage) async throws -> [[Int]] {
        let context = CIContext()
        guard let cgFull = context.createCGImage(image, from: image.extent) else {
            throw DetectionError.ocrFailed
        }

        let size  = image.extent.size
        let cellW = size.width  / 9
        let cellH = size.height / 9
        let inset = max(cellW, cellH) * 0.12

        var matrix = Array(repeating: Array(repeating: 0, count: 9), count: 9)

        for row in 0..<9 {
            for col in 0..<9 {
                let flippedRow = 8 - row   // CIImage: origin bottom-left; CGImage: top-left
                let rect = CGRect(
                    x: CGFloat(col) * cellW + inset,
                    y: CGFloat(flippedRow) * cellH + inset,
                    width:  cellW - 2 * inset,
                    height: cellH - 2 * inset
                )
                guard let cellCG = cgFull.cropping(to: rect) else { continue }
                matrix[row][col] = await ocrDigit(cgImage: cellCG)
            }
        }
        return matrix
    }

    private static func ocrDigit(cgImage: CGImage) async -> Int {
        await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { req, _ in
                // Accept single-char candidates that are digits 1-9
                let hit = (req.results as? [VNRecognizedTextObservation])?
                    .compactMap { $0.topCandidates(2).map(\.string) }
                    .flatMap { $0 }
                    .compactMap { s -> Int? in
                        let t = s.trimmingCharacters(in: .whitespaces)
                        guard t.count == 1, let d = Int(t), (1...9).contains(d) else { return nil }
                        return d
                    }
                    .first

                continuation.resume(returning: hit ?? 0)
            }
            request.recognitionLevel       = .accurate
            request.usesLanguageCorrection = false
            request.customWords            = ["1","2","3","4","5","6","7","8","9"]

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([request])
        }
    }
}

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
        let corrected    = await bestGridRegion(preprocessed)

        let context = CIContext()
        guard let cgGrid = context.createCGImage(corrected, from: corrected.extent) else {
            throw DetectionError.ocrFailed
        }

        let cells = await recognizeDigits(cgImage: cgGrid)
        return SudokuGrid(cells: cells)
    }

    // MARK: - Step 0: Preprocess

    private static func preprocess(_ image: CIImage) -> CIImage {
        image.applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: 0,
            kCIInputContrastKey: 1.3
        ])
    }

    // MARK: - Step 1: Find grid region

    private static func bestGridRegion(_ image: CIImage) async -> CIImage {
        if let obs = await detectRectangle(in: image, minSize: 0.2, minConfidence: 0.4, maxObs: 10),
           isSquarish(obs) {
            return applyPerspective(to: image, observation: obs)
        }
        if let obs = await detectRectangle(in: image, minSize: 0.1, minConfidence: 0.1, maxObs: 20) {
            return applyPerspective(to: image, observation: obs)
        }
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
                let best = (req.results as? [VNRectangleObservation])?
                    .max { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height }
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
        let r = obs.boundingBox.width / max(obs.boundingBox.height, 0.001)
        return r > 0.7 && r < 1.3
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

    private static func centerSquareCrop(_ image: CIImage) -> CIImage {
        let ext  = image.extent
        let side = min(ext.width, ext.height)
        let x    = ext.minX + (ext.width  - side) / 2
        let y    = ext.minY + (ext.height - side) / 2
        return image.cropped(to: CGRect(x: x, y: y, width: side, height: side))
    }

    // MARK: - Step 2: Digit recognition

    /// Runs full-grid OCR first (faster, better for printed grids).
    /// Falls back to upscaled cell-by-cell if full-grid yields too few digits.
    private static func recognizeDigits(cgImage: CGImage) async -> [[Int]] {
        let matrix = await fullGridOCR(cgImage: cgImage)
        let found  = matrix.flatMap { $0 }.filter { $0 != 0 }.count
        if found >= 5 { return matrix }
        return await cellByCellOCR(cgImage: cgImage)
    }

    // MARK: Full-grid OCR

    /// One VNRecognizeTextRequest on the whole grid. Maps each digit
    /// to a cell using the observation's bounding box.
    /// VNRecognizedTextObservation.boundingBox: normalized, origin bottom-left.
    private static func fullGridOCR(cgImage: CGImage) async -> [[Int]] {
        var matrix = Array(repeating: Array(repeating: 0, count: 9), count: 9)
        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { req, _ in
                guard let observations = req.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: matrix)
                    return
                }
                for obs in observations {
                    let digits = extractDigits(from: obs)
                    for (digit, bbox) in digits {
                        // bbox origin is bottom-left normalized → flip Y for top-down row
                        let col = min(Int(bbox.midX * 9), 8)
                        let row = min(Int((1 - bbox.midY) * 9), 8)
                        guard (0..<9).contains(row), (0..<9).contains(col) else { continue }
                        matrix[row][col] = digit
                    }
                }
                continuation.resume(returning: matrix)
            }
            request.recognitionLevel       = .accurate
            request.usesLanguageCorrection = false
            request.customWords            = ["1","2","3","4","5","6","7","8","9"]
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([request])
        }
    }

    /// Extract (digit, normalizedBoundingBox) pairs from a text observation.
    /// Handles both single-char ("5") and multi-char ("1 2 3") observations.
    private static func extractDigits(from obs: VNRecognizedTextObservation) -> [(Int, CGRect)] {
        var results: [(Int, CGRect)] = []
        for candidate in obs.topCandidates(2) {
            let str = candidate.string
            // Single digit — use the observation bbox directly
            if str.count == 1, let d = Int(str), (1...9).contains(d) {
                results.append((d, obs.boundingBox))
                break
            }
            // Multiple chars: try to get per-character range bboxes
            for (i, char) in str.enumerated() {
                guard let d = Int(String(char)), (1...9).contains(d) else { continue }
                if let range = Range(NSRange(location: i, length: 1), in: str),
                   let charBox = try? candidate.boundingBox(for: range)?.boundingBox {
                    results.append((d, charBox))
                }
            }
            if !results.isEmpty { break }
        }
        return results
    }

    // MARK: Cell-by-cell OCR (fallback)

    /// Divides the grid CGImage into 81 cells, scales each up to ~150px,
    /// and runs OCR individually.
    private static func cellByCellOCR(cgImage: CGImage) async -> [[Int]] {
        let w     = CGFloat(cgImage.width)
        let h     = CGFloat(cgImage.height)
        let cellW = w / 9
        let cellH = h / 9
        let inset = max(cellW, cellH) * 0.08   // tighter inset when upscaling

        var matrix = Array(repeating: Array(repeating: 0, count: 9), count: 9)
        for row in 0..<9 {
            for col in 0..<9 {
                // CGImage origin is top-left → row 0 at y=0 (no flip needed)
                let rect = CGRect(
                    x: CGFloat(col) * cellW + inset,
                    y: CGFloat(row) * cellH + inset,
                    width:  cellW - 2 * inset,
                    height: cellH - 2 * inset
                )
                guard let cell = cgImage.cropping(to: rect),
                      let scaled = upscale(cell, to: 150) else { continue }
                matrix[row][col] = await ocrSingleCell(cgImage: scaled)
            }
        }
        return matrix
    }

    private static func upscale(_ source: CGImage, to size: Int) -> CGImage? {
        let s = CGSize(width: size, height: size)
        return UIGraphicsImageRenderer(size: s).image { _ in
            UIImage(cgImage: source).draw(in: CGRect(origin: .zero, size: s))
        }.cgImage
    }

    private static func ocrSingleCell(cgImage: CGImage) async -> Int {
        await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { req, _ in
                let digit = (req.results as? [VNRecognizedTextObservation])?
                    .compactMap { obs -> Int? in
                        for candidate in obs.topCandidates(3) {
                            let t = candidate.string.trimmingCharacters(in: .whitespaces)
                            if t.count == 1, let d = Int(t), (1...9).contains(d) { return d }
                        }
                        return nil
                    }
                    .first ?? 0
                continuation.resume(returning: digit)
            }
            request.recognitionLevel       = .accurate
            request.usesLanguageCorrection = false
            request.customWords            = ["1","2","3","4","5","6","7","8","9"]
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([request])
        }
    }
}

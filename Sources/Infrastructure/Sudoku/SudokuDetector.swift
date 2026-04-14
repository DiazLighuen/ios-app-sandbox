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

        let context   = CIContext()
        guard let cgImage = context.createCGImage(preprocessed, from: preprocessed.extent) else {
            throw DetectionError.noGridFound
        }

        // Find grid bounds in the original image (normalized, Vision bottom-left origin)
        let gridBounds = await findGridBounds(in: preprocessed)

        // Strategy 1: OCR on the full original image — best quality, uses grid bounds to map cells
        let matrixFull = await fullImageOCR(cgImage: cgImage, gridBounds: gridBounds)
        if matrixFull.flatMap({ $0 }).filter({ $0 != 0 }).count >= 5 {
            return SudokuGrid(cells: matrixFull)
        }

        // Strategy 2: Extract and upscale each cell from the original image
        let matrixCell = await cellByCellOCR(cgImage: cgImage, gridBounds: gridBounds)
        return SudokuGrid(cells: matrixCell)
    }

    // MARK: - Preprocess

    private static func preprocess(_ image: CIImage) -> CIImage {
        image.applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: 0,
            kCIInputContrastKey: 1.3
        ])
    }

    // MARK: - Grid detection

    /// Returns the grid bounding box in Vision normalized coords (origin bottom-left).
    /// Falls back to a centered 90% crop if nothing is detected.
    private static func findGridBounds(in image: CIImage) async -> CGRect {
        if let obs = await detectRectangle(in: image, minSize: 0.1, minConfidence: 0.1, maxObs: 20) {
            return obs.boundingBox
        }
        return CGRect(x: 0.05, y: 0.05, width: 0.9, height: 0.9)
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

    // MARK: - Strategy 1: Full-image OCR + grid bounds mapping

    /// Runs OCR on the full-resolution CGImage.
    /// Each detected digit is mapped to a cell using its position relative to gridBounds.
    /// gridBounds uses Vision normalized coords: origin bottom-left, Y increases upward.
    private static func fullImageOCR(cgImage: CGImage, gridBounds: CGRect) async -> [[Int]] {
        await withCheckedContinuation { (continuation: CheckedContinuation<[[Int]], Never>) in
            var matrix = Array(repeating: Array(repeating: 0, count: 9), count: 9)
            let request = VNRecognizeTextRequest { req, _ in
                if let observations = req.results as? [VNRecognizedTextObservation] {
                    for obs in observations {
                        for (digit, bbox) in extractDigits(from: obs) {
                            guard gridBounds.contains(CGPoint(x: bbox.midX, y: bbox.midY)) else { continue }
                            let relX = (bbox.midX - gridBounds.minX) / gridBounds.width
                            let relY = (bbox.midY - gridBounds.minY) / gridBounds.height
                            let col  = max(0, min(Int(relX * 9), 8))
                            let row  = max(0, min(8 - Int(relY * 9), 8))
                            matrix[row][col] = digit
                        }
                    }
                }
                continuation.resume(returning: matrix)
            }
            request.recognitionLevel       = .accurate
            request.usesLanguageCorrection = false
            request.customWords            = ["1","2","3","4","5","6","7","8","9"]
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: matrix)
            }
        }
    }

    // MARK: - Strategy 2: Cell-by-cell on original image, upscaled

    /// Extracts each of the 81 cells directly from the original CGImage using gridBounds,
    /// scales each cell to 200×200 px, then runs per-cell OCR.
    private static func cellByCellOCR(cgImage: CGImage, gridBounds: CGRect) async -> [[Int]] {
        let imgW = CGFloat(cgImage.width)
        let imgH = CGFloat(cgImage.height)

        // Convert gridBounds (Vision normalized, bottom-left) → CGImage coords (top-left)
        let gx = gridBounds.minX * imgW
        let gy = (1 - gridBounds.maxY) * imgH   // flip Y for CGImage top-left origin
        let gw = gridBounds.width  * imgW
        let gh = gridBounds.height * imgH

        let cellW = gw / 9
        let cellH = gh / 9
        let inset = min(cellW, cellH) * 0.08

        var matrix = Array(repeating: Array(repeating: 0, count: 9), count: 9)
        for row in 0..<9 {
            for col in 0..<9 {
                let rect = CGRect(
                    x: gx + CGFloat(col) * cellW + inset,
                    y: gy + CGFloat(row) * cellH + inset,
                    width:  cellW - 2 * inset,
                    height: cellH - 2 * inset
                )
                guard let cell   = cgImage.cropping(to: rect),
                      let scaled = upscale(cell, to: 200) else { continue }
                matrix[row][col] = await ocrSingleCell(cgImage: scaled)
            }
        }
        return matrix
    }

    private static func upscale(_ source: CGImage, to size: Int) -> CGImage? {
        let s = CGSize(width: size, height: size)
        return UIGraphicsImageRenderer(size: s).image { ctx in
            // White background then draw cell (helps with dark-background Sudoku apps)
            ctx.cgContext.setFillColor(UIColor.white.cgColor)
            ctx.cgContext.fill(CGRect(origin: .zero, size: s))
            UIImage(cgImage: source).draw(in: CGRect(origin: .zero, size: s))
        }.cgImage
    }

    private static func ocrSingleCell(cgImage: CGImage) async -> Int {
        await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { req, _ in
                let digit = (req.results as? [VNRecognizedTextObservation])?
                    .compactMap { obs -> Int? in
                        for c in obs.topCandidates(3) {
                            let t = c.string.trimmingCharacters(in: .whitespaces)
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

    // MARK: - Digit extraction helpers

    /// Extracts (digit, boundingBox) pairs from a VNRecognizedTextObservation.
    /// Handles both single-char ("5") and multi-char ("1 2") observations.
    private static func extractDigits(from obs: VNRecognizedTextObservation) -> [(Int, CGRect)] {
        for candidate in obs.topCandidates(2) {
            let str = candidate.string
            var results: [(Int, CGRect)] = []

            if str.count == 1, let d = Int(str), (1...9).contains(d) {
                return [(d, obs.boundingBox)]
            }
            for (i, ch) in str.enumerated() {
                guard let d = Int(String(ch)), (1...9).contains(d) else { continue }
                if let range = Range(NSRange(location: i, length: 1), in: str),
                   let box   = try? candidate.boundingBox(for: range)?.boundingBox {
                    results.append((d, box))
                }
            }
            if !results.isEmpty { return results }
        }
        return []
    }
}

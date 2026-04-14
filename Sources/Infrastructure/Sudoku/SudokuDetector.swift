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
        // Ensure orientation is .up so all downstream CGImage operations are correct
        let img = image.normalizedOrientation
        guard let cgImage = img.cgImage else { throw DetectionError.noGridFound }

        // Detect grid bounds in the image (normalized Vision coords, origin bottom-left)
        let gridBounds = await findGridBounds(cgImage: cgImage)

        // Strategy 1: row-by-row OCR — most reliable for isolated digits in a grid
        let rowMatrix = await rowByRowOCR(cgImage: cgImage, gridBounds: gridBounds)
        if rowMatrix.flatMap({ $0 }).filter({ $0 != 0 }).count >= 5 {
            return SudokuGrid(cells: rowMatrix)
        }

        // Strategy 2: cell-by-cell with aggressive upscaling
        let cellMatrix = await cellByCellOCR(cgImage: cgImage, gridBounds: gridBounds)
        return SudokuGrid(cells: cellMatrix)
    }

    // MARK: - Grid detection

    private static func findGridBounds(cgImage: CGImage) async -> CGRect {
        let ciImage = CIImage(cgImage: cgImage)
        if let obs = await detectLargestRectangle(in: ciImage) {
            return obs.boundingBox
        }
        return CGRect(x: 0.05, y: 0.05, width: 0.90, height: 0.90)
    }

    private static func detectLargestRectangle(in image: CIImage) async -> VNRectangleObservation? {
        await withCheckedContinuation { (continuation: CheckedContinuation<VNRectangleObservation?, Never>) in
            let request = VNDetectRectanglesRequest { req, _ in
                let best = (req.results as? [VNRectangleObservation])?
                    .max { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height }
                continuation.resume(returning: best)
            }
            request.minimumAspectRatio  = 0.6
            request.maximumAspectRatio  = 1.4
            request.minimumSize         = 0.1
            request.maximumObservations = 20
            request.minimumConfidence   = 0.1
            let handler = VNImageRequestHandler(ciImage: image, options: [:])
            do    { try handler.perform([request]) }
            catch { continuation.resume(returning: nil) }
        }
    }

    // MARK: - Strategy 1: Row-by-row OCR

    /// Extracts 9 horizontal strips (one per Sudoku row), pads & upscales them,
    /// then runs .fast OCR. Maps each digit's X position to a column.
    private static func rowByRowOCR(cgImage: CGImage, gridBounds: CGRect) async -> [[Int]] {
        let imgW  = CGFloat(cgImage.width)
        let imgH  = CGFloat(cgImage.height)

        // Convert gridBounds (Vision normalized, bottom-left) → CGImage coords (top-left)
        let gx = gridBounds.minX * imgW
        let gy = (1.0 - gridBounds.maxY) * imgH
        let gw = gridBounds.width  * imgW
        let gh = gridBounds.height * imgH
        let cellH = gh / 9

        var matrix = Array(repeating: Array(repeating: 0, count: 9), count: 9)

        for row in 0..<9 {
            let stripRect = CGRect(
                x: gx,
                y: gy + CGFloat(row) * cellH,
                width: gw,
                height: cellH
            )
            guard let strip  = cgImage.cropping(to: stripRect),
                  let padded = paddedStrip(strip, targetHeight: 80) else { continue }

            let hits = await ocrStrip(cgImage: padded)
            for (digit, normX) in hits {
                let col = max(0, min(Int(normX * 9), 8))
                if matrix[row][col] == 0 { matrix[row][col] = digit }
            }
        }
        return matrix
    }

    /// Returns (digit, normalizedX) pairs where normalizedX ∈ [0,1] within the strip.
    private static func ocrStrip(cgImage: CGImage) async -> [(Int, CGFloat)] {
        await withCheckedContinuation { (continuation: CheckedContinuation<[(Int, CGFloat)], Never>) in
            var result: [(Int, CGFloat)] = []
            let request = VNRecognizeTextRequest { req, _ in
                if let observations = req.results as? [VNRecognizedTextObservation] {
                    for obs in observations {
                        for (digit, bbox) in extractDigits(from: obs) {
                            result.append((digit, bbox.midX))
                        }
                    }
                }
                continuation.resume(returning: result)
            }
            // .fast avoids complex layout analysis — better for rows of isolated chars
            request.recognitionLevel       = .fast
            request.usesLanguageCorrection = false
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
            do    { try handler.perform([request]) }
            catch { continuation.resume(returning: result) }
        }
    }

    /// Scales the strip to `targetHeight` pixels tall and adds white padding on all sides.
    private static func paddedStrip(_ source: CGImage, targetHeight: CGFloat) -> CGImage? {
        let scale    = targetHeight / CGFloat(source.height)
        let scaledW  = CGFloat(source.width) * scale
        let padding  = targetHeight * 0.25
        let finalSize = CGSize(width: scaledW + 2 * padding, height: targetHeight + 2 * padding)

        return UIGraphicsImageRenderer(size: finalSize).image { ctx in
            ctx.cgContext.setFillColor(UIColor.white.cgColor)
            ctx.cgContext.fill(CGRect(origin: .zero, size: finalSize))
            UIImage(cgImage: source).draw(in: CGRect(x: padding, y: padding,
                                                     width: scaledW, height: targetHeight))
        }.cgImage
    }

    // MARK: - Strategy 2: Cell-by-cell upscaled OCR

    private static func cellByCellOCR(cgImage: CGImage, gridBounds: CGRect) async -> [[Int]] {
        let imgW = CGFloat(cgImage.width)
        let imgH = CGFloat(cgImage.height)
        let gx   = gridBounds.minX * imgW
        let gy   = (1.0 - gridBounds.maxY) * imgH
        let gw   = gridBounds.width  * imgW
        let gh   = gridBounds.height * imgH
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
                      let scaled = upscaledCell(cell, size: 200) else { continue }
                matrix[row][col] = await ocrSingleCell(scaled)
            }
        }
        return matrix
    }

    private static func upscaledCell(_ source: CGImage, size: Int) -> CGImage? {
        let s = CGSize(width: size, height: size)
        return UIGraphicsImageRenderer(size: s).image { ctx in
            ctx.cgContext.setFillColor(UIColor.white.cgColor)
            ctx.cgContext.fill(CGRect(origin: .zero, size: s))
            UIImage(cgImage: source).draw(in: CGRect(origin: .zero, size: s))
        }.cgImage
    }

    private static func ocrSingleCell(_ cgImage: CGImage) async -> Int {
        await withCheckedContinuation { (continuation: CheckedContinuation<Int, Never>) in
            let request = VNRecognizeTextRequest { req, _ in
                let digit = (req.results as? [VNRecognizedTextObservation])?
                    .compactMap { obs -> Int? in
                        for c in obs.topCandidates(3) {
                            let t = c.string.trimmingCharacters(in: .whitespaces)
                            if t.count == 1, let d = Int(t), (1...9).contains(d) { return d }
                        }
                        return nil
                    }.first ?? 0
                continuation.resume(returning: digit)
            }
            request.recognitionLevel       = .accurate
            request.usesLanguageCorrection = false
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
            do    { try handler.perform([request]) }
            catch { continuation.resume(returning: 0) }
        }
    }

    // MARK: - Digit extraction

    private static func extractDigits(from obs: VNRecognizedTextObservation) -> [(Int, CGRect)] {
        for candidate in obs.topCandidates(2) {
            let str = candidate.string
            if str.count == 1, let d = Int(str), (1...9).contains(d) {
                return [(d, obs.boundingBox)]
            }
            var results: [(Int, CGRect)] = []
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

// MARK: - UIImage orientation normalization

private extension UIImage {
    /// Returns a copy drawn upright (orientation == .up).
    var normalizedOrientation: UIImage {
        guard imageOrientation != .up else { return self }
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        defer { UIGraphicsEndImageContext() }
        draw(in: CGRect(origin: .zero, size: size))
        return UIGraphicsGetImageFromCurrentImageContext() ?? self
    }
}

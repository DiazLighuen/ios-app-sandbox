import Vision
import CoreImage
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
        let img = image.normalizedOrientation
        guard let cgImage = img.cgImage else { throw DetectionError.noGridFound }

        let gridBounds = await findGridBounds(cgImage: cgImage)

        // Strategy 1: full-grid accurate OCR — proven to find all digits.
        // Uses Vision bounding boxes to place each digit into the correct cell.
        let s1 = await fullGridOCR(cgImage: cgImage, gridBounds: gridBounds)
        if s1.flatMap({ $0 }).filter({ $0 != 0 }).count >= 10 { return SudokuGrid(cells: s1) }

        // Strategy 2: cell-by-cell (accurate OCR on each 300 px crop).
        // Slower but more robust when the full-image pass misses digits.
        let s2 = await cellByCellOCR(cgImage: cgImage, gridBounds: gridBounds)
        if s2.flatMap({ $0 }).filter({ $0 != 0 }).count >= 1 { return SudokuGrid(cells: s2) }

        throw DetectionError.ocrFailed
    }

    // MARK: - Grid detection

    private static func findGridBounds(cgImage: CGImage) async -> CGRect {
        let ci = CIImage(cgImage: cgImage)
        if let obs = await detectLargestRect(in: ci) { return obs.boundingBox }
        return CGRect(x: 0.02, y: 0.02, width: 0.96, height: 0.96)
    }

    private static func detectLargestRect(in image: CIImage) async -> VNRectangleObservation? {
        await withCheckedContinuation { (c: CheckedContinuation<VNRectangleObservation?, Never>) in
            let req = VNDetectRectanglesRequest { r, _ in
                c.resume(returning: (r.results as? [VNRectangleObservation])?
                    .max { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height })
            }
            req.minimumAspectRatio = 0.6; req.maximumAspectRatio = 1.4
            req.minimumSize = 0.1; req.maximumObservations = 20; req.minimumConfidence = 0.1
            let h = VNImageRequestHandler(ciImage: image, options: [:])
            do { try h.perform([req]) } catch { c.resume(returning: nil) }
        }
    }

    // MARK: - Strategy 1: Full-grid accurate OCR

    /// Runs VNRecognizeTextRequest (.accurate) on the whole image and uses each
    /// observation's bounding box to determine which cell the digit belongs to.
    private static func fullGridOCR(cgImage: CGImage, gridBounds: CGRect) async -> [[Int]] {
        let observations = await recognizeAllText(cgImage: cgImage)
        var matrix = Array(repeating: Array(repeating: 0, count: 9), count: 9)

        for obs in observations {
            // Each observation's boundingBox is in Vision normalized coords (origin = bottom-left).
            let box = obs.boundingBox

            // Check that the centre of the observation falls inside the detected grid.
            guard gridBounds.contains(CGPoint(x: box.midX, y: box.midY)) else { continue }

            // Relative position inside the grid (0…1 each axis).
            let relX = (box.midX - gridBounds.minX) / gridBounds.width
            let relY = (box.midY - gridBounds.minY) / gridBounds.height
            // relY is 0 at the bottom of the grid → row 8; 1 at top → row 0.
            let col = max(0, min(Int(relX * 9), 8))
            let row = max(0, min(8 - Int(relY * 9), 8))

            // Try to extract a single digit from this observation.
            let digit = extractBestDigit(from: obs)
            if digit != 0 { matrix[row][col] = digit }
        }
        return matrix
    }

    private static func recognizeAllText(cgImage: CGImage) async -> [VNRecognizedTextObservation] {
        await withCheckedContinuation { (c: CheckedContinuation<[VNRecognizedTextObservation], Never>) in
            let req = VNRecognizeTextRequest { r, _ in
                c.resume(returning: (r.results as? [VNRecognizedTextObservation]) ?? [])
            }
            req.recognitionLevel       = .accurate
            req.usesLanguageCorrection = false
            req.customWords            = ["1","2","3","4","5","6","7","8","9"]
            let h = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
            do { try h.perform([req]) } catch { c.resume(returning: []) }
        }
    }

    /// Returns the first valid 1–9 digit found in the top candidates of an observation.
    private static func extractBestDigit(from obs: VNRecognizedTextObservation) -> Int {
        for candidate in obs.topCandidates(3) {
            let t = candidate.string.trimmingCharacters(in: .whitespaces)
            // Direct single-character hit.
            if t.count == 1, let d = Int(t), (1...9).contains(d) { return d }
            // Multi-character string — try per-character extraction.
            for ch in t {
                if let d = Int(String(ch)), (1...9).contains(d) { return d }
            }
        }
        return 0
    }

    // MARK: - Strategy 2: Cell-by-cell accurate OCR

    private static func cellByCellOCR(cgImage: CGImage, gridBounds: CGRect) async -> [[Int]] {
        let imgW  = CGFloat(cgImage.width)
        let imgH  = CGFloat(cgImage.height)
        // Convert gridBounds from Vision coords (BL-origin) to CGImage coords (TL-origin).
        let gx    = gridBounds.minX * imgW
        let gy    = (1.0 - gridBounds.maxY) * imgH
        let cellW = gridBounds.width  * imgW / 9
        let cellH = gridBounds.height * imgH / 9
        let inset = min(cellW, cellH) * 0.08
        var matrix = Array(repeating: Array(repeating: 0, count: 9), count: 9)

        for row in 0..<9 {
            for col in 0..<9 {
                let rect = CGRect(
                    x: gx + CGFloat(col) * cellW + inset,
                    y: gy + CGFloat(row) * cellH + inset,
                    width:  cellW - 2 * inset,
                    height: cellH - 2 * inset)
                guard let cell   = cgImage.cropping(to: rect),
                      let scaled = upscaled(cell, to: 300) else { continue }
                matrix[row][col] = await recognizeSingleDigit(scaled)
            }
        }
        return matrix
    }

    // MARK: - Single digit recognition

    private static func recognizeSingleDigit(_ cgImage: CGImage) async -> Int {
        await withCheckedContinuation { (c: CheckedContinuation<Int, Never>) in
            let req = VNRecognizeTextRequest { r, _ in
                let digit = (r.results as? [VNRecognizedTextObservation])?
                    .compactMap { o -> Int? in
                        for cand in o.topCandidates(3) {
                            let t = cand.string.trimmingCharacters(in: .whitespaces)
                            if t.count == 1, let d = Int(t), (1...9).contains(d) { return d }
                        }
                        return nil
                    }.first ?? 0
                c.resume(returning: digit)
            }
            req.recognitionLevel       = .accurate
            req.usesLanguageCorrection = false
            let h = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
            do { try h.perform([req]) } catch { c.resume(returning: 0) }
        }
    }

    // MARK: - Helpers

    private static func upscaled(_ src: CGImage, to size: Int) -> CGImage? {
        let s = CGSize(width: size, height: size)
        return UIGraphicsImageRenderer(size: s).image { ctx in
            ctx.cgContext.setFillColor(UIColor.white.cgColor)
            ctx.cgContext.fill(CGRect(origin: .zero, size: s))
            UIImage(cgImage: src).draw(in: CGRect(origin: .zero, size: s))
        }.cgImage
    }
}

// MARK: - UIImage orientation

private extension UIImage {
    var normalizedOrientation: UIImage {
        guard imageOrientation != .up else { return self }
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        defer { UIGraphicsEndImageContext() }
        draw(in: CGRect(origin: .zero, size: size))
        return UIGraphicsGetImageFromCurrentImageContext() ?? self
    }
}

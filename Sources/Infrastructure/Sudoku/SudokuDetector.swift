import Vision
import CoreImage
import UIKit

struct SudokuDetector {

    enum DetectionError: LocalizedError {
        case noGridFound

        var errorDescription: String? {
            "No se detectó un tablero de Sudoku en la imagen."
        }
    }

    // MARK: - Public

    static func detect(in image: UIImage) async throws -> SudokuGrid {
        let img = image.normalizedOrientation
        guard let cgImage = img.cgImage else { throw DetectionError.noGridFound }

        // Strategy 1: full-image accurate OCR.
        // Derives grid bounds from the digit positions themselves — no
        // VNDetectRectanglesRequest needed, so a misdetected bounding box
        // can never silently discard all the real digits.
        let (s1, derivedBounds) = await fullGridOCR(cgImage: cgImage)
        let s1Count = s1.flatMap({ $0 }).filter({ $0 != 0 }).count
        if s1Count >= 10 { return SudokuGrid(cells: s1) }

        // Strategy 2: cell-by-cell accurate OCR.
        // Use bounds derived from Strategy 1, or fall back to rectangle
        // detection, or use the whole image as a last resort.
        let rectBounds = await findGridBoundsFromRectDetect(cgImage: cgImage)
        let gridBounds = derivedBounds ?? rectBounds ?? CGRect(x: 0.02, y: 0.02, width: 0.96, height: 0.96)

        let s2 = await cellByCellOCR(cgImage: cgImage, gridBounds: gridBounds)
        let s2Count = s2.flatMap({ $0 }).filter({ $0 != 0 }).count

        // Return the richer result, even if both found very few digits.
        return SudokuGrid(cells: s1Count >= s2Count ? s1 : s2)
    }

    // MARK: - Strategy 1: Full-image accurate OCR + spatial clustering

    /// Runs VNRecognizeTextRequest(.accurate) on the whole image and clusters
    /// the resulting digit observations into a 9×9 grid.
    /// Also returns the derived grid bounding box (Vision coords) for use by S2.
    private static func fullGridOCR(cgImage: CGImage) async -> ([[Int]], CGRect?) {
        let allObs = await recognizeAllText(cgImage: cgImage)

        // Collect single-digit (1-9) observations with their centres.
        struct DigitObs { let digit: Int; let cx: CGFloat; let cy: CGFloat }
        var digits: [DigitObs] = []
        for obs in allObs {
            let d = extractBestDigit(from: obs)
            if d != 0 {
                digits.append(.init(digit: d, cx: obs.boundingBox.midX, cy: obs.boundingBox.midY))
            }
        }

        guard digits.count >= 4 else { return (emptyMatrix(), nil) }

        // Derive grid bounds from digit positions (Vision coords, BL origin).
        let minX = digits.map(\.cx).min()!
        let maxX = digits.map(\.cx).max()!
        let minY = digits.map(\.cy).min()!
        let maxY = digits.map(\.cy).max()!

        // Expand by half a cell on each side so the border cells are centred.
        // A Sudoku has digits in 30 of 81 cells at most; we estimate cell size
        // from the spread of observations.
        let spanX = maxX - minX
        let spanY = maxY - minY
        // Expected col span if digits were spread across all 9 cols: spanX ≈ 8 * cellW
        // We use the number of distinct positions as a rough guide, but simply
        // expand by 10% on each side as a safe margin.
        let padX = max(spanX * 0.10, 0.02)
        let padY = max(spanY * 0.10, 0.02)
        let derivedBounds = CGRect(
            x: max(0, minX - padX),
            y: max(0, minY - padY),
            width: min(1, maxX - minX + 2 * padX),
            height: min(1, maxY - minY + 2 * padY)
        )

        // Map each digit to its cell using the derived bounds.
        var matrix = emptyMatrix()
        for obs in digits {
            let relX = (obs.cx - derivedBounds.minX) / derivedBounds.width
            let relY = (obs.cy - derivedBounds.minY) / derivedBounds.height
            let col = max(0, min(Int(relX * 9), 8))
            let row = max(0, min(8 - Int(relY * 9), 8))
            matrix[row][col] = obs.digit
        }
        return (matrix, derivedBounds)
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

    /// Returns the first valid 1–9 digit found in the top candidates.
    private static func extractBestDigit(from obs: VNRecognizedTextObservation) -> Int {
        for candidate in obs.topCandidates(3) {
            let t = candidate.string.trimmingCharacters(in: .whitespaces)
            if t.count == 1, let d = Int(t), (1...9).contains(d) { return d }
            // Multi-char fallback: take first valid digit character.
            for ch in t {
                if let d = Int(String(ch)), (1...9).contains(d) { return d }
            }
        }
        return 0
    }

    // MARK: - Grid detection (used only as S2 fallback)

    private static func findGridBoundsFromRectDetect(cgImage: CGImage) async -> CGRect? {
        await withCheckedContinuation { (c: CheckedContinuation<CGRect?, Never>) in
            let req = VNDetectRectanglesRequest { r, _ in
                let best = (r.results as? [VNRectangleObservation])?
                    .max { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height }
                c.resume(returning: best?.boundingBox)
            }
            req.minimumAspectRatio = 0.6; req.maximumAspectRatio = 1.4
            req.minimumSize = 0.1; req.maximumObservations = 20; req.minimumConfidence = 0.1
            let ci = CIImage(cgImage: cgImage)
            let h = VNImageRequestHandler(ciImage: ci, options: [:])
            do { try h.perform([req]) } catch { c.resume(returning: nil) }
        }
    }

    // MARK: - Strategy 2: Cell-by-cell accurate OCR

    private static func cellByCellOCR(cgImage: CGImage, gridBounds: CGRect) async -> [[Int]] {
        let imgW  = CGFloat(cgImage.width)
        let imgH  = CGFloat(cgImage.height)
        // gridBounds is in Vision coords (BL-origin) → convert to CGImage coords (TL-origin).
        let gx    = gridBounds.minX * imgW
        let gy    = (1.0 - gridBounds.maxY) * imgH
        let cellW = gridBounds.width  * imgW / 9
        let cellH = gridBounds.height * imgH / 9
        let inset = min(cellW, cellH) * 0.08
        var matrix = emptyMatrix()

        for row in 0..<9 {
            for col in 0..<9 {
                let rect = CGRect(
                    x: gx + CGFloat(col) * cellW + inset,
                    y: gy + CGFloat(row) * cellH + inset,
                    width:  cellW - 2 * inset,
                    height: cellH - 2 * inset)
                guard rect.width > 0, rect.height > 0,
                      let cell   = cgImage.cropping(to: rect),
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

    private static func emptyMatrix() -> [[Int]] {
        Array(repeating: Array(repeating: 0, count: 9), count: 9)
    }

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

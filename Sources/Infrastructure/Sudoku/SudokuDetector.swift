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
        let img = image.normalizedOrientation
        guard let cgImage = img.cgImage else { throw DetectionError.noGridFound }

        let gridBounds = await findGridBounds(cgImage: cgImage)

        // Strategy 1: detect text rectangles → recognize each character region
        let s1 = await textRectOCR(cgImage: cgImage, gridBounds: gridBounds)
        if s1.flatMap({ $0 }).filter({ $0 != 0 }).count >= 5 { return SudokuGrid(cells: s1) }

        // Strategy 2: row-by-row strips
        let s2 = await rowByRowOCR(cgImage: cgImage, gridBounds: gridBounds)
        if s2.flatMap({ $0 }).filter({ $0 != 0 }).count >= 5 { return SudokuGrid(cells: s2) }

        // Strategy 3: cell-by-cell at 300 px
        let s3 = await cellByCellOCR(cgImage: cgImage, gridBounds: gridBounds)
        return SudokuGrid(cells: s3)
    }

    // MARK: - Grid detection

    private static func findGridBounds(cgImage: CGImage) async -> CGRect {
        let ci = CIImage(cgImage: cgImage)
        if let obs = await detectLargestRect(in: ci) { return obs.boundingBox }
        return CGRect(x: 0.05, y: 0.05, width: 0.90, height: 0.90)
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

    // MARK: - Strategy 1: VNDetectTextRectanglesRequest + per-char recognition

    /// Finds all text/character bounding boxes in the image first,
    /// then crops + recognizes each one. Works well for isolated digits.
    private static func textRectOCR(cgImage: CGImage, gridBounds: CGRect) async -> [[Int]] {
        let charBoxes = await detectCharacterBoxes(cgImage: cgImage)
        let imgW = CGFloat(cgImage.width)
        let imgH = CGFloat(cgImage.height)
        var matrix = Array(repeating: Array(repeating: 0, count: 9), count: 9)

        for box in charBoxes {
            // box is Vision normalized coords (origin bottom-left)
            guard gridBounds.contains(CGPoint(x: box.midX, y: box.midY)) else { continue }

            let relX = (box.midX - gridBounds.minX) / gridBounds.width
            let relY = (box.midY - gridBounds.minY) / gridBounds.height
            let col  = max(0, min(Int(relX * 9), 8))
            let row  = max(0, min(8 - Int(relY * 9), 8))

            // Convert to CGImage coords (flip Y)
            let cropRect = CGRect(
                x: box.minX * imgW,
                y: (1.0 - box.maxY) * imgH,
                width:  box.width  * imgW,
                height: box.height * imgH
            )
            guard let crop   = cgImage.cropping(to: cropRect),
                  let scaled = upscaled(crop, to: 200) else { continue }

            let digit = await recognizeSingleDigit(scaled)
            if digit != 0 { matrix[row][col] = digit }
        }
        return matrix
    }

    /// Returns character-level bounding boxes (Vision normalized, bottom-left origin).
    private static func detectCharacterBoxes(cgImage: CGImage) async -> [CGRect] {
        await withCheckedContinuation { (c: CheckedContinuation<[CGRect], Never>) in
            let req = VNDetectTextRectanglesRequest { r, _ in
                guard let obs = r.results as? [VNTextObservation] else { c.resume(returning: []); return }
                var boxes: [CGRect] = []
                for o in obs {
                    if let chars = o.characterBoxes, !chars.isEmpty {
                        boxes += chars.map(\.boundingBox)
                    } else {
                        boxes.append(o.boundingBox)   // fallback: whole word box
                    }
                }
                c.resume(returning: boxes)
            }
            req.reportCharacterBoxes = true
            let h = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
            do { try h.perform([req]) } catch { c.resume(returning: []) }
        }
    }

    // MARK: - Strategy 2: Row-by-row strips

    private static func rowByRowOCR(cgImage: CGImage, gridBounds: CGRect) async -> [[Int]] {
        let imgW  = CGFloat(cgImage.width)
        let imgH  = CGFloat(cgImage.height)
        let gx    = gridBounds.minX * imgW
        let gy    = (1.0 - gridBounds.maxY) * imgH
        let gw    = gridBounds.width  * imgW
        let gh    = gridBounds.height * imgH
        let cellH = gh / 9
        var matrix = Array(repeating: Array(repeating: 0, count: 9), count: 9)

        for row in 0..<9 {
            let rect = CGRect(x: gx, y: gy + CGFloat(row) * cellH, width: gw, height: cellH)
            guard let strip  = cgImage.cropping(to: rect),
                  let padded = paddedStrip(strip, targetHeight: 80) else { continue }
            for (digit, nx) in await ocrStrip(padded) {
                let col = max(0, min(Int(nx * 9), 8))
                if matrix[row][col] == 0 { matrix[row][col] = digit }
            }
        }
        return matrix
    }

    private static func ocrStrip(_ cgImage: CGImage) async -> [(Int, CGFloat)] {
        await withCheckedContinuation { (c: CheckedContinuation<[(Int, CGFloat)], Never>) in
            var result: [(Int, CGFloat)] = []
            let req = VNRecognizeTextRequest { r, _ in
                if let obs = r.results as? [VNRecognizedTextObservation] {
                    for o in obs {
                        for (d, bbox) in extractDigits(from: o) { result.append((d, bbox.midX)) }
                    }
                }
                c.resume(returning: result)
            }
            req.recognitionLevel = .fast
            req.usesLanguageCorrection = false
            let h = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
            do { try h.perform([req]) } catch { c.resume(returning: result) }
        }
    }

    private static func paddedStrip(_ src: CGImage, targetHeight: CGFloat) -> CGImage? {
        let scale    = targetHeight / CGFloat(src.height)
        let scaledW  = CGFloat(src.width) * scale
        let pad      = targetHeight * 0.25
        let size     = CGSize(width: scaledW + 2 * pad, height: targetHeight + 2 * pad)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            ctx.cgContext.setFillColor(UIColor.white.cgColor)
            ctx.cgContext.fill(CGRect(origin: .zero, size: size))
            UIImage(cgImage: src).draw(in: CGRect(x: pad, y: pad, width: scaledW, height: targetHeight))
        }.cgImage
    }

    // MARK: - Strategy 3: Cell-by-cell

    private static func cellByCellOCR(cgImage: CGImage, gridBounds: CGRect) async -> [[Int]] {
        let imgW  = CGFloat(cgImage.width)
        let imgH  = CGFloat(cgImage.height)
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

    private static func extractDigits(from obs: VNRecognizedTextObservation) -> [(Int, CGRect)] {
        for candidate in obs.topCandidates(2) {
            let str = candidate.string
            if str.count == 1, let d = Int(str), (1...9).contains(d) { return [(d, obs.boundingBox)] }
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

import Vision
import CoreImage
import UIKit

struct SudokuDetector {

    enum DetectionError: LocalizedError {
        case noGridFound
        var errorDescription: String? { "No se detectó un tablero de Sudoku en la imagen." }
    }

    // MARK: - OCR confusion map
    // Vision regularly misreads certain digits as visually similar letters.
    // This map converts the most common confusions back to the correct digit.
    private static let ocrConfusions: [Character: Int] = [
        // Digit   Confused as
        "Z": 2, "z": 2,                    // 2 ↔ Z
        "S": 5, "s": 5,                    // 5 ↔ S
        "b": 6, "G": 6,                    // 6 ↔ b / G
        "g": 9,                            // 9 ↔ g
        // "q" removed — q looks more like 6 (open tail bottom-left) than 9.
        // Keeping it as 9 was causing 6→9 misclassification.
        "q": 6,                            // 6 ↔ q  (open bottom-left, like 6)
        "l": 1, "I": 1, "|": 1, "i": 1,  // 1 ↔ l / I / |  / i
        "B": 8, "ß": 8,                    // 8 ↔ B / ß
        "A": 4,                            // 4 ↔ A (rare but happens)
        "З": 3, "з": 3,                    // 3 ↔ Cyrillic Ze (identical glyph)
        "Э": 3, "э": 3,                    // 3 ↔ Cyrillic E-reverse
        "о": 0, "О": 0,                    // 0 ↔ Cyrillic o/O (filtered out later, but prevents false digits)
    ]

    // MARK: - Public

    static func detect(in image: UIImage) async throws -> SudokuGrid {
        let img = image.normalizedOrientation
        guard let cgImage = img.cgImage else { throw DetectionError.noGridFound }

        // Strategy 1 — full-image accurate OCR.
        // Derives the grid bounds from the spatial distribution of found digits,
        // so a wrong VNDetectRectanglesRequest can never discard real digits.
        let (s1, derivedBounds) = await fullGridOCR(cgImage: cgImage)

        // Strategy 2 — cell-by-cell OCR only for cells S1 left empty.
        // For S2 we want the LARGEST plausible grid bounds, so we union
        // the digit-derived bounds with the rectangle-detector result.
        // This covers edge columns/rows that S1 missed (derivedBounds would
        // be too narrow) while still benefiting from digit-position data
        // when the rectangle detector fires a false positive.
        let rectBounds = await findGridBoundsFromRectDetect(cgImage: cgImage)
        let baseBounds = derivedBounds ?? CGRect(x: 0.02, y: 0.02, width: 0.96, height: 0.96)
        let gridBounds = rectBounds.map { baseBounds.union($0) } ?? baseBounds

        let emptyCells: [(Int, Int)] = (0..<9).flatMap { r in
            (0..<9).compactMap { c in s1[r][c] == 0 ? (r, c) : nil }
        }

        var merged = s1
        if !emptyCells.isEmpty {
            let fills = await cellByCellOCR(cgImage: cgImage, gridBounds: gridBounds, only: emptyCells)
            for (r, c) in emptyCells where fills[r][c] != 0 {
                merged[r][c] = fills[r][c]
            }
        }

        return SudokuGrid(cells: merged)
    }

    // MARK: - Public bounds detection (used by crop UI)

    /// Fast pre-scan: returns the best grid bounding rect in Vision coordinates
    /// (origin bottom-left, values 0–1). Combines digit-position clustering with
    /// rectangle detection. Returns nil when nothing plausible is found.
    static func findGridBounds(in image: UIImage) async -> CGRect? {
        let img = image.normalizedOrientation
        guard let cgImage = img.cgImage else { return nil }

        // Run both strategies concurrently.
        async let digitBoundsResult = fullGridOCR(cgImage: cgImage)
        async let rectBoundsResult  = findGridBoundsFromRectDetect(cgImage: cgImage)

        let (_, digitBounds) = await digitBoundsResult
        let rectBounds        = await rectBoundsResult

        switch (digitBounds, rectBounds) {
        case let (d?, r?): return d.union(r)
        case let (d?, _):  return d
        case let (_, r?):  return r
        case _:            return nil
        }
    }

    // MARK: - Strategy 1: Full-image accurate OCR + spatial clustering

    private static func fullGridOCR(cgImage: CGImage) async -> ([[Int]], CGRect?) {
        let allObs = await recognizeAllText(cgImage: cgImage)

        struct DigitObs { let digit: Int; let cx: CGFloat; let cy: CGFloat }
        var digits: [DigitObs] = []
        for obs in allObs {
            let d = extractBestDigit(from: obs)
            if d != 0 {
                digits.append(.init(digit: d, cx: obs.boundingBox.midX, cy: obs.boundingBox.midY))
            }
        }

        guard digits.count >= 4 else { return (emptyMatrix(), nil) }

        let minX = digits.map(\.cx).min()!
        let maxX = digits.map(\.cx).max()!
        let minY = digits.map(\.cy).min()!
        let maxY = digits.map(\.cy).max()!
        let spanX = maxX - minX
        let spanY = maxY - minY

        // Half-cell padding: the outermost digits are centred inside their cells,
        // not at the grid edges.  Using spanX/8 (conservative) instead of
        // spanX/16 (ideal for 9 cols) ensures the bounds still reach the real
        // grid edge when one or both extreme columns have no detected digit.
        let halfCellX = max(spanX / 8, 0.02)
        let halfCellY = max(spanY / 8, 0.02)

        let derivedBounds = CGRect(
            x: max(0, minX - halfCellX),
            y: max(0, minY - halfCellY),
            width:  min(1, spanX + 2 * halfCellX),
            height: min(1, spanY + 2 * halfCellY)
        )

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

    /// Returns the first valid 1–9 digit from the observation's top candidates,
    /// applying the OCR confusion map to recover misread characters.
    private static func extractBestDigit(from obs: VNRecognizedTextObservation) -> Int {
        for candidate in obs.topCandidates(5) {
            let t = candidate.string.trimmingCharacters(in: .whitespaces)
            for ch in t {
                // Direct digit parse first.
                if let d = Int(String(ch)), (1...9).contains(d) { return d }
                // Confusion-map fallback.
                if let d = ocrConfusions[ch], (1...9).contains(d) { return d }
            }
        }
        return 0
    }

    // MARK: - Grid detection (S2 fallback)

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

    /// `only` restricts processing to the given (row,col) pairs, or all 81 cells if nil.
    private static func cellByCellOCR(
        cgImage: CGImage,
        gridBounds: CGRect,
        only cells: [(Int, Int)]? = nil
    ) async -> [[Int]] {
        let imgW  = CGFloat(cgImage.width)
        let imgH  = CGFloat(cgImage.height)
        let gx    = gridBounds.minX * imgW
        let gy    = (1.0 - gridBounds.maxY) * imgH
        let cellW = gridBounds.width  * imgW / 9
        let cellH = gridBounds.height * imgH / 9
        let inset = min(cellW, cellH) * 0.08
        var matrix = emptyMatrix()

        let targets = cells ?? (0..<9).flatMap { r in (0..<9).map { c in (r, c) } }

        for (row, col) in targets {
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
        return matrix
    }

    // MARK: - Single digit recognition

    private static func recognizeSingleDigit(_ cgImage: CGImage) async -> Int {
        // Attempt 1 — 300 px upscale (normal).
        if let s = upscaled(cgImage, to: 300) {
            let d = await ocrCell(s); if d != 0 { return d }
        }
        // Attempt 2 — 300 px high-contrast: helps with thin web-font strokes.
        if let s = highContrast(cgImage, size: 300) {
            let d = await ocrCell(s); if d != 0 { return d }
        }
        // Attempt 3 — 500 px upscale.
        if let s = upscaled(cgImage, to: 500) {
            let d = await ocrCell(s); if d != 0 { return d }
        }
        // Attempt 4 — 500 px high-contrast.
        if let s = highContrast(cgImage, size: 500) {
            let d = await ocrCell(s); if d != 0 { return d }
        }
        // Attempt 5 — original size, no processing.
        return await ocrCell(cgImage)
    }

    /// Upscales and applies high-contrast greyscale — improves recognition of
    /// thin-stroke digital fonts common in web-rendered Sudoku images.
    private static func highContrast(_ src: CGImage, size: Int) -> CGImage? {
        guard let base = upscaled(src, to: size) else { return nil }
        let ci = CIImage(cgImage: base)
        guard let filter = CIFilter(name: "CIColorControls",
                                    parameters: [kCIInputImageKey:      ci,
                                                 kCIInputContrastKey:   NSNumber(value: 3.5),
                                                 kCIInputSaturationKey: NSNumber(value: 0.0),
                                                 kCIInputBrightnessKey: NSNumber(value: 0.0)])
        else { return nil }
        guard let out = filter.outputImage else { return nil }
        return CIContext().createCGImage(out, from: out.extent)
    }

    private static func ocrCell(_ cgImage: CGImage) async -> Int {
        await withCheckedContinuation { (c: CheckedContinuation<Int, Never>) in
            let req = VNRecognizeTextRequest { r, _ in
                let digit = (r.results as? [VNRecognizedTextObservation])?
                    .compactMap { o -> Int? in
                        for cand in o.topCandidates(5) {
                            let t = cand.string.trimmingCharacters(in: .whitespaces)
                            for ch in t {
                                if let d = Int(String(ch)), (1...9).contains(d) { return d }
                                if let d = ocrConfusions[ch] { return d }
                            }
                        }
                        return nil
                    }.first ?? 0
                c.resume(returning: digit)
            }
            req.recognitionLevel       = .accurate
            req.usesLanguageCorrection = false
            req.customWords            = ["1","2","3","4","5","6","7","8","9"]
            req.recognitionLanguages   = ["en-US"]
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

extension UIImage {
    var normalizedOrientation: UIImage {
        guard imageOrientation != .up else { return self }
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        defer { UIGraphicsEndImageContext() }
        draw(in: CGRect(origin: .zero, size: size))
        return UIGraphicsGetImageFromCurrentImageContext() ?? self
    }
}

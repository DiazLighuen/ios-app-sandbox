import SwiftUI

// MARK: - Crop View

/// Shown after the user picks an image. Lets them confirm or adjust the
/// detected crop area before the OCR runs.
struct SudokuCropView: View {
    let image: UIImage
    let onConfirm: (UIImage) -> Void
    let onCancel:  () -> Void

    // Normalized rect (0…1), UIKit origin = top-left
    @State private var normRect    = CGRect(x: 0.05, y: 0.05, width: 0.90, height: 0.90)
    @State private var isDetecting = true

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let dispRect = imageDisplayRect(imageSize: image.size, in: geo.size)
                let scrRect  = toScreen(normRect, display: dispRect)

                ZStack {
                    Color.black.ignoresSafeArea()

                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: geo.size.width, height: geo.size.height)

                    CropMaskView(rect: scrRect)

                    ForEach(CropCorner.allCases) { corner in
                        CornerHandleView(position: cornerPoint(corner, rect: scrRect))
                            .gesture(
                                DragGesture(minimumDistance: 0,
                                            coordinateSpace: .named("canvas"))
                                    .onChanged { v in
                                        move(corner, to: v.location, display: dispRect)
                                    }
                            )
                    }
                }
                .coordinateSpace(name: "canvas")
                .overlay(alignment: .bottom) {
                    if isDetecting {
                        Label("Detectando tablero…", systemImage: "viewfinder")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(.bottom, 20)
                    }
                }
            }
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("Ajustar recorte")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar", action: onCancel)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Confirmar") { confirmCrop() }
                        .fontWeight(.semibold)
                }
            }
            .task { await autoDetect() }
        }
    }

    // MARK: - Geometry helpers

    private func imageDisplayRect(imageSize: CGSize, in container: CGSize) -> CGRect {
        let scale = min(container.width / imageSize.width,
                        container.height / imageSize.height)
        let w = imageSize.width  * scale
        let h = imageSize.height * scale
        return CGRect(x: (container.width  - w) / 2,
                      y: (container.height - h) / 2,
                      width: w, height: h)
    }

    /// Normalized → screen pixels inside displayRect.
    private func toScreen(_ norm: CGRect, display: CGRect) -> CGRect {
        CGRect(x: display.minX + norm.minX * display.width,
               y: display.minY + norm.minY * display.height,
               width:  norm.width  * display.width,
               height: norm.height * display.height)
    }

    private func cornerPoint(_ corner: CropCorner, rect: CGRect) -> CGPoint {
        switch corner {
        case .topLeft:     return CGPoint(x: rect.minX, y: rect.minY)
        case .topRight:    return CGPoint(x: rect.maxX, y: rect.minY)
        case .bottomLeft:  return CGPoint(x: rect.minX, y: rect.maxY)
        case .bottomRight: return CGPoint(x: rect.maxX, y: rect.maxY)
        }
    }

    // MARK: - Drag logic

    private func move(_ corner: CropCorner, to location: CGPoint, display: CGRect) {
        // Convert screen location → normalized [0,1]
        let nx = ((location.x - display.minX) / display.width) .clamped(to: 0...1)
        let ny = ((location.y - display.minY) / display.height).clamped(to: 0...1)
        let minSide: CGFloat = 0.08

        var r = normRect
        switch corner {
        case .topLeft:
            let x = min(nx, r.maxX - minSide)
            let y = min(ny, r.maxY - minSide)
            r = CGRect(x: x, y: y, width: r.maxX - x, height: r.maxY - y)
        case .topRight:
            let mx = max(nx, r.minX + minSide)
            let y  = min(ny, r.maxY - minSide)
            r = CGRect(x: r.minX, y: y, width: mx - r.minX, height: r.maxY - y)
        case .bottomLeft:
            let x  = min(nx, r.maxX - minSide)
            let my = max(ny, r.minY + minSide)
            r = CGRect(x: x, y: r.minY, width: r.maxX - x, height: my - r.minY)
        case .bottomRight:
            let mx = max(nx, r.minX + minSide)
            let my = max(ny, r.minY + minSide)
            r = CGRect(x: r.minX, y: r.minY, width: mx - r.minX, height: my - r.minY)
        }
        normRect = r
    }

    // MARK: - Auto-detect

    private func autoDetect() async {
        isDetecting = true
        defer { isDetecting = false }

        guard let visionRect = await SudokuDetector.findGridBounds(in: image) else { return }

        // Vision uses bottom-left origin → convert to UIKit top-left
        let uiRect = CGRect(x: visionRect.minX,
                            y: 1 - visionRect.maxY,
                            width:  visionRect.width,
                            height: visionRect.height)
        let pad: CGFloat = 0.015
        normRect = CGRect(x: max(0, uiRect.minX - pad),
                          y: max(0, uiRect.minY - pad),
                          width:  min(1, uiRect.width  + 2 * pad),
                          height: min(1, uiRect.height + 2 * pad))
    }

    // MARK: - Confirm

    private func confirmCrop() {
        let normalized = image.normalizedOrientation
        guard let cg = normalized.cgImage else { onConfirm(image); return }

        let px = CGRect(x: normRect.minX * CGFloat(cg.width),
                        y: normRect.minY * CGFloat(cg.height),
                        width:  normRect.width  * CGFloat(cg.width),
                        height: normRect.height * CGFloat(cg.height))

        if let cropped = cg.cropping(to: px) {
            onConfirm(UIImage(cgImage: cropped))
        } else {
            onConfirm(image)
        }
    }
}

// MARK: - Crop mask (dimmed outside + border + grid)

private struct CropMaskView: View {
    let rect: CGRect

    var body: some View {
        Canvas { ctx, size in
            // Dim outside
            var outside = Path()
            outside.addRect(CGRect(origin: .zero, size: size))
            outside.addRect(rect)
            ctx.fill(outside, with: .color(.black.opacity(0.55)),
                     style: FillStyle(eoFill: true))

            // White border
            ctx.stroke(Path(rect), with: .color(.white), lineWidth: 1.5)

            // Rule-of-thirds guide lines
            var guide = Path()
            for i in 1...2 {
                let f = CGFloat(i) / 3
                guide.move(to: CGPoint(x: rect.minX + f * rect.width, y: rect.minY))
                guide.addLine(to: CGPoint(x: rect.minX + f * rect.width, y: rect.maxY))
                guide.move(to: CGPoint(x: rect.minX, y: rect.minY + f * rect.height))
                guide.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + f * rect.height))
            }
            ctx.stroke(guide, with: .color(.white.opacity(0.35)), lineWidth: 0.5)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Corner handle

private struct CornerHandleView: View {
    let position: CGPoint

    var body: some View {
        Circle()
            .fill(.white)
            .frame(width: 26, height: 26)
            .shadow(color: .black.opacity(0.45), radius: 3, x: 0, y: 1)
            .position(position)
    }
}

// MARK: - Corner enum

private enum CropCorner: CaseIterable, Identifiable {
    case topLeft, topRight, bottomLeft, bottomRight
    var id: Self { self }
}

// MARK: - Helpers

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

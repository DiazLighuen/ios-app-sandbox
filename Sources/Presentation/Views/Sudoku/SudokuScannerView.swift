import SwiftUI
import AVFoundation
import PhotosUI

// MARK: - Entry point shown when no grid is loaded

struct SudokuScannerView: View {
    @ObservedObject var viewModel: SudokuViewModel
    @State private var showCamera  = false
    @State private var showPicker  = false
    @State private var pickerItem: PhotosPickerItem?
    /// Image waiting to be cropped before OCR.
    @State private var imageToCrop: UIImage?

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "squareshape.split.3x3")
                .font(.system(size: 64, weight: .thin))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text("Escanear Sudoku")
                    .font(.title2.weight(.semibold))
                Text("Usá la cámara o elegí una imagen de la galería")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 14) {
                Button {
                    showCamera = true
                } label: {
                    Label("Cámara", systemImage: "camera.fill")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: 260)
                        .padding(.vertical, 14)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label("Galería", systemImage: "photo.on.rectangle")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: 260)
                        .padding(.vertical, 14)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color(.separator).opacity(0.5), lineWidth: 0.5))
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .padding(.horizontal, 32)
        // Camera
        .fullScreenCover(isPresented: $showCamera) {
            CameraCaptureView { image in
                showCamera = false
                imageToCrop = image
            }
        }
        // Gallery
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data  = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    imageToCrop = image
                }
                pickerItem = nil
            }
        }
        // Crop step — shown for both camera and gallery
        .fullScreenCover(isPresented: Binding(
            get: { imageToCrop != nil },
            set: { if !$0 { imageToCrop = nil } }
        )) {
            if let img = imageToCrop {
                SudokuCropView(image: img) { cropped in
                    imageToCrop = nil
                    Task { await viewModel.processImage(cropped) }
                } onCancel: {
                    imageToCrop = nil
                }
            }
        }
        .overlay {
            if viewModel.isProcessing {
                ProcessingOverlay()
            }
        }
        .alert("Error de detección", isPresented: .constant(viewModel.detectionError != nil)) {
            Button("OK") { viewModel.detectionError = nil }
        } message: {
            Text(viewModel.detectionError ?? "")
        }
    }
}

// MARK: - Camera capture (single frame)

struct CameraCaptureView: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType        = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate          = context.coordinator
        return picker
    }

    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onCapture: onCapture) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (UIImage) -> Void
        init(onCapture: @escaping (UIImage) -> Void) { self.onCapture = onCapture }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                onCapture(image)
            } else {
                picker.dismiss(animated: true)
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

// MARK: - Processing overlay

private struct ProcessingOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.4)
                Text("Analizando tablero…")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
            }
            .padding(28)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        }
    }
}

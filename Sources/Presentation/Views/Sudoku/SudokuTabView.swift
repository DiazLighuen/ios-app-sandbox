import SwiftUI

struct SudokuTabView: View {
    @StateObject private var viewModel = SudokuViewModel()

    var body: some View {
        NavigationStack {
            if viewModel.hasGrid {
                SudokuWorkspaceView(viewModel: viewModel)
            } else {
                SudokuScannerView(viewModel: viewModel)
                    .navigationTitle("Sudoku")
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
    }
}

// MARK: - Workspace (grid loaded)

private struct SudokuWorkspaceView: View {
    @ObservedObject var viewModel: SudokuViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Tab picker
            Picker("Modo", selection: $viewModel.displayMode) {
                Text("Original").tag(SudokuDisplayMode.original)
                Text("Jugando").tag(SudokuDisplayMode.playing)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            // Mode subtitle
            modeSubtitle
                .padding(.horizontal, 16)
                .padding(.bottom, 6)

            // Grid
            SudokuGridView(viewModel: viewModel)
                .padding(.horizontal, 12)

            // Number picker (only in edit mode with a selected cell)
            if viewModel.isEditingMode, let selected = viewModel.selectedCell {
                NumberPickerView { value in
                    viewModel.setCell(selected, value: value)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            Spacer(minLength: 0)

            // Action bar
            actionBar
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        }
        .navigationTitle("Sudoku")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .animation(.easeInOut(duration: 0.2), value: viewModel.isEditingMode)
        .animation(.easeInOut(duration: 0.2), value: viewModel.selectedCell)
        .animation(.easeInOut(duration: 0.2), value: viewModel.displayMode)
        .onChange(of: viewModel.displayMode) { _, _ in
            // Exit edit mode when switching tabs so stale selection is cleared.
            if viewModel.isEditingMode {
                viewModel.isEditingMode = false
                viewModel.selectedCell  = nil
            }
        }
        .alert("Aviso", isPresented: .constant(viewModel.detectionError != nil)) {
            Button("OK") { viewModel.detectionError = nil }
        } message: {
            Text(viewModel.detectionError ?? "")
        }
    }

    // MARK: - Mode subtitle

    @ViewBuilder
    private var modeSubtitle: some View {
        switch viewModel.displayMode {
        case .original:
            Text("Corregí los números si el escáner se equivocó")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .playing:
            if !viewModel.errorCells.isEmpty {
                Label(
                    "\(viewModel.errorCells.count) celda\(viewModel.errorCells.count == 1 ? "" : "s") incorrecta\(viewModel.errorCells.count == 1 ? "" : "s")",
                    systemImage: "exclamationmark.circle.fill"
                )
                .font(.caption.weight(.medium))
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if viewModel.solvedGrid != nil {
                Label("Solución completa", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("Ingresá tu solución. Los números en negro son las pistas.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Action bar

    private var actionBar: some View {
        HStack(spacing: 12) {
            switch viewModel.displayMode {
            case .original:
                ActionButton(label: "Nuevo", icon: "camera.viewfinder", color: .blue) {
                    viewModel.clearAll()
                }

            case .playing:
                ActionButton(
                    label: "Errores",
                    icon: "exclamationmark.magnifyingglass",
                    color: .orange
                ) {
                    viewModel.checkErrors()
                }

                ActionButton(
                    label: "Resolver",
                    icon: "checkmark.seal.fill",
                    color: .green,
                    disabled: !viewModel.canSolve
                ) {
                    viewModel.solve()
                }

                ActionButton(label: "Nuevo", icon: "camera.viewfinder", color: .blue) {
                    viewModel.clearAll()
                }
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                withAnimation { viewModel.isEditingMode.toggle() }
                if !viewModel.isEditingMode { viewModel.selectedCell = nil }
            } label: {
                Label(
                    viewModel.isEditingMode ? "Listo" : "Editar",
                    systemImage: viewModel.isEditingMode ? "checkmark" : "pencil"
                )
                .font(.subheadline.weight(.semibold))
            }
        }

        ToolbarItem(placement: .cancellationAction) {
            // Reset clears user entries in playing mode only.
            if viewModel.displayMode == .playing {
                Button {
                    viewModel.resetUserEntries()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
            }
        }
    }
}

// MARK: - Action button

private struct ActionButton: View {
    let label: String
    let icon: String
    let color: Color
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                Text(label)
                    .font(.caption.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .foregroundStyle(disabled ? Color(.tertiaryLabel) : color)
            .background(
                disabled ? Color(.systemFill) : color.opacity(0.12),
                in: RoundedRectangle(cornerRadius: 12)
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

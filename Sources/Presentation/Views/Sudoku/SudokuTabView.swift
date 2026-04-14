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
            // Mode picker
            Picker("Modo", selection: $viewModel.displayMode) {
                Text("Original").tag(SudokuDisplayMode.original)
                Text("Errores").tag(SudokuDisplayMode.errors)
                if viewModel.solvedGrid != nil {
                    Text("Resuelto").tag(SudokuDisplayMode.solved)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

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
        .alert("Sin solución", isPresented: .constant(viewModel.detectionError != nil)) {
            Button("OK") { viewModel.detectionError = nil }
        } message: {
            Text(viewModel.detectionError ?? "")
        }
    }

    // MARK: - Action bar

    private var actionBar: some View {
        HStack(spacing: 12) {
            // Check errors
            ActionButton(
                label: "Errores",
                icon: "exclamationmark.magnifyingglass",
                color: .orange
            ) {
                viewModel.checkErrors()
            }

            // Solve
            ActionButton(
                label: "Resolver",
                icon: "checkmark.seal.fill",
                color: .green,
                disabled: !viewModel.canSolve
            ) {
                viewModel.solve()
            }

            // Scan new
            ActionButton(
                label: "Nuevo",
                icon: "camera.viewfinder",
                color: .blue
            ) {
                viewModel.clearAll()
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
            if viewModel.originalGrid != nil {
                Button {
                    viewModel.resetToOriginal()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .disabled(viewModel.isEditingMode == false && viewModel.displayMode == .original)
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
                (disabled ? Color(.systemFill) : color.opacity(0.12)),
                in: RoundedRectangle(cornerRadius: 12)
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

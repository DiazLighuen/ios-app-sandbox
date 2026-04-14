import SwiftUI

enum SudokuDisplayMode {
    case original
    case errors
    case solved
}

@MainActor
final class SudokuViewModel: ObservableObject {

    // MARK: - Published state

    @Published private(set) var originalGrid: SudokuGrid?
    @Published           var currentGrid:     SudokuGrid?
    @Published private(set) var solvedGrid:   SudokuGrid?
    @Published private(set) var errorCells:   Set<GridPosition> = []
    @Published           var displayMode:     SudokuDisplayMode = .original
    @Published           var isEditingMode:   Bool = false
    @Published           var selectedCell:    GridPosition?
    @Published private(set) var isProcessing: Bool = false
    @Published           var detectionError:  String?

    // MARK: - Computed

    var hasGrid: Bool { currentGrid != nil }

    var displayedGrid: SudokuGrid? {
        switch displayMode {
        case .original: return currentGrid
        case .errors:   return currentGrid
        case .solved:   return solvedGrid ?? currentGrid
        }
    }

    var canSolve: Bool {
        guard let g = currentGrid else { return false }
        return errorCells.isEmpty && g.filledCount >= 17  // minimum clues for unique solution
    }

    // MARK: - Scanning

    func processImage(_ image: UIImage) async {
        isProcessing = true
        detectionError = nil
        defer { isProcessing = false }

        do {
            let grid = try await SudokuDetector.detect(in: image)
            originalGrid = grid
            currentGrid  = grid
            solvedGrid   = nil
            errorCells   = []
            displayMode  = .original
            isEditingMode = false
        } catch {
            detectionError = error.localizedDescription
        }
    }

    // MARK: - Grid actions

    func checkErrors() {
        guard let grid = currentGrid else { return }
        errorCells  = SudokuValidator.findErrors(in: grid)
        displayMode = .errors
    }

    func solve() {
        guard let grid = currentGrid else { return }
        if let solution = SudokuSolver.solve(grid) {
            solvedGrid  = solution
            displayMode = .solved
        } else {
            detectionError = "El Sudoku no tiene solución válida. Revisá los valores ingresados."
        }
    }

    func showOriginal() {
        displayMode = .original
        isEditingMode = false
        selectedCell = nil
    }

    // MARK: - Cell editing

    func selectCell(_ pos: GridPosition) {
        guard isEditingMode else { return }
        selectedCell = (selectedCell == pos) ? nil : pos
    }

    func setCell(_ pos: GridPosition, value: Int) {
        guard isEditingMode, currentGrid != nil else { return }
        currentGrid![pos.row, pos.col] = value
        // Clear derived state when user edits
        solvedGrid  = nil
        errorCells  = []
        displayMode = .original
        selectedCell = nil
    }

    func resetToOriginal() {
        currentGrid   = originalGrid
        solvedGrid    = nil
        errorCells    = []
        displayMode   = .original
        isEditingMode = false
        selectedCell  = nil
    }

    func clearAll() {
        originalGrid  = nil
        currentGrid   = nil
        solvedGrid    = nil
        errorCells    = []
        displayMode   = .original
        isEditingMode = false
        selectedCell  = nil
    }
}

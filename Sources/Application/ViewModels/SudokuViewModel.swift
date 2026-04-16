import SwiftUI

enum SudokuDisplayMode {
    /// View/edit the OCR-detected clues (ground truth of the puzzle).
    case original
    /// Enter and verify the user's answers on top of the clues.
    case playing
}

@MainActor
final class SudokuViewModel: ObservableObject {

    // MARK: - Published state

    /// Fixed clues as detected by OCR (editable in the Original tab).
    @Published private(set) var originalGrid: SudokuGrid?
    /// Numbers the user has entered while solving (editable in the Playing tab).
    @Published           var userGrid:        SudokuGrid?
    /// Solution computed by the solver — non-nil after "Resolver" is tapped.
    @Published private(set) var solvedGrid:   SudokuGrid?
    /// Cells flagged as wrong (direct conflict or mismatch with known solution).
    @Published private(set) var errorCells:   Set<GridPosition> = []
    @Published           var displayMode:     SudokuDisplayMode = .original
    @Published           var isEditingMode:   Bool = false
    @Published           var selectedCell:    GridPosition?
    @Published private(set) var isProcessing: Bool = false
    @Published           var detectionError:  String?

    // MARK: - Computed

    var hasGrid: Bool { originalGrid != nil }

    /// Merge: original clues + user answers (user entries only fill empty clue cells).
    var mergedGrid: SudokuGrid? {
        guard var base = originalGrid else { return nil }
        if let user = userGrid {
            for r in 0..<9 {
                for c in 0..<9 where base[r, c] == 0 && user[r, c] != 0 {
                    base[r, c] = user[r, c]
                }
            }
        }
        return base
    }

    var displayedGrid: SudokuGrid? {
        switch displayMode {
        case .original: return originalGrid
        case .playing:  return solvedGrid ?? mergedGrid
        }
    }

    /// True when the cell came from OCR (not user-entered) — shown bold and non-editable in playing mode.
    func isOriginalCell(_ pos: GridPosition) -> Bool {
        (originalGrid?[pos.row, pos.col] ?? 0) != 0
    }

    var canSolve: Bool {
        (mergedGrid?.filledCount ?? 0) >= 17
    }

    // MARK: - Scanning

    func processImage(_ image: UIImage) async {
        isProcessing = true
        detectionError = nil
        defer { isProcessing = false }

        do {
            let grid = try await SudokuDetector.detect(in: image)
            originalGrid  = grid
            userGrid      = .empty()
            solvedGrid    = nil
            errorCells    = []
            displayMode   = .original
            isEditingMode = false
        } catch {
            detectionError = error.localizedDescription
        }
    }

    // MARK: - Grid actions

    /// Check user entries for correctness.
    ///
    /// Pass 1 — direct conflicts (duplicates in the same row/col/3×3 box).
    /// Pass 2 — if no direct conflicts, solve from the original clues alone and
    ///           compare each user-entered cell against the known solution.
    func checkErrors() {
        guard let merged = mergedGrid, let original = originalGrid else { return }
        solvedGrid = nil

        // Pass 1: direct conflicts.
        let direct = SudokuValidator.findErrors(in: merged)
        if !direct.isEmpty {
            errorCells  = direct
            displayMode = .playing
            return
        }

        // Pass 2: deep check — compare user entries against the known solution.
        if let solution = SudokuSolver.solve(original) {
            var wrong = Set<GridPosition>()
            for r in 0..<9 {
                for c in 0..<9 {
                    let entered = userGrid?[r, c] ?? 0
                    if entered != 0 && entered != solution[r, c] {
                        wrong.insert(GridPosition(row: r, col: c))
                    }
                }
            }
            errorCells = wrong
        } else {
            // The original clues themselves are unsolvable — ask the user to fix them.
            errorCells = []
            detectionError = "Los datos del tablero original no tienen solución. Corregí los valores en la pestaña Original."
        }
        displayMode = .playing
    }

    func solve() {
        guard let original = originalGrid else { return }
        errorCells = []
        // Solve from the original clues only — ignores user entries so that
        // wrong user values never make a valid puzzle appear unsolvable.
        if let solution = SudokuSolver.solve(original) {
            solvedGrid  = solution
            displayMode = .playing
        } else {
            detectionError = "El Sudoku no tiene solución. Revisá los valores en la pestaña Original."
        }
    }

    // MARK: - Cell editing

    func selectCell(_ pos: GridPosition) {
        guard isEditingMode else { return }
        // In playing mode, original clue cells are not editable.
        if displayMode == .playing && isOriginalCell(pos) { return }
        selectedCell = (selectedCell == pos) ? nil : pos
    }

    func setCell(_ pos: GridPosition, value: Int) {
        guard isEditingMode else { return }

        switch displayMode {
        case .original:
            // Editing the OCR clues — changes are authoritative.
            originalGrid?[pos.row, pos.col] = value
            // Invalidate user work since the base puzzle changed.
            userGrid   = .empty()
            solvedGrid = nil
            errorCells = []

        case .playing:
            // Only empty clue cells can be filled by the user.
            guard !isOriginalCell(pos) else { return }
            if userGrid == nil { userGrid = .empty() }
            userGrid![pos.row, pos.col] = value
            solvedGrid = nil
            errorCells = []
        }
        selectedCell = nil
    }

    /// Clear all user-entered answers (keeps original clues intact).
    func resetUserEntries() {
        userGrid      = .empty()
        solvedGrid    = nil
        errorCells    = []
        displayMode   = .playing
        isEditingMode = false
        selectedCell  = nil
    }

    func clearAll() {
        originalGrid  = nil
        userGrid      = nil
        solvedGrid    = nil
        errorCells    = []
        displayMode   = .original
        isEditingMode = false
        selectedCell  = nil
    }
}

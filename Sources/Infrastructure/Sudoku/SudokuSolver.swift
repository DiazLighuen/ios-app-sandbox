import Foundation

struct SudokuSolver {
    /// Returns a solved copy of the grid, or nil if unsolvable.
    static func solve(_ grid: SudokuGrid) -> SudokuGrid? {
        var work = grid
        return backtrack(&work) ? work : nil
    }

    // MARK: - Private

    private static func backtrack(_ grid: inout SudokuGrid) -> Bool {
        guard let pos = nextEmpty(in: grid) else { return true }  // solved
        for value in 1...9 {
            if isValid(value, at: pos, in: grid) {
                grid[pos.row, pos.col] = value
                if backtrack(&grid) { return true }
                grid[pos.row, pos.col] = 0
            }
        }
        return false
    }

    private static func nextEmpty(in grid: SudokuGrid) -> GridPosition? {
        for row in 0..<9 {
            for col in 0..<9 {
                if grid[row, col] == 0 { return GridPosition(row: row, col: col) }
            }
        }
        return nil
    }

    private static func isValid(_ value: Int, at pos: GridPosition, in grid: SudokuGrid) -> Bool {
        let row = pos.row, col = pos.col

        // Row
        for c in 0..<9 where grid[row, c] == value { return false }
        // Column
        for r in 0..<9 where grid[r, col] == value { return false }
        // 3×3 box
        let boxRow = (row / 3) * 3
        let boxCol = (col / 3) * 3
        for r in boxRow..<boxRow + 3 {
            for c in boxCol..<boxCol + 3 {
                if grid[r, c] == value { return false }
            }
        }
        return true
    }
}

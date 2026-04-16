import Foundation

struct SudokuValidator {
    /// Returns all positions that violate Sudoku rules (duplicates in row/col/box).
    static func findErrors(in grid: SudokuGrid) -> Set<GridPosition> {
        var errors = Set<GridPosition>()

        for i in 0..<9 {
            errors.formUnion(duplicates(in: rowPositions(i), grid: grid))
            errors.formUnion(duplicates(in: colPositions(i), grid: grid))
        }
        for boxRow in 0..<3 {
            for boxCol in 0..<3 {
                errors.formUnion(duplicates(in: boxPositions(boxRow, boxCol), grid: grid))
            }
        }
        return errors
    }

    // MARK: - Private helpers

    private static func duplicates(in positions: [GridPosition], grid: SudokuGrid) -> Set<GridPosition> {
        var seen = [Int: GridPosition]()
        var dupes = Set<GridPosition>()
        for pos in positions {
            let val = grid[pos.row, pos.col]
            guard val != 0 else { continue }
            if let prev = seen[val] {
                dupes.insert(prev)
                dupes.insert(pos)
            } else {
                seen[val] = pos
            }
        }
        return dupes
    }

    private static func rowPositions(_ row: Int) -> [GridPosition] {
        (0..<9).map { GridPosition(row: row, col: $0) }
    }

    private static func colPositions(_ col: Int) -> [GridPosition] {
        (0..<9).map { GridPosition(row: $0, col: col) }
    }

    private static func boxPositions(_ boxRow: Int, _ boxCol: Int) -> [GridPosition] {
        let startRow = boxRow * 3
        let startCol = boxCol * 3
        return (0..<3).flatMap { r in
            (0..<3).map { c in GridPosition(row: startRow + r, col: startCol + c) }
        }
    }
}

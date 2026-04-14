import Foundation

struct GridPosition: Hashable {
    let row: Int
    let col: Int
}

struct SudokuGrid {
    // 0 = empty cell
    private(set) var cells: [[Int]]

    init(cells: [[Int]]) {
        self.cells = cells
    }

    subscript(row: Int, col: Int) -> Int {
        get { cells[row][col] }
        set { cells[row][col] = newValue }
    }

    var isEmpty: Bool {
        cells.allSatisfy { $0.allSatisfy { $0 == 0 } }
    }

    var filledCount: Int {
        cells.flatMap { $0 }.filter { $0 != 0 }.count
    }

    static func empty() -> SudokuGrid {
        SudokuGrid(cells: Array(repeating: Array(repeating: 0, count: 9), count: 9))
    }
}

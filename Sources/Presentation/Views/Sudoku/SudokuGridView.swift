import SwiftUI

// MARK: - Grid

struct SudokuGridView: View {
    @ObservedObject var viewModel: SudokuViewModel

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let cellSize = size / 9

            ZStack {
                gridLines(size: size, cellSize: cellSize)
                cellsLayer(cellSize: cellSize)
            }
            .frame(width: size, height: size)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    // MARK: - Cells

    private func cellsLayer(cellSize: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(0..<9, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<9, id: \.self) { col in
                        SudokuCellView(
                            pos: GridPosition(row: row, col: col),
                            viewModel: viewModel,
                            cellSize: cellSize
                        )
                    }
                }
            }
        }
    }

    // MARK: - Grid lines

    private func gridLines(size: CGFloat, cellSize: CGFloat) -> some View {
        Canvas { ctx, _ in
            for i in 0...9 {
                let pos = CGFloat(i) * cellSize
                let isBold = i % 3 == 0

                var col = Path()
                col.move(to: CGPoint(x: pos, y: 0))
                col.addLine(to: CGPoint(x: pos, y: size))
                ctx.stroke(col, with: .color(isBold ? .primary : .secondary.opacity(0.4)),
                           lineWidth: isBold ? 2 : 0.5)

                var row = Path()
                row.move(to: CGPoint(x: 0, y: pos))
                row.addLine(to: CGPoint(x: size, y: pos))
                ctx.stroke(row, with: .color(isBold ? .primary : .secondary.opacity(0.4)),
                           lineWidth: isBold ? 2 : 0.5)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Cell

struct SudokuCellView: View {
    let pos: GridPosition
    @ObservedObject var viewModel: SudokuViewModel
    let cellSize: CGFloat

    private var value: Int {
        viewModel.displayedGrid?[pos.row, pos.col] ?? 0
    }

    /// Came from OCR — bold in both modes.
    private var isOriginal: Bool {
        viewModel.isOriginalCell(pos)
    }

    /// User-entered cell that the solver filled in (shown in blue).
    private var isSolvedCell: Bool {
        viewModel.displayMode == .playing &&
        viewModel.solvedGrid != nil &&
        (viewModel.mergedGrid?[pos.row, pos.col] ?? 0) == 0 &&
        value != 0
    }

    private var isError: Bool {
        viewModel.errorCells.contains(pos)
    }

    private var isSelected: Bool {
        viewModel.selectedCell == pos
    }

    /// In playing mode, original cells are not tappable — dim the selection hint.
    private var isNonEditable: Bool {
        viewModel.displayMode == .playing && isOriginal
    }

    private var cellBackground: Color {
        if isSelected    { return Color.blue.opacity(0.25) }
        if isError       { return Color.red.opacity(0.15) }
        return Color.clear
    }

    private var textColor: Color {
        if isError       { return .red }
        if isSolvedCell  { return .blue }
        if isOriginal    { return .primary }
        // User-entered answers shown in a slightly subdued color.
        return .primary.opacity(0.75)
    }

    var body: some View {
        ZStack {
            cellBackground
                .animation(.easeInOut(duration: 0.15), value: isSelected)
                .animation(.easeInOut(duration: 0.15), value: isError)

            if value != 0 {
                Text("\(value)")
                    .font(.system(
                        size: cellSize * 0.48,
                        weight: isOriginal ? .semibold : .regular,
                        design: .rounded
                    ))
                    .foregroundStyle(textColor)
                    .animation(.easeInOut(duration: 0.15), value: textColor)
            }
        }
        .frame(width: cellSize, height: cellSize)
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.selectCell(pos)
        }
    }
}

// MARK: - Number picker

struct NumberPickerView: View {
    let onSelect: (Int) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(1...5, id: \.self) { n in pickerButton(n) }
            }
            HStack(spacing: 0) {
                ForEach(6...9, id: \.self) { n in pickerButton(n) }
                pickerButton(0, label: Image(systemName: "delete.left"))
            }
        }
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(.separator).opacity(0.4), lineWidth: 0.5))
    }

    private func pickerButton(_ value: Int, label: some View = EmptyView()) -> some View {
        Button {
            onSelect(value)
        } label: {
            Group {
                if value == 0 {
                    Image(systemName: "delete.left")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(value)")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 48)
        }
        .buttonStyle(.plain)
    }
}

// Overload to resolve EmptyView ambiguity when no label is passed
private extension NumberPickerView {
    func pickerButton(_ value: Int) -> some View {
        pickerButton(value, label: EmptyView() as EmptyView)
    }
}

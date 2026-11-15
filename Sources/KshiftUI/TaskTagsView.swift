import Foundation
import SwiftUI

struct TaskTagList: View {
    let tags: [String]

    var body: some View {
        TagFlowLayout(spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                TaskTagChip(tag: tag)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct TaskTagEditor: View {
    @Binding var tags: [String]
    @Binding var input: String
    @FocusState private var isInputFocused: Bool

    var body: some View {
        TagFlowLayout(spacing: 7, expandsLastItem: true) {
            ForEach(tags, id: \.self) { tag in
                TaskTagChip(tag: tag) {
                    remove(tag)
                }
            }

            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                TextField("添加标签", text: $input)
                    .textFieldStyle(.plain)
                    .font(.callout)
                    .focused($isInputFocused)
                    .onSubmit(commitInput)
                    .onChange(of: input) { _, value in
                        guard value.contains(where: { $0 == "," || $0 == "，" || $0 == "\n" }) else {
                            return
                        }
                        commitInput()
                    }
                    .frame(minWidth: 150)
                    .accessibilityLabel("添加任务标签")
                    .accessibilityIdentifier("task-tag-input")
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 28)
            .background(.primary.opacity(0.05), in: Capsule())
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            .primary.opacity(0.025),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.separator, lineWidth: 1)
        }
    }

    private func commitInput() {
        tags = TaskTagValues.adding(input, to: tags)
        input = ""
    }

    private func remove(_ tag: String) {
        tags.removeAll { $0 == tag }
    }
}

enum TaskTagValues {
    static func adding(_ input: String, to tags: [String]) -> [String] {
        var result = tags
        for value in normalized(input) where !contains(value, in: result) {
            result.append(value)
        }
        return result
    }

    static func normalized(_ input: String) -> [String] {
        input
            .components(separatedBy: CharacterSet(charactersIn: ",，\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func contains(_ value: String, in tags: [String]) -> Bool {
        tags.contains { $0.caseInsensitiveCompare(value) == .orderedSame }
    }
}

private struct TaskTagChip: View {
    let tag: String
    var onRemove: (() -> Void)?

    var body: some View {
        HStack(spacing: 4) {
            Text("#\(tag)")
                .font(.caption.weight(.medium))
                .lineLimit(1)

            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.bold))
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("移除标签 \(tag)")
            }
        }
        .foregroundStyle(.tint)
        .padding(.leading, 10)
        .padding(.trailing, onRemove == nil ? 10 : 5)
        .frame(minHeight: 28)
        .background(.tint.opacity(0.1), in: Capsule())
    }
}

private struct TagFlowLayout: Layout {
    var spacing: CGFloat
    var expandsLastItem = false

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let arrangement = arrange(subviews: subviews, availableWidth: proposal.width)
        return CGSize(
            width: proposal.width ?? arrangement.width,
            height: arrangement.height
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let arrangement = arrange(subviews: subviews, availableWidth: bounds.width)
        for (index, frame) in arrangement.frames.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: frame.width, height: frame.height)
            )
        }
    }

    private func arrange(
        subviews: Subviews,
        availableWidth: CGFloat?
    ) -> (frames: [CGRect], width: CGFloat, height: CGFloat) {
        let maximumWidth = availableWidth ?? .infinity
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var contentWidth: CGFloat = 0

        for (index, subview) in subviews.enumerated() {
            let measured = subview.sizeThatFits(.unspecified)
            var itemWidth = min(measured.width, maximumWidth)
            let itemHeight = measured.height

            if x > 0, x + itemWidth > maximumWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }

            if expandsLastItem, index == subviews.count - 1, maximumWidth.isFinite {
                itemWidth = max(itemWidth, maximumWidth - x)
            }

            frames.append(CGRect(x: x, y: y, width: itemWidth, height: itemHeight))
            x += itemWidth + spacing
            rowHeight = max(rowHeight, itemHeight)
            contentWidth = max(contentWidth, x - spacing)
        }

        return (frames, contentWidth, y + rowHeight)
    }
}

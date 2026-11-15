import SwiftUI

struct TaskCreationButton<Label: View>: View {
    @ObservedObject var model: AppModel
    let assigneeIDs: [String]
    let date: Date?
    let arrowEdge: Edge
    let label: () -> Label
    @State private var draft: TaskDraft?

    init(
        model: AppModel,
        assigneeIDs: [String],
        date: Date? = nil,
        arrowEdge: Edge = .top,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.model = model
        self.assigneeIDs = assigneeIDs
        self.date = date
        self.arrowEdge = arrowEdge
        self.label = label
    }

    var body: some View {
        Button {
            draft = model.newTaskDraft(assigneeIDs: assigneeIDs, date: date)
        } label: {
            label()
        }
        .popover(
            item: $draft,
            attachmentAnchor: .rect(.bounds),
            arrowEdge: arrowEdge
        ) { draft in
            TaskEditorView(
                model: model,
                initialDraft: draft,
                presentation: .popover
            )
        }
    }
}

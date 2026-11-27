import SwiftUI

private struct KshiftForcedDynamicTypeSizeKey: EnvironmentKey {
    static let defaultValue: DynamicTypeSize? = nil
}

extension EnvironmentValues {
    /// Test-only override used by release evidence capture.
    public var kshiftForcedDynamicTypeSize: DynamicTypeSize? {
        get { self[KshiftForcedDynamicTypeSizeKey.self] }
        set { self[KshiftForcedDynamicTypeSizeKey.self] = newValue }
    }
}

struct KshiftPlannerDynamicTypeSizeModifier: ViewModifier {
    let forcedSize: DynamicTypeSize?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let forcedSize {
            content.dynamicTypeSize(forcedSize)
        } else {
            content.dynamicTypeSize(.xSmall ... .accessibility5)
        }
    }
}

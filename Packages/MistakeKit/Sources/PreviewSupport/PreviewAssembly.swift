#if os(iOS)
import SwiftUI
import Contracts
import TestSupport
import UI

/// This target is not linked by the production App and exists only for synthetic previews.
@MainActor
public enum PreviewAssembly {
    public static func make() -> MistakeBookRootView {
        MistakeBookRootView(service: PreviewAppService(records: [ContractSamples.mistakeRecord()]))
    }
}

#Preview("合成预览 · 非正式业务数据") {
    PreviewAssembly.make()
}
#endif

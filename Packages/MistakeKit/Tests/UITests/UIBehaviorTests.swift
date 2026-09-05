#if os(iOS)
import XCTest
import Contracts
import TestSupport
import UI

@MainActor
final class UIBehaviorTests: XCTestCase {
    func testRootCanBeConstructedWithOnlyAppService() {
        let service = PreviewAppService(records: [ContractSamples.mistakeRecord()])
        let view = MistakeBookRootView(service: service)
        _ = view.body
        XCTAssertNotNil(view)
    }

    func testPracticeExportOptionsRejectAnswerSections() {
        XCTAssertThrowsError(try ExportOptions(mode: .practice, includeHandwriting: true,
                                               includeHypotheses: false, blankSpace: .medium,
                                               sort: .selectionOrder, pageSize: .a4))
        XCTAssertNoThrow(try ExportOptions(mode: .practice, includeHandwriting: false,
                                           includeHypotheses: false, blankSpace: .medium,
                                           sort: .selectionOrder, pageSize: .a4))
    }
}
#else
import XCTest

final class UIBehaviorTests: XCTestCase {
    func testUIRequiresiOSRuntime() throws {
        throw XCTSkip("UI tests require an iOS simulator or device.")
    }
}
#endif

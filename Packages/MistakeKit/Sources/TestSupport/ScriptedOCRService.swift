import Foundation
import Contracts

/// Test-only deterministic cancellation/failure control; does not implement OCR.
public actor ScriptedOCRService: OCRService {
    private let result: Result<RecognizedPage, AppError>
    private let delay: Duration
    public private(set) var callCount = 0

    public init(result: Result<RecognizedPage, AppError>, delay: Duration = .zero) {
        self.result = result; self.delay = delay
    }
    public func supportedLanguages() async throws -> [String] {
        try Task.checkCancellation()
        return ["synthetic-language"]
    }
    public func recognize(image: ImagePayload, options: RecognitionOptions) async throws -> RecognizedPage {
        callCount += 1
        try await Task.sleep(for: delay)
        try Task.checkCancellation()
        return try result.get()
    }
}

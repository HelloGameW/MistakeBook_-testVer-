import Foundation

public enum AchievementStoreError: Error, Sendable, Equatable {
    case invalidData
    case unsupportedSchema(Int)
}

public protocol AchievementStateStore: Sendable {
    func load() async throws -> AchievementState?
    func save(_ state: AchievementState) async throws
}

public actor InMemoryAchievementStateStore: AchievementStateStore {
    private var state: AchievementState?

    public init(initialState: AchievementState? = nil) {
        self.state = initialState
    }

    public func load() async throws -> AchievementState? { state }
    public func save(_ state: AchievementState) async throws { self.state = state }
}

/// The file is intentionally separate from MistakeBook's SwiftData store.
/// This lets the feature be removed or reset without touching records/assets.
public actor JSONFileAchievementStateStore: AchievementStateStore {
    public let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL) {
        self.fileURL = fileURL
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public func load() async throws -> AchievementState? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        do {
            return try decoder.decode(AchievementState.self, from: Data(contentsOf: fileURL))
        } catch {
            throw AchievementStoreError.invalidData
        }
    }

    public func save(_ state: AchievementState) async throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            let data = try encoder.encode(state)
            try data.write(to: fileURL, options: .atomic)
        } catch let error as AchievementStoreError {
            throw error
        } catch {
            throw AchievementStoreError.invalidData
        }
    }
}

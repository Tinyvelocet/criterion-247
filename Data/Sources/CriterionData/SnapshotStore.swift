import Foundation

/// Persists and loads a `CriterionSnapshot` in a shared App Group container.
/// This is the single bridge between the menu-bar app (writer, source of truth)
/// and the widget (reader). The app group identifier is injectable for tests.
public struct SnapshotStore: Sendable {
    public let appGroupID: String
    private let filename = "snapshot.json"

    /// Override for tests — points at a plain directory instead of an App Group
    /// container, so save/load can be exercised without the entitlement.
    public var containerOverride: URL?

    public init(appGroupID: String) {
        self.appGroupID = appGroupID
    }

    public var containerURL: URL? {
        if let override = containerOverride { return override }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    private var fileURL: URL? {
        containerURL?.appendingPathComponent(filename)
    }

    public func save(_ snapshot: CriterionSnapshot) throws {
        guard let url = fileURL else {
            throw SnapshotStoreError.noAppGroupContainer
        }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try Self.encode(snapshot)
        try data.write(to: url, options: [.atomic])
    }

    public func load() -> CriterionSnapshot? {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url) else { return nil }
        return Self.decode(data)
    }

    // MARK: - Pure Codable round-trip (testable without App Group entitlement)

    public static func encode(_ snapshot: CriterionSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(snapshot)
    }

    public static func decode(_ data: Data) -> CriterionSnapshot? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CriterionSnapshot.self, from: data)
    }
}

public enum SnapshotStoreError: Error, CustomStringConvertible, Sendable {
    case noAppGroupContainer
    public var description: String {
        switch self {
        case .noAppGroupContainer:
            return "App Group container not available (entitlement missing or wrong identifier)."
        }
    }
}
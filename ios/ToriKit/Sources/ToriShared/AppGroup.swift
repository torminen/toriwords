import Foundation

/// App Group container layout. The root is injectable for tests.
public struct AppGroup: Sendable {
    public static let identifier = "group.com.toriwords.app"

    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    #if canImport(Darwin)
    /// The real App Group container; nil if the entitlement is missing.
    public static var shared: AppGroup? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier).map(AppGroup.init)
    }
    #endif

    public var vocabIndex: URL { root.appendingPathComponent("vocab-index.json") }
    public var widgetSnapshot: URL { root.appendingPathComponent("widget-snapshot.json") }
    public var captureSticky: URL { root.appendingPathComponent("capture-sticky.json") }
    public var inbox: Inbox { Inbox(directory: root.appendingPathComponent("inbox", isDirectory: true)) }
}

/// Atomic file writes: write `.tmp-<name>` in the same directory, then rename over the target,
/// so a reader never sees a partial file (and `inbox/` listings never see an unfinished capture).
public enum AtomicFile {
    public static func write(_ data: Data, to url: URL) throws {
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let temp = dir.appendingPathComponent(".tmp-" + url.lastPathComponent)
        try data.write(to: temp)
        guard rename(temp.path, url.path) == 0 else {
            let code = errno
            try? FileManager.default.removeItem(at: temp)
            throw CocoaError(.fileWriteUnknown, userInfo: [NSUnderlyingErrorKey: POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)])
        }
    }

    public static func write(_ value: some Encodable, to url: URL) throws {
        try write(try JSONFiles.encoder.encode(value), to: url)
    }

    /// Decodes a JSON file; nil when the file does not exist.
    public static func read<T: Decodable>(_ type: T.Type, from url: URL) throws -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try JSONDecoder().decode(type, from: data)
    }
}

enum JSONFiles {
    static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return e
    }
}

/// Darwin notification the Share Extension posts after writing an inbox file.
public enum InboxNotification {
    public static let name = "com.toriwords.inbox.changed"

    #if canImport(Darwin)
    public static func post() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(), CFNotificationName(name as CFString), nil, nil, true)
    }

    /// Calls `handler` (on an arbitrary thread) for each post while this object is alive.
    public final class Observer: Sendable {
        private let handler: @Sendable () -> Void

        public init(_ handler: @escaping @Sendable () -> Void) {
            self.handler = handler
            CFNotificationCenterAddObserver(
                CFNotificationCenterGetDarwinNotifyCenter(), Unmanaged.passUnretained(self).toOpaque(),
                { _, observer, _, _, _ in
                    guard let observer else { return }
                    Unmanaged<Observer>.fromOpaque(observer).takeUnretainedValue().handler()
                },
                InboxNotification.name as CFString, nil, .deliverImmediately)
        }

        deinit {
            CFNotificationCenterRemoveEveryObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                                    Unmanaged.passUnretained(self).toOpaque())
        }
    }
    #endif
}

import Foundation

/// Runs work on the main thread: inline when already there, otherwise hopped via `hop`.
/// For system callbacks whose completion handler must be called on main (e.g. notification responses).
public enum MainThreadHandoff {
    public static func run(isMainThread: Bool = Thread.isMainThread,
                           hop: (@escaping @Sendable () -> Void) -> Void = { DispatchQueue.main.async(execute: $0) },
                           _ work: @escaping @Sendable () -> Void) {
        if isMainThread { work() } else { hop(work) }
    }
}

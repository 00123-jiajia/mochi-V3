import Darwin
import Foundation

/// A downloaded app keeps `com.apple.quarantine` until something removes it.
/// Gatekeeper asks the user once. After the app is allowed to open, this clears
/// the mark on the bundle so the hook command inside it can run.
public enum DownloadQuarantine {
    public static let attribute = "com.apple.quarantine"

    /// True when no connector the capsule can show is linked yet.
    public static func offerConnect(cursorConnected: Bool, codexConnected: Bool, grokConnected: Bool) -> Bool {
        !cursorConnected && !codexConnected && !grokConnected
    }

    /// The real downloaded app, when macOS has opened a temporary copy instead.
    /// Hook commands must point at the downloaded app, which stays put.
    public static func relocatedBundle(current: URL) -> URL? {
        guard current.path.contains("/AppTranslocation/") else { return nil }
        guard let original = originalLocation(of: current) else { return nil }
        guard original.standardizedFileURL.path != current.standardizedFileURL.path else { return nil }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: original.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }
        return original
    }

    @discardableResult
    public static func clear(at root: URL) -> Bool {
        clearItem(root)
        if let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: nil,
            options: []
        ) {
            for case let url as URL in enumerator {
                clearItem(url)
            }
        }
        return !isMarked(at: root)
    }

    public static func isMarked(at root: URL) -> Bool {
        if hasMark(root) { return true }
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: nil,
            options: []
        ) else { return false }
        for case let url as URL in enumerator {
            if hasMark(url) { return true }
        }
        return false
    }

    public static func mark(_ url: URL) {
        let value = Data("0083;00000000;Safari;MochiIsland".utf8)
        _ = value.withUnsafeBytes { buffer in
            setxattr(url.path, attribute, buffer.baseAddress, buffer.count, 0, 0)
        }
    }

    private typealias OriginalPathFn = @convention(c) (
        CFURL,
        UnsafeMutablePointer<Unmanaged<CFError>?>?
    ) -> Unmanaged<CFURL>?

    private static func originalLocation(of url: URL) -> URL? {
        guard let handle = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_NOW) else {
            return nil
        }
        guard let symbol = dlsym(handle, "SecTranslocateCreateOriginalPathForURL") else { return nil }
        let lookup = unsafeBitCast(symbol, to: OriginalPathFn.self)
        var error: Unmanaged<CFError>?
        guard let made = lookup(url as CFURL, &error) else { return nil }
        return made.takeRetainedValue() as URL
    }

    private static func hasMark(_ url: URL) -> Bool {
        getxattr(url.path, attribute, nil, 0, 0, 0) >= 0
    }

    private static func clearItem(_ url: URL) {
        _ = removexattr(url.path, attribute, 0)
    }
}

import AppKit
import Security

/// Checks GitHub for a newer release, then downloads, verifies and installs it in place.
///
/// A release is installed only when its app is signed by this team (so a tampered or foreign
/// download is rejected) and its version is newer than the running one.
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()

    struct Release: Equatable {
        let version: String
        let notes: String
        let downloadURL: URL
        let pageURL: URL
    }

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(Release)
        case installing
        case failed(String)
    }

    @Published private(set) var state: State = .idle

    private static let latestReleaseURL = URL(string: "https://api.github.com/repos/tajshaik24/display-assistant/releases/latest")!
    private static let teamID = "LDUCPMFSMH"
    private static let checkInterval: TimeInterval = 24 * 60 * 60

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    private var timer: Timer?
    private var resetTask: Task<Void, Never>?

    private init() {}

    /// Checks shortly after launch and then once a day, without interrupting the user.
    func startAutomaticChecks() {
        guard timer == nil else { return }
        Task {
            try? await Task.sleep(for: .seconds(10))
            await check(userInitiated: false)
        }
        timer = Timer.scheduledTimer(withTimeInterval: Self.checkInterval, repeats: true) { _ in
            Task { @MainActor in await Updater.shared.check(userInitiated: false) }
        }
    }

    func check(userInitiated: Bool) async {
        switch state {
        case .checking, .installing: return
        case .available where !userInitiated: return
        default: break
        }
        resetTask?.cancel()
        let previous = state
        state = .checking
        do {
            if let release = try await Self.fetchLatestRelease(),
               Self.isVersion(release.version, newerThan: Self.currentVersion) {
                state = .available(release)
            } else {
                state = userInitiated ? .upToDate : .idle
            }
        } catch {
            // Background checks fail quietly (offline, rate limited); keep what was shown before.
            state = userInitiated ? .failed("Couldn’t check for updates") : previous
        }
        if userInitiated, state == .upToDate || state.isFailure { clearMessageLater() }
    }

    /// Shows the release notes and installs the update if the user agrees.
    func promptToInstall(_ release: Release) {
        let alert = NSAlert()
        alert.messageText = "Display Assistant \(release.version) is available"
        alert.informativeText = "You have \(Self.currentVersion).\n\n" + Self.plainText(release.notes)
        alert.addButton(withTitle: "Install and Relaunch")
        alert.addButton(withTitle: "Later")
        alert.addButton(withTitle: "Release Notes…")
        NSApp.activate()
        switch alert.runModal() {
        case .alertFirstButtonReturn: Task { await install(release) }
        case .alertThirdButtonReturn: NSWorkspace.shared.open(release.pageURL)
        default: break
        }
    }

    func install(_ release: Release) async {
        guard state != .installing else { return }
        state = .installing
        do {
            let appURL = Bundle.main.bundleURL
            let staged = try await Self.download(release, replacing: appURL)
            try Self.verify(staged, newerThan: Self.currentVersion)
            _ = try FileManager.default.replaceItemAt(appURL, withItemAt: staged)
            Self.relaunch(appURL)
        } catch {
            state = .failed((error as? UpdateError)?.message ?? "Update failed")
            clearMessageLater(after: 8)
        }
    }

    private func clearMessageLater(after seconds: Double = 4) {
        resetTask = Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            if state == .upToDate || state.isFailure { state = .idle }
        }
    }

    // MARK: - GitHub

    private static func fetchLatestRelease() async throws -> Release? {
        var request = URLRequest(url: latestReleaseURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("DisplayAssistant/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError("Couldn’t check for updates") }

        struct Payload: Decodable {
            struct Asset: Decodable { let name: String; let browser_download_url: URL }
            let tag_name: String
            let body: String?
            let html_url: URL
            let draft: Bool
            let prerelease: Bool
            let assets: [Asset]
        }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        guard !payload.draft, !payload.prerelease,
              let asset = payload.assets.first(where: { $0.name.lowercased().hasSuffix(".zip") })
        else { return nil }
        let version = payload.tag_name.hasPrefix("v") ? String(payload.tag_name.dropFirst()) : payload.tag_name
        return Release(version: version, notes: payload.body ?? "", downloadURL: asset.browser_download_url, pageURL: payload.html_url)
    }

    /// Downloads and unzips the release next to the installed app (same volume, so the swap is atomic).
    private static func download(_ release: Release, replacing appURL: URL) async throws -> URL {
        let parent = appURL.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: parent.path) else {
            throw UpdateError("Can’t write to \(parent.lastPathComponent)")
        }
        let workDir = try FileManager.default.url(
            for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: appURL, create: true
        )
        let (zipURL, response) = try await URLSession.shared.download(from: release.downloadURL)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError("Download failed") }

        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        unzip.arguments = ["-x", "-k", zipURL.path, workDir.path]
        try unzip.run()
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async { unzip.waitUntilExit(); continuation.resume() }
        }
        try? FileManager.default.removeItem(at: zipURL)
        guard unzip.terminationStatus == 0,
              let app = try FileManager.default.contentsOfDirectory(at: workDir, includingPropertiesForKeys: nil)
                .first(where: { $0.pathExtension == "app" })
        else { throw UpdateError("The download is damaged") }
        return app
    }

    /// The new app must be signed by this team with this bundle ID, be intact, and be newer.
    private static func verify(_ app: URL, newerThan current: String) throws {
        var staticCode: SecStaticCode?
        var requirement: SecRequirement?
        let requirementText = "identifier \"com.tajshaik.DisplayAssistant\" and anchor apple generic and certificate leaf[subject.OU] = \"\(teamID)\""
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &staticCode) == errSecSuccess, let staticCode,
              SecRequirementCreateWithString(requirementText as CFString, [], &requirement) == errSecSuccess, let requirement
        else { throw UpdateError("The update isn’t signed") }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        guard SecStaticCodeCheckValidity(staticCode, flags, requirement) == errSecSuccess else {
            throw UpdateError("The update’s signature isn’t valid")
        }
        guard let version = Bundle(url: app)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              isVersion(version, newerThan: current)
        else { throw UpdateError("The update isn’t newer") }
    }

    /// Opens the new copy once this process has exited, then quits.
    private static func relaunch(_ appURL: URL) {
        let script = Process()
        script.executableURL = URL(fileURLWithPath: "/bin/sh")
        script.arguments = ["-c", "while kill -0 \"$1\" 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"$2\"",
                            "relaunch", String(ProcessInfo.processInfo.processIdentifier), appURL.path]
        try? script.run()
        NSApp.terminate(nil)
    }

    // MARK: - Helpers

    /// Compares dotted versions numerically, so 1.10 is newer than 1.9.
    static func isVersion(_ a: String, newerThan b: String) -> Bool {
        let lhs = a.split(separator: ".").map { Int($0) ?? 0 }
        let rhs = b.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(lhs.count, rhs.count) {
            let l = index < lhs.count ? lhs[index] : 0
            let r = index < rhs.count ? rhs[index] : 0
            if l != r { return l > r }
        }
        return false
    }

    /// Release notes are Markdown; the alert shows plain text.
    private static func plainText(_ markdown: String) -> String {
        let text = markdown
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "(?m)^#+ ", with: "", options: .regularExpression)
            .replacingOccurrences(of: "(?m)^- ", with: "• ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.count > 1200 ? String(text.prefix(1200)) + "…" : text
    }
}

private struct UpdateError: Error {
    let message: String
    init(_ message: String) { self.message = message }
}

extension Updater.State {
    var isFailure: Bool { if case .failed = self { true } else { false } }
}

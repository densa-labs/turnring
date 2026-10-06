import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Checks GitHub for a newer release once a day.
enum Updates {
    static let latestURL = URL(string: "https://api.github.com/repos/densa-labs/turnring/releases/latest")!

    /// Calls back with the newer version, if there is one.
    static func check(force: Bool = false, completion: @escaping (String?) -> Void) {
        if !force, let last = Prefs.lastUpdateCheck, Date().timeIntervalSince(last) < 24 * 3600 {
            return completion(nil)
        }
        var request = URLRequest(url: latestURL, timeoutInterval: 10)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { data, _, _ in
            Prefs.lastUpdateCheck = Date()
            struct Release: Decodable { var tag_name: String }
            guard let data, let release = try? JSONDecoder().decode(Release.self, from: data) else {
                return completion(nil)
            }
            let version = release.tag_name.hasPrefix("v") ? String(release.tag_name.dropFirst()) : release.tag_name
            completion(isNewer(version, than: turnringVersion) ? version : nil)
        }.resume()
    }

    static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }
        let y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }

    /// The shell command that installs the update for however Turnring was installed.
    static func installCommand(executable: String = CommandLine.arguments[0]) -> String {
        let resolved = URL(fileURLWithPath: executable).resolvingSymlinksInPath().path
        if let range = resolved.range(of: "/Cellar/turnring/") {
            let brew = resolved[..<range.lowerBound] + "/bin/brew"
            return "\(brew) update --quiet && \(brew) upgrade turnring && \(brew) services restart turnring"
        }
        return "curl -fsSL https://raw.githubusercontent.com/densa-labs/turnring/main/install.sh | sh"
    }
}

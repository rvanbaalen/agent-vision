import Foundation
import AgentVisionShared

/// Non-blocking check for newer versions on GitHub.
/// Prints a one-line notice to stderr if a newer version exists.
/// Silently does nothing on any failure (network, parse, timeout).
func checkForUpdate(owner: String, repo: String) {
    let urlString = "https://api.github.com/repos/\(owner)/\(repo)/releases/latest"
    guard let url = URL(string: urlString) else { return }

    var request = URLRequest(url: url)
    request.timeoutInterval = 2
    request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")

    let semaphore = DispatchSemaphore(value: 0)
    nonisolated(unsafe) var latestTag: String?

    let task = URLSession.shared.dataTask(with: request) { data, _, _ in
        defer { semaphore.signal() }
        guard let data = data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String else { return }
        latestTag = tag
    }
    task.resume()

    _ = semaphore.wait(timeout: .now() + 2)

    guard let tag = latestTag else { return }

    let remote = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
    let local = AgentVisionVersion.current

    if remote != local, remote > local {
        fputs("Update available: v\(local) → v\(remote). Run: brew upgrade agent-vision\n", stderr)
    }
}

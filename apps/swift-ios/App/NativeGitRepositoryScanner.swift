import Foundation

/// Finds Git repositories nested below a project folder that is not a repository itself.
/// It walks the server's directory browser, which lists directories only, so a `.git`
/// file (a linked worktree or a submodule) is not detected.
enum NativeGitRepositoryScanner {
    static let maximumDepth = 2
    static let maximumDirectories = 150
    private static let concurrentRequests = 12
    private static let skippedDirectories: Set<String> = [
        "node_modules", "vendor", "dist", "build", "target", "Pods", "DerivedData",
    ]

    /// Returns repository paths relative to `root`, `/`-separated and sorted. `browse`
    /// lists the subdirectories of an absolute directory path, hidden ones included.
    static func scan(
        root: String,
        browse: @escaping @Sendable (String) async throws -> [FilesystemBrowseEntry]
    ) async throws -> [String] {
        var repositories: [String] = []
        var pending = [""]
        var visited = 0
        for depth in 0...maximumDepth {
            try Task.checkCancellation()
            let batch = Array(pending.sorted().prefix(maximumDirectories - visited))
            guard !batch.isEmpty else { break }
            visited += batch.count
            pending = []
            for listing in try await listings(of: batch, root: root, browse: browse) {
                let names = listing.entries.map(\.name)
                if !listing.path.isEmpty, names.contains(".git") {
                    repositories.append(listing.path)
                } else if depth < maximumDepth {
                    pending += names
                        .filter { !$0.hasPrefix(".") && !skippedDirectories.contains($0) }
                        .map { listing.path.isEmpty ? $0 : listing.path + "/" + $0 }
                }
            }
        }
        return repositories.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// The root listing must succeed; an unreadable subdirectory counts as empty.
    private static func listings(
        of paths: [String],
        root: String,
        browse: @escaping @Sendable (String) async throws -> [FilesystemBrowseEntry]
    ) async throws -> [(path: String, entries: [FilesystemBrowseEntry])] {
        var results: [(path: String, entries: [FilesystemBrowseEntry])] = []
        for start in stride(from: 0, to: paths.count, by: concurrentRequests) {
            let chunk = paths[start..<min(start + concurrentRequests, paths.count)]
            results += try await withThrowingTaskGroup(
                of: (path: String, entries: [FilesystemBrowseEntry]).self
            ) { group in
                for path in chunk {
                    // A trailing separator makes the server list the directory itself, `.git` included.
                    let directory = NativeWorkspaceMapper.joinedPath(root, path)
                    let partialPath = directory.hasSuffix("/") || directory.hasSuffix("\\")
                        ? directory
                        : directory + "/"
                    group.addTask {
                        do {
                            return (path, try await browse(partialPath))
                        } catch {
                            if path.isEmpty { throw error }
                            return (path, [])
                        }
                    }
                }
                return try await group.reduce(into: []) { $0.append($1) }
            }
        }
        return results
    }
}

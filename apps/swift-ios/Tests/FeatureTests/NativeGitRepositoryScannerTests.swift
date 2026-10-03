import Foundation
import Testing
@testable import T3Code

@Suite("Nested Git repository scan")
struct NativeGitRepositoryScannerTests {
    private actor BrowseLog {
        private(set) var paths: [String] = []
        func record(_ path: String) { paths.append(path) }
    }

    private static func browser(
        _ tree: [String: [String]],
        log: BrowseLog,
        failing: Set<String> = []
    ) -> @Sendable (String) async throws -> [FilesystemBrowseEntry] {
        { path in
            await log.record(path)
            if failing.contains(path) { throw BrowseFailure() }
            return (tree[path] ?? []).map { FilesystemBrowseEntry(name: $0, fullPath: path + $0) }
        }
    }

    private struct BrowseFailure: Error {}

    @Test
    func findsRepositoriesTwoLevelsDownWithoutEnteringThem() async throws {
        let log = BrowseLog()
        let tree = [
            "/w/": ["repo-b", "repo-a", "packages", "node_modules", ".t3", "docs"],
            "/w/repo-a/": [".git", "src"],
            "/w/repo-b/": [".git"],
            "/w/packages/": ["api", "web"],
            "/w/packages/api/": [".git"],
            "/w/packages/web/": ["src"],
            "/w/docs/": ["deep"],
            "/w/docs/deep/": [".git-not", "deeper"],
        ]

        let repositories = try await NativeGitRepositoryScanner.scan(
            root: "/w",
            browse: Self.browser(tree, log: log)
        )

        #expect(repositories == ["packages/api", "repo-a", "repo-b"])
        let browsed = Set(await log.paths)
        #expect(!browsed.contains("/w/node_modules/"))
        #expect(!browsed.contains("/w/.t3/"))
        #expect(!browsed.contains("/w/repo-a/src/"))
        #expect(!browsed.contains("/w/docs/deep/deeper/"))
    }

    @Test
    func anUnreadableFolderIsSkippedButAnUnreadableRootFails() async throws {
        let tree = ["/w/": ["locked", "repo"], "/w/repo/": [".git"]]
        let repositories = try await NativeGitRepositoryScanner.scan(
            root: "/w",
            browse: Self.browser(tree, log: BrowseLog(), failing: ["/w/locked/"])
        )
        #expect(repositories == ["repo"])

        await #expect(throws: BrowseFailure.self) {
            try await NativeGitRepositoryScanner.scan(
                root: "/w",
                browse: Self.browser(tree, log: BrowseLog(), failing: ["/w/"])
            )
        }
    }

    @Test
    func joinsRelativePathsInTheRootsSeparatorStyle() {
        #expect(NativeWorkspaceMapper.joinedPath("/w", "packages/api") == "/w/packages/api")
        #expect(NativeWorkspaceMapper.joinedPath("/w/", "repo") == "/w/repo")
        #expect(NativeWorkspaceMapper.joinedPath("/w", "") == "/w")
        #expect(NativeWorkspaceMapper.joinedPath(#"C:\work"#, "packages/api") == #"C:\work\packages\api"#)
    }
}

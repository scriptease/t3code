import SwiftUI

/// Lists the Git repositories nested below a thread's project folder. Picking one, or the
/// project folder itself (`nil`), reports it through `onSelect` and dismisses.
struct FeatureGitRepositoryPicker: View {
    @SwiftUI.Environment(\.dismiss) private var dismiss
    let client: any FeatureClient
    let threadID: String
    let selection: String?
    let onSelect: (String?) -> Void

    @State private var repositories: [String]?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let repositories {
                List {
                    Section {
                        row(nil)
                    }
                    Section("Nested repositories") {
                        if repositories.isEmpty {
                            Text("No Git repositories within two folder levels.")
                                .foregroundStyle(T3Colors.textSecondary)
                        }
                        ForEach(repositories, id: \.self) { row($0) }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .refreshable { await load() }
            } else if let errorMessage {
                ContentUnavailableView {
                    Label("Repositories unavailable", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Retry") { Task { await load() } }
                }
            } else {
                ProgressView("Searching for repositories…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(T3Colors.background)
        .navigationTitle("Repository")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .task { await load() }
    }

    private func row(_ path: String?) -> some View {
        Button {
            onSelect(path)
            dismiss()
        } label: {
            HStack {
                Label(
                    path ?? "Project folder",
                    systemImage: path == nil ? "folder" : "arrow.triangle.branch"
                )
                .foregroundStyle(T3Colors.textPrimary)
                Spacer()
                if path == selection {
                    Image(systemName: "checkmark")
                        .foregroundStyle(T3Colors.accent)
                }
            }
        }
        .accessibilityAddTraits(path == selection ? .isSelected : [])
        .accessibilityIdentifier("git-repository-\(path ?? "project-folder")")
    }

    private func load() async {
        errorMessage = nil
        do {
            repositories = try await client.gitRepositoryCandidates(threadID: threadID)
        } catch is CancellationError {
            return
        } catch {
            repositories = nil
            errorMessage = error.localizedDescription
        }
    }
}

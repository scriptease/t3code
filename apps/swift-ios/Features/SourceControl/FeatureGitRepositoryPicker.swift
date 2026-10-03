import SwiftUI

/// Lists the Git repositories nested below a project folder, as returned by `load`. Picking
/// one, or the project folder itself (`nil`), reports it through `onSelect` and dismisses.
struct FeatureGitRepositoryPicker: View {
    @SwiftUI.Environment(\.dismiss) private var dismiss
    let selection: String?
    let load: () async throws -> [String]
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
                .refreshable { await reload() }
            } else if let errorMessage {
                ContentUnavailableView {
                    Label("Repositories unavailable", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Retry") { Task { await reload() } }
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
        .task { await reload() }
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

    private func reload() async {
        errorMessage = nil
        do {
            repositories = try await load()
        } catch is CancellationError {
            return
        } catch {
            repositories = nil
            errorMessage = error.localizedDescription
        }
    }
}

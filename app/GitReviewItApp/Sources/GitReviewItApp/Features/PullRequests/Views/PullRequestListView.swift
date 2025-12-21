import SwiftUI

struct PullRequestListView: View {
    @State private var container: PullRequestListContainer
    private let onLogout: () async -> Void
    
    init(container: PullRequestListContainer, onLogout: @escaping () async -> Void) {
        _container = State(wrappedValue: container)
        self.onLogout = onLogout
    }
    
    var body: some View {
        Group {
            switch container.loadingState {
            case .idle, .loading:
                LoadingView()
            case .loaded(let prs):
                if prs.isEmpty {
                    ContentUnavailableView(
                        "No Pull Requests",
                        systemImage: "checkmark.circle",
                        description: Text("You have no pull requests awaiting your review.")
                    )
                } else {
                    List(prs) { pr in
                        PullRequestRow(pullRequest: pr)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                container.openPR(url: pr.htmlURL)
                            }
                    }
                }
            case .failed(let error):
                ErrorView(error: error) {
                    Task {
                        await container.retry()
                    }
                }
            }
        }
        .navigationTitle("Review Requests")
        .task {
            if case .idle = container.loadingState {
                await container.loadPullRequests()
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: {
                    Task {
                        await onLogout()
                    }
                }) {
                    Label("Logout", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        }
    }
}

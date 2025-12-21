import SwiftUI

struct PullRequestListView: View {
    @State private var container: PullRequestListContainer
    
    init(container: PullRequestListContainer) {
        _container = State(wrappedValue: container)
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
    }
}

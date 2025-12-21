import AppKit
import Foundation
import Observation

@Observable
@MainActor
final class PullRequestListContainer {
    private(set) var loadingState: LoadingState<[PullRequest]> = .idle

    private let githubAPI: GitHubAPI
    private let credentialStorage: CredentialStorage
    private let openURL: (URL) -> Void

    init(
        githubAPI: GitHubAPI,
        credentialStorage: CredentialStorage,
        openURL: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) }
    ) {
        self.githubAPI = githubAPI
        self.credentialStorage = credentialStorage
        self.openURL = openURL
    }

    func loadPullRequests() async {
        loadingState = .loading

        do {
            guard let credentials = try await credentialStorage.retrieve() else {
                loadingState = .failed(APIError.unauthorized)
                return
            }

            let pullRequests = try await githubAPI.fetchReviewRequests(credentials: credentials)
            loadingState = .loaded(pullRequests)
        } catch let error as APIError {
            loadingState = .failed(error)
        } catch {
            loadingState = .failed(APIError.unknown(error))
        }
    }

    func retry() async {
        await loadPullRequests()
    }

    func openPR(url: URL) {
        openURL(url)
    }
}

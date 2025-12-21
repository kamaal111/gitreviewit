import Foundation

@testable import GitReviewItApp

/// Mock implementation of GitHubAPI for testing
/// Allows pre-configuring responses without making actual network calls
@MainActor
final class MockGitHubAPI: GitHubAPI {
    // MARK: - Configuration

    /// User to return from fetchUser
    var userToReturn: AuthenticatedUser?

    /// Pull requests to return from fetchReviewRequests
    var pullRequestsToReturn: [PullRequest] = []

    /// Error to throw from fetchUser
    var fetchUserErrorToThrow: Error?

    /// Error to throw from fetchReviewRequests
    var fetchReviewRequestsErrorToThrow: Error?

    // MARK: - Captured Data

    /// Credentials passed to fetchUser
    private(set) var fetchUserCredentials: [GitHubCredentials] = []

    /// Credentials passed to fetchReviewRequests
    private(set) var fetchReviewRequestsCredentials: [GitHubCredentials] = []

    /// Count of how many times fetchUser was called
    var fetchUserCallCount: Int {
        fetchUserCredentials.count
    }

    /// Count of how many times fetchReviewRequests was called
    var fetchReviewRequestsCallCount: Int {
        fetchReviewRequestsCredentials.count
    }

    // MARK: - GitHubAPI Protocol

    func fetchUser(credentials: GitHubCredentials) async throws -> AuthenticatedUser {
        fetchUserCredentials.append(credentials)

        if let error = fetchUserErrorToThrow {
            throw error
        }

        guard let user = userToReturn else {
            // Default user if none configured
            return AuthenticatedUser(
                login: "testuser",
                name: "Test User",
                avatarURL: URL(string: "https://avatars.githubusercontent.com/u/1?v=4")
            )
        }

        return user
    }

    func fetchReviewRequests(credentials: GitHubCredentials) async throws -> [PullRequest] {
        fetchReviewRequestsCredentials.append(credentials)

        if let error = fetchReviewRequestsErrorToThrow {
            throw error
        }

        return pullRequestsToReturn
    }

    // MARK: - Test Helpers

    /// Reset all captured data and configuration
    func reset() {
        userToReturn = nil
        pullRequestsToReturn = []
        fetchUserErrorToThrow = nil
        fetchReviewRequestsErrorToThrow = nil
        fetchUserCredentials.removeAll()
        fetchReviewRequestsCredentials.removeAll()
    }

    /// Get the last credentials used for fetchUser
    var lastFetchUserCredentials: GitHubCredentials? {
        fetchUserCredentials.last
    }

    /// Get the last credentials used for fetchReviewRequests
    var lastFetchReviewRequestsCredentials: GitHubCredentials? {
        fetchReviewRequestsCredentials.last
    }

    /// Check if a specific base URL was used in any API call
    func didUseBaseURL(_ baseURL: String) -> Bool {
        let allCredentials = fetchUserCredentials + fetchReviewRequestsCredentials
        return allCredentials.contains { $0.baseURL == baseURL }
    }
}

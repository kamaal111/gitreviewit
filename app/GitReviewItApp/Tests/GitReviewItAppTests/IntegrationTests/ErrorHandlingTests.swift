import Foundation
import Testing

@testable import GitReviewItApp

/// Integration tests for error handling scenarios across the app.
@MainActor
struct ErrorHandlingTests {

    // MARK: - Test Helpers

    private func makeAuthContainer(
        mockAPI: MockGitHubAPI = MockGitHubAPI(),
        mockStorage: MockCredentialStorage = MockCredentialStorage()
    ) -> (AuthenticationContainer, MockGitHubAPI) {
        let container = AuthenticationContainer(
            githubAPI: mockAPI,
            credentialStorage: mockStorage
        )
        return (container, mockAPI)
    }

    private func makePRContainer(
        mockAPI: MockGitHubAPI = MockGitHubAPI(),
        mockStorage: MockCredentialStorage = MockCredentialStorage()
    ) -> (PullRequestListContainer, MockGitHubAPI, MockCredentialStorage) {
        let container = PullRequestListContainer(
            githubAPI: mockAPI,
            credentialStorage: mockStorage
        )
        return (container, mockAPI, mockStorage)
    }

    // MARK: - T082: Network Failure Error Display

    @Test
    func `Network failure shows network unreachable error`() async throws {
        // Arrange
        let (container, mockAPI) = makeAuthContainer()

        // Mock GitHubAPI to throw networkUnreachable directly or map it
        // We simulate what GitHubAPIClient would return
        mockAPI.fetchUserErrorToThrow = APIError.networkUnreachable

        // Act
        await container.validateAndSaveCredentials(token: "ghp_test")

        // Assert
        #expect(container.error == .networkUnreachable, "Should display network unreachable error")
    }

    // MARK: - T083: Rate Limit Error

    @Test
    func `Rate limit error displays reset time`() async throws {
        // Arrange
        let (container, mockAPI) = makeAuthContainer()

        let resetDate = Date().addingTimeInterval(3600)  // 1 hour later
        mockAPI.fetchUserErrorToThrow = APIError.rateLimitExceeded(resetAt: resetDate)

        // Act
        await container.validateAndSaveCredentials(token: "ghp_test")

        // Assert
        #expect(container.error == .rateLimitExceeded(resetAt: resetDate))

        // Check description (indirectly testing localizedDescription)
        let errorDescription = container.error?.localizedDescription ?? ""
        #expect(errorDescription.contains("rate limit"), "Description should mention rate limit")
    }

    // MARK: - T084: Invalid Response Error Handling

    @Test
    func `Invalid response handling displays correct error`() async throws {
        // Arrange
        let (container, mockAPI) = makeAuthContainer()

        mockAPI.fetchUserErrorToThrow = APIError.invalidResponse

        // Act
        await container.validateAndSaveCredentials(token: "ghp_test")

        // Assert
        #expect(container.error == .invalidResponse)
        #expect(container.error?.localizedDescription.contains("invalid response") == true)
    }

    // MARK: - T085: Retry Functionality

    @Test
    func `Retry functionality succeeds after transient error`() async throws {
        // Arrange
        let (container, mockAPI, mockStorage) = makePRContainer()

        // Pre-store valid token
        try await mockStorage.store(
            GitHubCredentials(token: "ghp_test", baseURL: "https://api.github.com"))

        // Setup success response
        let pr = PullRequest(
            repositoryOwner: "owner",
            repositoryName: "repo",
            number: 1,
            title: "Test PR",
            authorLogin: "user",
            authorAvatarURL: nil,
            updatedAt: Date(),
            htmlURL: URL(string: "https://github.com/owner/repo/pull/1")!
        )
        mockAPI.pullRequestsToReturn = [pr]

        // First attempt fails with server error (transient)
        mockAPI.fetchReviewRequestsErrorToThrow = APIError.serverError(statusCode: 500)

        // Act 1: Load fails
        await container.loadPullRequests()

        // Assert 1
        #expect(
            container.loadingState == .failed(.serverError(statusCode: 500)),
            "State should be failed with 500 error")

        // Setup success for retry (clear error)
        mockAPI.fetchReviewRequestsErrorToThrow = nil

        // Act 2: Retry
        await container.retry()

        // Assert 2
        #expect(
            container.loadingState == .loaded([pr]), "State should be loaded with PR after retry")
    }
}

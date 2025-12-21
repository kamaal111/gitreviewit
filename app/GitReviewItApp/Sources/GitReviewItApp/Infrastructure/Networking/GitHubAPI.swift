import Foundation

/// High-level abstraction for GitHub API operations.
/// Implementations handle authentication, request construction,
/// response parsing, and error mapping.
protocol GitHubAPI: Sendable {
    /// Fetches the authenticated user's GitHub profile
    ///
    /// - Parameter credentials: GitHub credentials (token + baseURL)
    /// - Returns: AuthenticatedUser with username and profile info
    /// - Throws: APIError if request fails or token is invalid
    func fetchUser(credentials: GitHubCredentials) async throws -> AuthenticatedUser

    /// Fetches pull requests where the authenticated user's review is requested
    ///
    /// - Parameter credentials: GitHub credentials (token + baseURL)
    /// - Returns: Array of PullRequest objects (may be empty)
    /// - Throws: APIError if request fails
    func fetchReviewRequests(credentials: GitHubCredentials) async throws -> [PullRequest]
}

// MARK: - GitHubAPIClient

/// Production implementation of GitHubAPI using HTTPClient
final class GitHubAPIClient: GitHubAPI {
    private let httpClient: HTTPClient
    private let decoder: JSONDecoder

    /// Initialize with an HTTPClient for network operations
    /// - Parameter httpClient: HTTPClient for making network requests
    init(httpClient: HTTPClient) {
        self.httpClient = httpClient
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: - GitHubAPI Methods

    func fetchUser(credentials: GitHubCredentials) async throws -> AuthenticatedUser {
        let baseURL = credentials.baseURL.trimmingSuffix("/")
        guard let url = URL(string: "\(baseURL)/user") else {
            throw APIError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(credentials.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        do {
            let (data, response) = try await httpClient.perform(request)

            guard (200...299).contains(response.statusCode) else {
                throw mapHTTPError(statusCode: response.statusCode, data: data, response: response)
            }

            return try decoder.decode(AuthenticatedUser.self, from: data)
        } catch let error as HTTPError {
            throw mapHTTPErrorToAPIError(error)
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.decodingError(error)
        }
    }

    func fetchReviewRequests(credentials: GitHubCredentials) async throws -> [PullRequest] {
        // First, fetch the authenticated user to get their username
        let user = try await fetchUser(credentials: credentials)

        // Build search query for PRs where this user's review is requested
        let query = "type:pr+state:open+review-requested:\(user.login)"
        let baseURL = credentials.baseURL.trimmingSuffix("/")
        guard var components = URLComponents(string: "\(baseURL)/search/issues") else {
            throw APIError.invalidResponse
        }
        components.queryItems = [URLQueryItem(name: "q", value: query)]

        guard let url = components.url else {
            throw APIError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(credentials.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        do {
            let (data, response) = try await httpClient.perform(request)

            guard (200...299).contains(response.statusCode) else {
                throw mapHTTPError(statusCode: response.statusCode, data: data, response: response)
            }

            let searchResponse = try decoder.decode(GitHubSearchResponse.self, from: data)
            return searchResponse.items
        } catch let error as HTTPError {
            throw mapHTTPErrorToAPIError(error)
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.decodingError(error)
        }
    }

    // MARK: - Helper Methods

    private func mapHTTPError(statusCode: Int, data: Data, response: HTTPURLResponse) -> APIError {
        switch statusCode {
        case 401:
            return .unauthorized
        case 403:
            // Check for rate limiting
            if let rateLimitReset = response.value(forHTTPHeaderField: "X-RateLimit-Reset"),
                let timestamp = TimeInterval(rateLimitReset)
            {
                let resetDate = Date(timeIntervalSince1970: timestamp)
                return .rateLimitExceeded(resetAt: resetDate)
            }
            return .rateLimitExceeded(resetAt: nil)
        case 404:
            return .notFound
        case 422:
            return .invalidResponse
        case 500...599:
            return .serverError(statusCode: statusCode)
        default:
            // Try to extract error message from response
            if let errorMessage = try? decoder.decode(GitHubErrorResponse.self, from: data) {
                return .httpError(statusCode: statusCode, message: errorMessage.message)
            }
            return .httpError(statusCode: statusCode, message: nil)
        }
    }

    private func mapHTTPErrorToAPIError(_ error: HTTPError) -> APIError {
        switch error {
        case .connectionFailed, .timeout, .dnsError:
            return .networkError(error)
        case .invalidResponse, .noData:
            return .invalidResponse
        case .cancelled:
            return .unknown(error)
        default:
            return .unknown(error)
        }
    }

    private func extractRepositoryInfo(from urlString: String) -> (owner: String, name: String)? {
        // Parse "https://api.github.com/repos/owner/repo"
        guard let url = URL(string: urlString) else { return nil }
        let components = url.pathComponents

        // Path components: ["", "repos", "owner", "repo"]
        guard components.count >= 4,
            components[1] == "repos"
        else {
            return nil
        }

        return (owner: components[2], name: components[3])
    }
}

// MARK: - Response Models

private struct TokenResponse: Decodable {
    let access_token: String
    let token_type: String
    let scope: String
}

private struct OAuthErrorResponse: Decodable {
    let error: String
    let error_description: String
}

private struct GitHubErrorResponse: Decodable {
    let message: String
}

private struct GitHubSearchResponse: Decodable {
    let items: [PullRequest]
}

private struct SearchIssuesResponse: Decodable {
    let total_count: Int
    let incomplete_results: Bool
    let items: [SearchIssueItem]
}

private struct SearchIssueItem: Decodable {
    let number: Int
    let title: String
    let html_url: URL
    let updated_at: Date
    let state: String
    let user: SearchUser
    let repository_url: String
}

private struct SearchUser: Decodable {
    let login: String
    let avatar_url: URL?
}

// MARK: - String Extension

extension String {
    /// Removes trailing slash from string if present
    fileprivate func trimmingSuffix(_ suffix: String) -> String {
        guard hasSuffix(suffix) else { return self }
        return String(dropLast(suffix.count))
    }
}

# API Contracts: Infrastructure Layer

**Feature**: 001-github-pr-viewer  
**Date**: December 20, 2025  
**Status**: Complete

This document defines all protocol boundaries for the infrastructure layer, enabling dependency injection and testing.

---

## HTTPClient Protocol

**Purpose**: Abstraction over URLSession for HTTP request/response handling.

**Responsibilities**:
- Execute HTTP requests
- Return response data and metadata
- Propagate network errors

**Protocol Definition**:
```swift
/// Abstraction for HTTP networking. Implementations should handle
/// network requests and return response data with HTTP metadata.
protocol HTTPClient: Sendable {
    /// Executes an HTTP request and returns response data with HTTP metadata.
    ///
    /// - Parameter request: The URLRequest to execute
    /// - Returns: Tuple of response data and HTTPURLResponse
    /// - Throws: URLError for network failures, or HTTPError for invalid responses
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// Errors specific to HTTP operations
enum HTTPError: Error {
    case invalidResponse  // Response was not HTTPURLResponse
}
```

**Implementations**:
- Production: `URLSessionHTTPClient` (wraps URLSession)
- Testing: `MockHTTPClient` (returns fixture data)

**Example Usage**:
```swift
let request = URLRequest(url: url)
let (data, response) = try await httpClient.data(for: request)
guard response.statusCode == 200 else {
    throw APIError.invalidResponse(statusCode: response.statusCode)
}
```

---

## CredentialStorage Protocol

**Purpose**: Abstraction for secure credential persistence (Keychain).

**Responsibilities**:
- Save GitHub credentials (token + baseURL) securely
- Retrieve stored credentials
- Delete credentials on logout

**Protocol Definition**:
```swift
/// Abstraction for secure credential storage. Implementations should
/// store credentials using platform-appropriate secure storage (e.g., Keychain).
protocol CredentialStorage: Sendable {
    /// Saves credentials to secure storage
    ///
    /// - Parameter credentials: The GitHubCredentials to save (token + baseURL)
    /// - Throws: CredentialStorageError if save fails
    func saveCredentials(_ credentials: GitHubCredentials) async throws
    
    /// Loads the stored credentials from secure storage
    ///
    /// - Returns: The GitHubCredentials, or nil if no credentials are stored
    /// - Throws: CredentialStorageError if load fails (excluding "not found" case)
    func loadCredentials() async throws -> GitHubCredentials?
    
    /// Deletes the stored credentials from secure storage
    ///
    /// - Throws: CredentialStorageError if delete fails
    func deleteCredentials() async throws
}

/// Errors specific to credential storage operations
enum CredentialStorageError: Error, LocalizedError {
    case saveFailed(OSStatus)
    case loadFailed(OSStatus)
    case deleteFailed(OSStatus)
    case notFound
    
    var errorDescription: String? {
        switch self {
        case .saveFailed(let status):
            return "Failed to save credentials to keychain (status: \(status))"
        case .loadFailed(let status):
            return "Failed to load credentials from keychain (status: \(status))"
        case .deleteFailed(let status):
            return "Failed to delete credentials from keychain (status: \(status))"
        case .notFound:
            return "No credentials found in keychain"
        }
    }
}
```

**Implementations**:
- Production: `KeychainCredentialStorage` (uses Security framework, stores as JSON)
- Testing: `MockCredentialStorage` (in-memory dictionary)

**Example Usage**:
```swift
// Save credentials after PAT validation
let credentials = GitHubCredentials(token: "ghp_abc123...", baseURL: "https://api.github.com")
try await credentialStorage.saveCredentials(credentials)

// Load credentials at app launch
if let credentials = try await credentialStorage.loadCredentials() {
    // User is authenticated
}

// Delete credentials on logout
try await credentialStorage.deleteCredentials()
```

---

## GitHubAPI Protocol

**Purpose**: High-level abstraction for GitHub API operations.

**Responsibilities**:
- Fetch authenticated user info
- Fetch pull requests awaiting review
- Support GitHub Enterprise via configurable base URL
- Map HTTP responses to domain models
- Map HTTP errors to APIError

**Protocol Definition**:
```swift
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
```

**Implementations**:
- Production: `GitHubAPIClient` (constructs requests, parses JSON, supports GHE)
- Testing: `MockGitHubAPI` (returns fixture data without network calls)

**Example Usage**:
```swift
// Create credentials with PAT and base URL
let credentials = GitHubCredentials(
    token: "ghp_abc123...",
    baseURL: "https://api.github.com"  // or https://github.company.com/api/v3 for GHE
)

// Fetch user
let user = try await githubAPI.fetchUser(credentials: credentials)

// Fetch PRs
let prs = try await githubAPI.fetchReviewRequests(credentials: credentials)
```

---

## Request/Response Structures

### Get User Request

**Endpoint**: `GET {baseURL}/user`
- Standard GitHub: `https://api.github.com/user`
- GitHub Enterprise: `https://github.company.com/api/v3/user`

**Headers**:
```
Authorization: Bearer ghp_abc123...
Accept: application/vnd.github+json
X-GitHub-Api-Version: 2022-11-28
```

**Success Response (200)**:
```json
{
  "login": "octocat",
  "id": 1,
  "name": "The Octocat",
  "avatar_url": "https://avatars.githubusercontent.com/u/1?v=4",
  "type": "User",
  ...
}
```

**Error Response (401)**:
```json
{
  "message": "Bad credentials",
  "documentation_url": "https://docs.github.com/rest"
}
```

---

### Search Pull Requests Request

**Endpoint**: `GET {baseURL}/search/issues`
- Standard GitHub: `https://api.github.com/search/issues`
- GitHub Enterprise: `https://github.company.com/api/v3/search/issues`

**Query Parameters**:
```
q=type:pr+state:open+review-requested:octocat
sort=updated
order=desc
per_page=50
```

**Headers**:
```
Authorization: Bearer ghp_abc123...
Accept: application/vnd.github+json
X-GitHub-Api-Version: 2022-11-28
```

**Success Response (200)**:
```json
{
  "total_count": 2,
  "incomplete_results": false,
  "items": [
    {
      "number": 123,
      "title": "Add feature X",
      "html_url": "https://github.com/owner/repo/pull/123",
      "updated_at": "2025-12-20T10:30:00Z",
      "state": "open",
      "user": {
        "login": "author-username",
        "avatar_url": "https://avatars.githubusercontent.com/u/456?v=4"
      },
      "repository_url": "https://api.github.com/repos/owner/repo"
    }
  ]
}
```

**Rate Limit Response (403)**:
```json
{
  "message": "API rate limit exceeded for user ID 1.",
  "documentation_url": "https://docs.github.com/rest/overview/resources-in-the-rest-api#rate-limiting"
}
```

**Rate Limit Headers**:
```
X-RateLimit-Limit: 60
X-RateLimit-Remaining: 0
X-RateLimit-Reset: 1703080800
```

---

## Error Mapping Strategy

| HTTP Status | Headers/Body Indicators | Maps To APIError |
|-------------|-------------------------|------------------|
| N/A (URLError.notConnectedToInternet) | - | `.networkUnavailable` |
| 401 | - | `.unauthorized` |
| 403 | `X-RateLimit-Remaining: 0` | `.rateLimited(resetDate: ...)` |
| 422 | - | `.invalidResponse(statusCode: 422)` |
| 500-599 | - | `.serverError(statusCode: ...)` |
| 200-299 | Invalid JSON structure | `.invalidResponse(statusCode: ...)` |
| Other | - | `.unknown(error)` |

**Implementation Note**:
Parse `X-RateLimit-Reset` header (Unix timestamp) and convert to Date for `.rateLimited` case.

---

## Summary

All infrastructure protocol boundaries are defined with clear responsibilities, method signatures, and error cases. Implementations are separated into production (using system frameworks) and testing (using mocks/fixtures). Request/response formats are documented for all GitHub API interactions.

Ready to proceed to quickstart.md generation.

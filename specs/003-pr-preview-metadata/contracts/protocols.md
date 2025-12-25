# API Contracts: Preview Metadata

**Feature**: Pull Request Preview Metadata  
**Date**: December 25, 2025

## Overview

This document defines the protocol contracts and API interfaces for fetching and managing PR preview metadata.

---

## GitHubAPI Protocol (Extended)

**Existing Methods** (No Changes):
- `func fetchUser(credentials: GitHubCredentials) async throws -> AuthenticatedUser`
- `func fetchTeams(credentials: GitHubCredentials) async throws -> [Team]`
- `func fetchReviewRequests(credentials: GitHubCredentials) async throws -> [PullRequest]`

**New Method**:

```swift
/// Fetches detailed information for a specific pull request
///
/// - Parameters:
///   - owner: Repository owner username
///   - repo: Repository name
///   - number: PR number
///   - credentials: GitHub credentials (token + baseURL)
/// - Returns: PRPreviewMetadata with change stats and reviewers
/// - Throws: APIError if request fails or PR not found
func fetchPRDetails(
    owner: String,
    repo: String,
    number: Int,
    credentials: GitHubCredentials
) async throws -> PRPreviewMetadata
```

**Error Cases**:
- `APIError.unauthorized`: Invalid token (401)
- `APIError.notFound`: PR doesn't exist (404)
- `APIError.forbidden`: No permission to view PR (403)
- `APIError.rateLimited(resetDate)`: Rate limit exceeded (403 with rate limit headers)
- `APIError.serverError`: GitHub server error (5xx)
- `APIError.networkUnavailable`: Network error
- `APIError.decodingError(Error)`: Response parsing failed

---

## Request/Response Structures

### Get PR Details Request

**Endpoint**: `GET {baseURL}/repos/{owner}/{repo}/pulls/{number}`

**Example**: `GET https://api.github.com/repos/apple/swift/pulls/12345`

**Headers**:
```
Authorization: Bearer ghp_abc123...
Accept: application/vnd.github+json
X-GitHub-Api-Version: 2022-11-28
```

**Parameters**:
- `owner`: Repository owner (e.g., "apple")
- `repo`: Repository name (e.g., "swift")
- `number`: PR number (e.g., 12345)

---

### Get PR Details Response (Success 200)

**Relevant Fields** (response includes 100+ fields; we use these):

```json
{
  "url": "https://api.github.com/repos/apple/swift/pulls/12345",
  "number": 12345,
  "state": "open",
  "title": "Add distributed actor isolation",
  "additions": 145,
  "deletions": 23,
  "changed_files": 7,
  "commits": 3,
  "comments": 5,
  "review_comments": 12,
  "requested_reviewers": [
    {
      "login": "octocat",
      "id": 1,
      "avatar_url": "https://avatars.githubusercontent.com/u/1?v=4",
      "type": "User"
    }
  ],
  "requested_teams": [
    {
      "name": "Core Team",
      "slug": "core-team",
      "id": 2345
    }
  ],
  "labels": [
    {
      "name": "bug",
      "color": "d73a4a",
      "description": "Something isn't working"
    }
  ],
  ...
}
```

**Fields Used**:
- `additions` (int): Lines added
- `deletions` (int): Lines deleted
- `changed_files` (int): Files modified
- `requested_reviewers` (array): Users requested to review
- `requested_teams` (array): Teams requested to review (future enhancement)

---

### Error Responses

**401 Unauthorized**:
```json
{
  "message": "Bad credentials",
  "documentation_url": "https://docs.github.com/rest"
}
```

**404 Not Found**:
```json
{
  "message": "Not Found",
  "documentation_url": "https://docs.github.com/rest/pulls/pulls#get-a-pull-request"
}
```

**403 Forbidden (Rate Limit)**:
```json
{
  "message": "API rate limit exceeded for user ID 123456.",
  "documentation_url": "https://docs.github.com/rest/overview/resources-in-the-rest-api#rate-limiting"
}
```

**Headers**:
```
X-RateLimit-Limit: 5000
X-RateLimit-Remaining: 0
X-RateLimit-Reset: 1703095200
X-RateLimit-Used: 5000
```

**403 Forbidden (No Permission)**:
```json
{
  "message": "Resource not accessible by integration",
  "documentation_url": "https://docs.github.com/rest"
}
```

---

## Decoding Structures

### PRDetailsResponse

**Purpose**: Decode GitHub PR Details API response

```swift
struct PRDetailsResponse: Decodable {
    let additions: Int
    let deletions: Int
    let changed_files: Int
    let requested_reviewers: [ReviewerResponse]
    let requested_teams: [TeamResponse]
    
    struct ReviewerResponse: Decodable {
        let login: String
        let avatar_url: URL?
    }
    
    struct TeamResponse: Decodable {
        let name: String
        let slug: String
    }
}
```

**Mapping to Domain Model**:
```swift
func mapToPRPreviewMetadata(_ response: PRDetailsResponse) -> PRPreviewMetadata {
    PRPreviewMetadata(
        additions: response.additions,
        deletions: response.deletions,
        changedFiles: response.changed_files,
        requestedReviewers: response.requested_reviewers.map { reviewer in
            Reviewer(login: reviewer.login, avatarURL: reviewer.avatar_url)
        }
    )
}
```

---

## PreviewMetadataService Protocol

**Purpose**: High-level service for enriching PRs with preview metadata

```swift
/// Service responsible for enriching PRs with preview metadata
protocol PreviewMetadataService: Sendable {
    /// Enriches a list of PRs with preview metadata
    ///
    /// Fetches metadata for each PR in parallel. Individual failures are isolated
    /// and don't affect other PRs. Failed PRs retain nil previewMetadata.
    ///
    /// - Parameters:
    ///   - pullRequests: PRs to enrich (must be mutable binding)
    ///   - credentials: GitHub credentials for API calls
    ///   - onProgress: Optional callback for progress updates (PR ID + metadata or error)
    /// - Returns: Array of enriched PRs (same order as input)
    func enrichPullRequests(
        _ pullRequests: [PullRequest],
        credentials: GitHubCredentials,
        onProgress: ((String, Result<PRPreviewMetadata, Error>) -> Void)?
    ) async -> [PullRequest]
}
```

**Implementation**: `DefaultPreviewMetadataService`

```swift
final class DefaultPreviewMetadataService: PreviewMetadataService {
    private let githubAPI: GitHubAPI
    private var cache: [String: PRPreviewMetadata] = [:]
    
    init(githubAPI: GitHubAPI) {
        self.githubAPI = githubAPI
    }
    
    func enrichPullRequests(
        _ pullRequests: [PullRequest],
        credentials: GitHubCredentials,
        onProgress: ((String, Result<PRPreviewMetadata, Error>) -> Void)?
    ) async -> [PullRequest] {
        // Check cache first
        // Fetch missing metadata in parallel
        // Update PRs with results
        // Return enriched PRs
    }
    
    func clearCache() {
        cache.removeAll()
    }
}
```

---

## MockGitHubAPI Extension

**Purpose**: Add mock support for `fetchPRDetails` in tests

```swift
extension MockGitHubAPI {
    /// Preview metadata to return from fetchPRDetails, keyed by "{owner}/{repo}#{number}"
    var prDetailsToReturn: [String: PRPreviewMetadata] = [:]
    
    /// Error to throw from fetchPRDetails, keyed by "{owner}/{repo}#{number}"
    var fetchPRDetailsErrorsToThrow: [String: Error] = [:]
    
    /// Captured fetchPRDetails calls (for verification)
    private(set) var fetchPRDetailsCallCount = 0
    private(set) var fetchPRDetailsCalls: [(owner: String, repo: String, number: Int)] = []
    
    func fetchPRDetails(
        owner: String,
        repo: String,
        number: Int,
        credentials: GitHubCredentials
    ) async throws -> PRPreviewMetadata {
        fetchPRDetailsCallCount += 1
        fetchPRDetailsCalls.append((owner, repo, number))
        
        let key = "\(owner)/\(repo)#\(number)"
        
        if let error = fetchPRDetailsErrorsToThrow[key] {
            throw error
        }
        
        guard let metadata = prDetailsToReturn[key] else {
            throw APIError.notFound
        }
        
        return metadata
    }
}
```

**Usage in Tests**:
```swift
mockGitHubAPI.prDetailsToReturn["apple/swift#12345"] = PRPreviewMetadata(
    additions: 145,
    deletions: 23,
    changedFiles: 7,
    requestedReviewers: [
        Reviewer(login: "reviewer1", avatarURL: nil)
    ]
)
```

---

## Example Usage

### Fetching PR Details (GitHubAPIClient)

```swift
func fetchPRDetails(
    owner: String,
    repo: String,
    number: Int,
    credentials: GitHubCredentials
) async throws -> PRPreviewMetadata {
    let baseURL = credentials.baseURL.trimmingSuffix("/")
    guard let url = URL(string: "\(baseURL)/repos/\(owner)/\(repo)/pulls/\(number)") else {
        throw APIError.invalidResponse
    }
    
    var request = URLRequest(url: url)
    request.setValue("Bearer \(credentials.token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
    
    let (data, response) = try await httpClient.perform(request)
    
    guard (200...299).contains(response.statusCode) else {
        throw mapHTTPError(statusCode: response.statusCode, data: data, response: response)
    }
    
    let prDetails = try decoder.decode(PRDetailsResponse.self, from: data)
    return mapToPRPreviewMetadata(prDetails)
}
```

---

### Enriching PRs (PullRequestListContainer)

```swift
func enrichPreviewMetadata() async {
    guard case .loaded(let prs) = loadingState else { return }
    guard let credentials = try? await credentialStorage.retrieve() else { return }
    
    isEnrichingMetadata = true
    defer { isEnrichingMetadata = false }
    
    await withTaskGroup(of: (Int, PRPreviewMetadata?).self) { group in
        for (index, pr) in prs.enumerated() {
            group.addTask {
                do {
                    let metadata = try await self.githubAPI.fetchPRDetails(
                        owner: pr.repositoryOwner,
                        repo: pr.repositoryName,
                        number: pr.number,
                        credentials: credentials
                    )
                    return (index, metadata)
                } catch {
                    // Log error (OSLog) but don't fail
                    return (index, nil)
                }
            }
        }
        
        var enrichedPRs = prs
        for await (index, metadata) in group {
            enrichedPRs[index].previewMetadata = metadata
        }
        
        loadingState = .loaded(enrichedPRs)
    }
}
```

---

## Rate Limiting Handling

**Detection**: Check for 403 status + rate limit headers

```swift
if response.statusCode == 403,
   let rateLimitResetString = response.headers["X-RateLimit-Reset"],
   let rateLimitReset = Int(rateLimitResetString) {
    let resetDate = Date(timeIntervalSince1970: TimeInterval(rateLimitReset))
    throw APIError.rateLimited(resetAt: resetDate)
}
```

**Behavior**: Stop further enrichment attempts until rate limit resets. Already-enriched PRs retain their metadata.

---

## Error Isolation Strategy

**Principle**: Individual PR enrichment failures must not affect other PRs or the overall list.

**Implementation**:
```swift
// In TaskGroup:
group.addTask {
    do {
        let metadata = try await fetchPRDetails(...)
        return .success(metadata)
    } catch {
        // Log error but return nil instead of throwing
        logger.error("Failed to fetch metadata for \(pr.id): \(error)")
        return .failure(error)
    }
}

// Handle results:
for await result in group {
    switch result {
    case .success(let metadata):
        pr.previewMetadata = metadata
    case .failure:
        pr.previewMetadata = nil  // Leave as unavailable
    }
}
```

**User Experience**: PRs with failed enrichment display "—" for unavailable fields but remain visible and functional.

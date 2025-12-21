# Developer Quickstart Guide

**Feature**: 001-github-pr-viewer  
**Date**: December 21, 2025  
**Target Audience**: Developers implementing the GitHub PR Review Viewer MVP

## Prerequisites

- Xcode 16.0+ (for Swift 6.0 support)
- macOS 15.0+ (for running the app)
- GitHub account (for testing API)
- GitHub Personal Access Token (PAT) (Classic or Fine-grained)

---

## Personal Access Token Setup

This app uses Personal Access Tokens (PAT) for authentication, which supports both GitHub.com and GitHub Enterprise instances.

### Steps:

1. Go to https://github.com/settings/tokens
2. Click "Generate new token" (Classic recommended for MVP simplicity, or Fine-grained)
3. **Scopes Required**:
   - `repo` (Full control of private repositories) - needed to read PRs and user info
   - `read:org` (Read org and team membership) - needed for team review requests
   - `user` (Read all user profile data)
4. Copy your generated token
5. (Optional) For GitHub Enterprise, ensure you know your API base URL (e.g., `https://github.company.com/api/v3`)

---

## Project Structure Overview

```
GitReviewIt/
├── Features/
│   ├── Authentication/
│   │   ├── Views/          # LoginView
│   │   ├── State/          # AuthenticationContainer
│   │   └── Models/         # GitHubCredentials, AuthenticatedUser, Team
│   └── PullRequests/
│       ├── Views/          # PullRequestListView, PullRequestRow
│       ├── State/          # PullRequestListContainer
│       └── Models/         # PullRequest
├── Shared/
│   ├── Views/              # LoadingView, ErrorView
│   ├── Models/             # APIError, LoadingState
│   └── Utilities/          # URLValidator
├── Infrastructure/
│   ├── Networking/         # HTTPClient, GitHubAPI
│   └── Storage/            # CredentialStorage (Keychain)
├── GitReviewItApp.swift    # App entry point
└── ContentView.swift       # Root view with navigation

GitReviewItTests/
├── IntegrationTests/       # Full-flow tests
├── TestDoubles/            # Mocks for protocols
└── Fixtures/               # JSON response fixtures
```

---

## Implementation Sequence

Follow this order to build the app incrementally with tests at each step:

### 1. Infrastructure Layer (Bottom-Up)

**a. HTTPClient Protocol + Implementation**
- Define `HTTPClient` protocol in `Infrastructure/Networking/HTTPClient.swift`
- Implement `URLSessionHTTPClient` (wraps URLSession)
- Create `MockHTTPClient` in tests with fixture loading

**b. CredentialStorage Protocol + Implementation**
- Define `CredentialStorage` protocol in `Infrastructure/Storage/CredentialStorage.swift`
- Implement `KeychainCredentialStorage` (uses Security framework)
- Create `MockCredentialStorage` in tests (in-memory)

**c. GitHubAPI Protocol + Implementation**
- Define `GitHubAPI` protocol in `Infrastructure/Networking/GitHubAPI.swift`
- Implement `GitHubAPIClient` (uses HTTPClient for requests)
- Create `MockGitHubAPI` in tests

### 2. Domain Models

**a. Error Types**
- `APIError` enum in `Shared/Models/APIError.swift`
- `LoadingState<T>` enum in `Shared/Models/LoadingState.swift`

**b. Domain Entities**
- `GitHubCredentials` struct in `Features/Authentication/Models/GitHubCredentials.swift`
- `AuthenticatedUser` struct in `Features/Authentication/Models/AuthenticatedUser.swift`
- `PullRequest` struct in `Features/PullRequests/Models/PullRequest.swift`

### 3. State Containers

**a. AuthenticationContainer**
- Create `@Observable` class in `Features/Authentication/State/AuthenticationContainer.swift`
- Implement methods: `validateAndSaveCredentials(token:baseURL:)`, `checkExistingCredentials()`, `logout()`
- Add integration tests in `AuthenticationFlowTests`

**b. PullRequestListContainer**
- Create `@Observable` class in `Features/PullRequests/State/PullRequestListContainer.swift`
- Implement methods: `loadPullRequests()`, `retry()`, `openPR(url:)`
- Add integration tests in `PullRequestListTests`

### 4. Views (Top-Down)

**a. Shared Views**
- `LoadingView` in `Shared/Views/LoadingView.swift` (spinner + message)
- `ErrorView` in `Shared/Views/ErrorView.swift` (error message + retry button)

**b. Authentication Views**
- `LoginView` in `Features/Authentication/Views/LoginView.swift`
  - Shows PAT input field and optional Base URL field
  - Owns AuthenticationContainer via @State
  - Calls `validateAndSaveCredentials()` on button tap

**c. Pull Request Views**
- `PullRequestRow` in `Features/PullRequests/Views/PullRequestRow.swift`
  - Displays single PR (repo, title, author, time)
- `PullRequestListView` in `Features/PullRequests/Views/PullRequestListView.swift`
  - Owns PullRequestListContainer via @State
  - Shows loading/error/empty/loaded states
  - Calls `loadPullRequests()` in .task modifier

**d. Root Navigation**
- Update `ContentView.swift` to switch between LoginView and PullRequestListView
- Check credentials at launch via `checkExistingCredentials()`

### 5. App Configuration

**a. Info.plist Updates**
- Minimal updates needed (URL schemes removed as OAuth is not used)

---

## Key Implementation Patterns

### Pattern 1: Protocol Injection for Testability

```swift
// Container owns protocols, not concrete types
@MainActor
@Observable
final class AuthenticationContainer {
    private let githubAPI: GitHubAPI
    private let credentialStorage: CredentialStorage
    
    init(githubAPI: GitHubAPI, credentialStorage: CredentialStorage) {
        self.githubAPI = githubAPI
        self.credentialStorage = credentialStorage
    }
}

// Production usage
let container = AuthenticationContainer(
    githubAPI: GitHubAPIClient(httpClient: URLSessionHTTPClient()),
    credentialStorage: KeychainCredentialStorage()
)

// Test usage
let container = AuthenticationContainer(
    githubAPI: MockGitHubAPI(fixtures: ...),
    credentialStorage: MockCredentialStorage()
)
```

### Pattern 2: View Owns State via @State

```swift
struct PullRequestListView: View {
    @State private var container: PullRequestListContainer
    
    init(githubAPI: GitHubAPI, credentialStorage: CredentialStorage) {
        // Inject dependencies, @State owns lifecycle
        _container = State(initialValue: PullRequestListContainer(
            githubAPI: githubAPI,
            credentialStorage: credentialStorage
        ))
    }
    
    var body: some View {
        // View reads container state and sends intent
        List(container.pullRequests) { pr in
            PullRequestRow(pr: pr)
        }
        .task {
            await container.loadPullRequests()
        }
    }
}
```

### Pattern 3: Intent-Based State Container Methods

```swift
// ❌ Bad: Imperative setters
func setPullRequests(_ prs: [PullRequest]) { ... }
func setLoading(_ loading: Bool) { ... }

// ✅ Good: Intent-based methods
func loadPullRequests() async { ... }
func retry() async { ... }
func validateAndSaveCredentials(token: String, baseURL: String) async { ... }
```

### Pattern 4: LoadingState for Async Operations

```swift
@MainActor
@Observable
final class PullRequestListContainer {
    private(set) var loadingState: LoadingState<[PullRequest]> = .idle
    
    func loadPullRequests() async {
        loadingState = .loading
        do {
            let prs = try await githubAPI.fetchReviewRequests(credentials: ...)
            loadingState = .loaded(prs)
        } catch let error as APIError {
            loadingState = .failed(error)
        }
    }
}

// View uses switch to render state
var body: some View {
    switch container.loadingState {
    case .idle:
        Text("Tap to load")
    case .loading:
        LoadingView()
    case .loaded(let prs):
        List(prs) { pr in PullRequestRow(pr: pr) }
    case .failed(let error):
        ErrorView(error: error, retry: container.retry)
    }
}
```

---

## Testing Strategy

### Integration Test Example

```swift
final class AuthenticationFlowTests: XCTestCase {
    func testSuccessfulLoginFlow() async throws {
        // Arrange: Set up mocks with fixtures
        let mockHTTP = MockHTTPClient()
        mockHTTP.stubResponse(for: "/user", fixture: "user-response.json")
        
        let credentialStorage = MockCredentialStorage()
        let githubAPI = GitHubAPIClient(httpClient: mockHTTP)
        
        let container = AuthenticationContainer(
            githubAPI: githubAPI,
            credentialStorage: credentialStorage
        )
        
        // Act: Execute Login flow
        await container.validateAndSaveCredentials(token: "test_token")
        
        // Assert: Verify state transitions and token storage
        XCTAssertTrue(container.authState.isAuthenticated)
        XCTAssertNotNil(try await credentialStorage.retrieve())
        XCTAssertEqual(container.authState.user?.login, "octocat")
    }
    
    func testTokenExpirationHandling() async throws {
        // Arrange: Mock returns 401 for PR fetch
        let mockHTTP = MockHTTPClient()
        mockHTTP.stubResponse(for: "/search/issues", statusCode: 401, body: Data())
        
        let credentialStorage = MockCredentialStorage()
        try await credentialStorage.store(GitHubCredentials(token: "expired", baseURL: "https://api.github.com"))
        
        let githubAPI = GitHubAPIClient(httpClient: mockHTTP)
        let container = PullRequestListContainer(githubAPI: githubAPI, credentialStorage: credentialStorage)
        
        // Act: Load PRs with expired token
        await container.loadPullRequests()
        
        // Assert: Should fail with .unauthorized
        guard case .failed(let error) = container.loadingState,
              case .unauthorized = error else {
            XCTFail("Expected .unauthorized error")
            return
        }
        
        // Token should be cleared (handled by AuthenticationContainer in real app, 
        // or by container detecting 401 and notifying parent)
    }
}
```

### Fixture Files (GitReviewItTests/Fixtures/)

**user-response.json**:
```json
{
  "login": "octocat",
  "name": "The Octocat",
  "avatar_url": "https://avatars.githubusercontent.com/u/1?v=4"
}
```

**prs-response.json**:
```json
{
  "total_count": 1,
  "items": [
    {
      "number": 123,
      "title": "Add feature X",
      "html_url": "https://github.com/owner/repo/pull/123",
      "updated_at": "2025-12-20T10:30:00Z",
      "user": {
        "login": "author",
        "avatar_url": "https://avatars.githubusercontent.com/u/2?v=4"
      },
      "repository_url": "https://api.github.com/repos/owner/repo"
    }
  ]
}
```

---

## Running the App

1. Open `GitReviewIt.xcodeproj` in Xcode
2. Select the GitReviewIt scheme and target macOS
3. Build and run (Cmd+R)
4. Enter your GitHub Personal Access Token (and custom Base URL if using GHE)
5. Click "Sign In" to validate token and load profile
6. View your PRs awaiting review

---

## Running Tests

```bash
# Run all tests
cd app && just test
# OR
cd app && xcodebuild test -project GitReviewIt.xcodeproj -scheme GitReviewIt -destination 'platform=macOS'

# Or in Xcode: Cmd+U
```

---

## Common Pitfalls & Solutions

### Problem: Keychain operations fail with errSecItemNotFound

**Solution**: This is expected when no token exists. Don't treat it as an error—return `nil` from `retrieve()`.

```swift
let status = SecItemCopyMatching(query as CFDictionary, &result)
if status == errSecItemNotFound {
    return nil  // Not an error, just no token
}
```

### Problem: GitHub API returns 422 for search query

**Solution**: Ensure query parameters are properly URL-encoded. Use `URLComponents` to build the URL safely.

```swift
var components = URLComponents(string: "https://api.github.com/search/issues")!
components.queryItems = [
    URLQueryItem(name: "q", value: "type:pr state:open review-requested:\(username)"),
    URLQueryItem(name: "sort", value: "updated"),
    URLQueryItem(name: "order", value: "desc")
]
let url = components.url!
```

### Problem: GitHub Enterprise URL issues

**Solution**: Ensure the Base URL provided by the user does not have a trailing slash and includes the API path (e.g. `/api/v3` for GHE). The app should handle trimming trailing slashes, but correct path suffix is required.

### Problem: SwiftUI view not updating when state changes

**Solution**: Ensure container is `@Observable` and view uses `@State`. Check that state properties are accessed in the view body.

```swift
@Observable  // ← Must be present
final class MyContainer { ... }

struct MyView: View {
    @State private var container: MyContainer  // ← Use @State
    
    var body: some View {
        Text(container.someProperty)  // ← Accessing property triggers observation
    }
}
```

---

## Next Steps After MVP

- [ ] Add pull-to-refresh gesture
- [ ] Cache avatar images
- [ ] Display PR description and labels
- [ ] Add filtering/sorting options
- [ ] Add multi-account support
- [ ] Expand to iOS and iPadOS

---

## Resources

- [GitHub REST API Documentation](https://docs.github.com/en/rest)
- [SwiftUI Observation Documentation](https://developer.apple.com/documentation/observation)
- [Keychain Services Documentation](https://developer.apple.com/documentation/security/keychain_services)

---

**Last Updated**: December 21, 2025  
**Maintainer**: Development Team

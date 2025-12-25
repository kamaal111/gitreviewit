# Research: Pull Request Preview Metadata

**Feature**: Pull Request Preview Metadata  
**Date**: December 25, 2025  
**Status**: Complete

## Executive Summary

Preview metadata fields have varying data source requirements:
- **Already available** from Search Issues API: `comments` count, `labels` array
- **Requires additional API calls**: `additions`, `deletions`, `changed_files`, `requested_reviewers`

Recommended strategy: Phased loading
1. Display PRs immediately with comments/labels from Search API
2. Enrich each PR asynchronously with change stats and reviewers from Pull Requests API
3. Cache enriched data for session lifetime

## Research Areas

### 1. GitHub API Data Sources for Preview Metadata

#### Search Issues API (Currently Used)

**Endpoint**: `GET {baseURL}/search/issues`

**Already Provides**:
- ✅ `comments` (integer): Total comment count on the issue/PR
- ✅ `labels` (array): All labels applied to the PR
  ```json
  "labels": [
    {
      "name": "bug",
      "color": "d73a4a",
      "description": "Something isn't working"
    }
  ]
  ```

**Does NOT Provide**:
- ❌ Additions/deletions/changed_files
- ❌ Requested reviewers
- ❌ Review states (pending/approved/changes requested)

**Decision**: Continue using Search API as primary data source. Comments and labels are "free" metadata requiring no additional calls.

---

#### Pull Requests API (Additional Call Required)

**Endpoint**: `GET {baseURL}/repos/{owner}/{repo}/pulls/{number}`

**Response Fields**:
```json
{
  "additions": 145,
  "deletions": 23,
  "changed_files": 7,
  "comments": 5,
  "review_comments": 12,
  "commits": 3,
  "requested_reviewers": [
    {
      "login": "octocat",
      "avatar_url": "https://avatars.githubusercontent.com/u/1?v=4"
    }
  ],
  "requested_teams": [
    {
      "name": "core-team",
      "slug": "core-team"
    }
  ],
  "labels": [...],
  ...
}
```

**Provides**:
- ✅ `additions`: Lines added
- ✅ `deletions`: Lines deleted
- ✅ `changed_files`: Files modified
- ✅ `requested_reviewers`: Array of users requested to review
- ✅ `requested_teams`: Array of teams requested to review
- ✅ `comments`: Issue comment count (redundant with Search API)
- ✅ `review_comments`: Code review comment count
- ✅ `labels`: Labels array (redundant with Search API)

**Cost**: 1 API call per PR

**Decision**: Use this endpoint for change statistics and reviewer information. Fetch asynchronously after initial PR list load.

---

### 2. API Call Strategy & Rate Limiting

#### Rate Limit Context

- **Authenticated limit**: 5,000 requests/hour
- **Current usage**: 1 request for user info + N requests for PR search queries (typically 3-5)
- **New usage**: +M requests for PR details (M = number of PRs displayed)

**Scenarios**:
- 10 PRs → 10 additional calls → 13-17 total requests
- 50 PRs → 50 additional calls → 53-57 total requests
- 100 PRs → 100 additional calls → 103-107 total requests

**Conclusion**: Rate limits are not a practical concern for typical usage (<100 PRs). Users would need to refresh >46 times per hour to hit limits.

---

#### Phased Loading Strategy

**Phase 1: Initial Load (Fast)**
- Fetch PR list via Search API (existing flow)
- Display PRs immediately with comments + labels
- State: `LoadingState.loaded([PullRequest])` with partial metadata

**Phase 2: Enrichment (Async)**
- For each PR in displayed list:
  - Fetch PR details from Pull Requests API
  - Update PR model with additions/deletions/files/reviewers
  - Notify view of update (via state container observation)
- Failures isolated: Individual PR enrichment failures don't affect others

**Benefits**:
- Fast initial render (no blocking on 50+ API calls)
- Progressive enhancement (metadata appears as it loads)
- Graceful degradation (failed enrichment shows "—" for missing data)

---

### 3. Caching Strategy

#### Session-Level Caching

**Approach**: Store enriched PR data in memory for the app session

**Implementation**:
```swift
private var metadataCache: [String: PRPreviewMetadata] = [:] // Key: PR.id
```

**Cache Invalidation**:
- Clear cache when user logs out
- Clear cache when PR list is manually refreshed
- Consider cache stale if `pr.updatedAt` changes (detected on next fetch)

**Benefits**:
- Avoids re-fetching metadata when filtering/searching (PRs remain in memory)
- Reduces API calls when user returns to list after opening a PR
- No persistence overhead (session-only)

**Trade-off**: Metadata may become stale during long sessions. Acceptable because:
- Users typically work in short sessions (<1 hour)
- Manual refresh is available
- Stale change counts are low-impact (users will see current data when opening PR)

---

### 4. Error Handling & Graceful Degradation

#### Failure Modes

| Failure | Behavior | User Experience |
|---------|----------|----------------|
| PR details API 404 | Skip enrichment for that PR | Show "—" for unavailable fields |
| PR details API 403 | Skip enrichment (permissions) | Show "—" for unavailable fields |
| PR details API 500 | Skip enrichment (retry not warranted) | Show "—" for unavailable fields |
| Network timeout | Skip enrichment | Show "—" for unavailable fields |
| Rate limit hit | Stop further enrichment | Already-enriched PRs show data, rest show "—" |

**Key Principle**: Partial data is acceptable. PR list must never fail to display because metadata enrichment failed.

---

### 5. State Modeling

#### Option A: Inline Enrichment (Chosen)

Extend `PullRequest` model with optional preview metadata:

```swift
struct PullRequest {
    // Existing fields
    let repositoryOwner: String
    let repositoryName: String
    let number: Int
    let title: String
    let authorLogin: String
    let authorAvatarURL: URL?
    let updatedAt: Date
    let htmlURL: URL
    
    // NEW: Preview metadata (from Search API - always available)
    let commentCount: Int
    let labels: [PRLabel]
    
    // NEW: Preview metadata (from PR Details API - loaded async)
    var previewMetadata: PRPreviewMetadata?
}

struct PRPreviewMetadata {
    let additions: Int
    let deletions: Int
    let changedFiles: Int
    let requestedReviewers: [Reviewer]
}

struct Reviewer {
    let login: String
    let avatarURL: URL?
}

struct PRLabel {
    let name: String
    let color: String
}
```

**Benefits**:
- Simple: Single model per PR
- Natural: Metadata is part of the PR entity
- Filtering/sorting unaffected: All existing logic operates on `[PullRequest]`

**Trade-offs**:
- Model becomes mutable (requires `var` for `previewMetadata`)
- Must use `@Observable` or manual notifications for updates

---

#### Option B: Separate Enrichment State (Rejected)

Maintain separate dictionary of metadata keyed by PR ID:

```swift
private(set) var metadata: [String: PRPreviewMetadata] = [:]
```

**Benefits**:
- `PullRequest` remains immutable
- Clear separation of "core" vs "enrichment" data

**Trade-offs**:
- Views must join PR + metadata manually
- More complex: Two sources of truth
- Filtering/sorting requires metadata awareness

**Decision**: Rejected. Inline enrichment is simpler and aligns with SwiftUI's observation model.

---

### 6. Data Availability Indicators

#### Distinguishing Zero from Unavailable

**Problem**: How to show "0 comments" vs "comment count unknown"?

**Solution**: Use Optional + semantic meaning

```swift
struct PullRequest {
    let commentCount: Int           // From Search API - always known
    var previewMetadata: PRPreviewMetadata? // nil = not yet loaded, non-nil = loaded
}

struct PRPreviewMetadata {
    let additions: Int              // Always present when struct exists
    let deletions: Int
    let changedFiles: Int
    let requestedReviewers: [Reviewer]  // Empty array = no reviewers, not "unknown"
}
```

**View Logic**:
```swift
// Comments: Always available
Text("\(pr.commentCount) comments")

// Change stats: Show "—" if not loaded
if let metadata = pr.previewMetadata {
    Text("+\(metadata.additions) −\(metadata.deletions)")
} else {
    Text("—")
}
```

**Benefits**:
- Clear semantics: `nil` = loading/unavailable, value = known (possibly zero)
- No additional "availability" enum needed
- Testable: Fixtures can model both states

---

### 7. Performance Considerations

#### Parallel vs Sequential Enrichment

**Option A: Parallel (Chosen)**
```swift
await withTaskGroup(of: Void.self) { group in
    for pr in pullRequests {
        group.addTask {
            await enrichPR(pr)
        }
    }
}
```

**Option B: Sequential**
```swift
for pr in pullRequests {
    await enrichPR(pr)
}
```

**Decision**: Parallel enrichment for 50 PRs completes in ~1-2 seconds vs 5-10 seconds sequentially. GitHub API allows burst concurrency.

---

#### Visible-Only Enrichment (Future Enhancement)

**Current Plan**: Enrich all PRs in the list
**Future**: Enrich only PRs visible in viewport (lazy loading)

**Rationale for deferring**:
- Adds complexity (viewport tracking, scroll monitoring)
- Current approach is "good enough" for 50-100 PRs
- Can optimize later if performance issues arise

---

### 8. Testing Strategy

#### Fixtures Required

**pr-details-response.json**: Full PR details with all metadata populated
```json
{
  "additions": 145,
  "deletions": 23,
  "changed_files": 7,
  "requested_reviewers": [
    {"login": "reviewer1", "avatar_url": "..."}
  ],
  "labels": [...]
}
```

**pr-details-minimal.json**: Minimal response (no reviewers, zero changes)
```json
{
  "additions": 0,
  "deletions": 0,
  "changed_files": 0,
  "requested_reviewers": []
}
```

**pr-details-large-changes.json**: Large PR (10k+ lines)
```json
{
  "additions": 12450,
  "deletions": 3280,
  "changed_files": 156
}
```

---

#### Integration Tests

**Test Coverage**:
1. ✅ PR list loads with comments/labels from Search API
2. ✅ Preview metadata enriches PRs with change stats and reviewers
3. ✅ Individual enrichment failures don't break PR list
4. ✅ Cache prevents duplicate API calls
5. ✅ Zero values display correctly (not confused with unavailable)
6. ✅ Filtering/searching works with enriched PRs
7. ✅ Rate limit responses handled gracefully

**Mock Boundary**: Network layer only (HTTPClient). `GitHubAPIClient` and state containers tested with real logic.

---

## Decisions Summary

| Aspect | Decision | Rationale |
|--------|----------|-----------|
| **Data Sources** | Search API + PR Details API | Comments/labels free; change stats/reviewers require extra call |
| **Loading Strategy** | Phased (immediate display + async enrichment) | Fast initial render, progressive enhancement |
| **Caching** | Session-level in-memory cache | Reduces API calls; acceptable staleness |
| **State Model** | Inline enrichment (mutable `PullRequest`) | Simpler than separate state; aligns with Observation |
| **Error Handling** | Graceful per-PR degradation | Individual failures don't affect list |
| **Concurrency** | Parallel enrichment via TaskGroup | 50 PRs enriched in ~1-2s vs 5-10s sequential |
| **Zero vs Unavailable** | Optional + semantic types | Clear distinction without extra enums |

---

## Future Enhancements (Out of Scope)

- **Live Updates**: Poll for metadata changes while list is open
- **Viewport-Based Enrichment**: Enrich only visible PRs (lazy loading)
- **Persistent Cache**: Store metadata across app launches
- **Batch API Calls**: GitHub doesn't support batch PR details, but could explore GraphQL
- **Review State Details**: Show approved/changes-requested/pending per reviewer (requires Reviews API)

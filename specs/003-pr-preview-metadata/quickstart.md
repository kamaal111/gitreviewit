# Quickstart: Pull Request Preview Metadata

**Feature**: Pull Request Preview Metadata  
**Last Updated**: December 25, 2025

## 30-Second Overview

**What**: Display preview metadata (change stats, comments, reviewers, labels) in PR list for quick triage.

**How**: Extend `PullRequest` model with metadata fields. Fetch comments/labels from Search API (free), enrich with change stats/reviewers from PR Details API (async). Display progressively in `PullRequestRow`.

**Key Files**:
- Models: `PullRequest.swift`, `PRPreviewMetadata.swift`, `Reviewer.swift`, `PRLabel.swift`
- API: `GitHubAPI.swift` (add `fetchPRDetails`), `GitHubAPIClient.swift` (implement)
- State: `PullRequestListContainer.swift` (add `enrichPreviewMetadata`)
- Views: `PullRequestRow.swift` (display metadata), `PreviewMetadataView.swift` (new subview)

---

## Architecture At-a-Glance

```
┌─────────────────────────────────────────────────┐
│ PullRequestListView                             │
│  ├─ PullRequestRow (for each PR)                │
│  │   ├─ Repo name, title, author (existing)     │
│  │   └─ PreviewMetadataView (NEW)               │
│  │       ├─ Comments (always available)         │
│  │       ├─ Labels (always available)           │
│  │       ├─ Change stats (async loaded)         │
│  │       └─ Reviewers (async loaded)            │
└─────────────────────────────────────────────────┘
                    │ reads state
                    ▼
┌─────────────────────────────────────────────────┐
│ PullRequestListContainer (@Observable)          │
│  ├─ loadingState: LoadingState<[PullRequest]>   │
│  ├─ isEnrichingMetadata: Bool                   │
│  ├─ metadataCache: [String: PRPreviewMetadata]  │
│  └─ Methods:                                    │
│      ├─ loadPullRequests() (existing)           │
│      └─ enrichPreviewMetadata() (NEW)           │
└─────────────────────────────────────────────────┘
                    │ calls
                    ▼
┌─────────────────────────────────────────────────┐
│ GitHubAPIClient (implements GitHubAPI)          │
│  ├─ fetchReviewRequests(...) (existing)         │
│  │   → Returns PRs with comments + labels       │
│  └─ fetchPRDetails(...) (NEW)                   │
│      → Returns change stats + reviewers         │
└─────────────────────────────────────────────────┘
                    │ network calls
                    ▼
       ┌────────────────────────────┐
       │ GitHub REST API            │
       ├────────────────────────────┤
       │ Search Issues (existing)   │
       │  ✓ comments               │
       │  ✓ labels                 │
       ├────────────────────────────┤
       │ Pull Requests (NEW)        │
       │  ✓ additions              │
       │  ✓ deletions              │
       │  ✓ changed_files          │
       │  ✓ requested_reviewers    │
       └────────────────────────────┘
```

---

## Data Flow

### Phase 1: Initial PR List Load (Fast)

```
User opens app
    │
    ▼
loadPullRequests()
    │
    ├─► Fetch credentials
    ├─► Call fetchReviewRequests()
    │       │
    │       ├─► Search API (parallel queries)
    │       └─► Returns PRs with commentCount + labels
    │
    ├─► Set loadingState = .loaded([PullRequest])
    │       (previewMetadata = nil for all PRs)
    │
    └─► View renders immediately
            ├─ Shows PR list
            ├─ Displays comments + labels
            └─ Shows "—" for change stats/reviewers (not loaded yet)
```

### Phase 2: Metadata Enrichment (Async)

```
enrichPreviewMetadata()
    │
    ├─► For each PR (in parallel via TaskGroup):
    │       │
    │       ├─► Check metadataCache[pr.id]
    │       │       ├─ Hit: Skip fetch, use cached value
    │       │       └─ Miss: Fetch from API
    │       │
    │       ├─► Call fetchPRDetails(owner, repo, number)
    │       │       │
    │       │       ├─► GET /repos/{owner}/{repo}/pulls/{number}
    │       │       └─► Returns PRPreviewMetadata
    │       │               ├─ additions, deletions, changedFiles
    │       │               └─ requestedReviewers
    │       │
    │       ├─► On success:
    │       │       ├─ Cache metadata
    │       │       └─ Update PR.previewMetadata
    │       │
    │       └─► On failure:
    │               ├─ Log error (OSLog)
    │               └─ Leave PR.previewMetadata = nil
    │
    └─► Update loadingState with enriched PRs
            │
            ▼
        View auto-updates (Observation)
            └─► Preview metadata appears progressively
```

---

## Implementation Checklist

### Phase A: Models & API Contract

- [ ] Extend `PullRequest` struct:
  - Add `commentCount: Int`
  - Add `labels: [PRLabel]`
  - Add `previewMetadata: PRPreviewMetadata?`
- [ ] Create `PRPreviewMetadata` struct (additions, deletions, changedFiles, requestedReviewers)
- [ ] Create `Reviewer` struct (login, avatarURL)
- [ ] Create `PRLabel` struct (name, color)
- [ ] Extend `GitHubAPI` protocol with `fetchPRDetails` method
- [ ] Update `SearchIssueItem` decoding to map comments + labels
- [ ] Create `PRDetailsResponse` decoding struct

### Phase B: API Implementation

- [ ] Implement `fetchPRDetails` in `GitHubAPIClient`
  - Construct URL: `{baseURL}/repos/{owner}/{repo}/pulls/{number}`
  - Set headers (Authorization, Accept, API version)
  - Decode `PRDetailsResponse`
  - Map to `PRPreviewMetadata`
  - Handle errors (401, 403, 404, 5xx)
- [ ] Update `MockGitHubAPI` with `fetchPRDetails` mock
  - Add `prDetailsToReturn` dictionary
  - Add call tracking

### Phase C: State Management

- [ ] Extend `PullRequestListContainer`:
  - Add `isEnrichingMetadata: Bool`
  - Add `metadataCache: [String: PRPreviewMetadata]`
  - Implement `enrichPreviewMetadata()` method
  - Implement `clearMetadataCache()` method
- [ ] Update `loadPullRequests()` to:
  - Clear metadata cache on fresh load
  - Call `enrichPreviewMetadata()` after successful fetch
- [ ] Update existing tests to handle new fields

### Phase D: UI Components

- [ ] Extend `PullRequestRow` to display:
  - Comment count (always available)
  - Labels (always available)
  - Change stats (+/- lines, files) if `previewMetadata != nil`
  - Reviewers if `previewMetadata != nil`
- [ ] Create `PreviewMetadataView` subview:
  - Display change stats with icons
  - Display reviewers with avatars
  - Handle nil metadata gracefully (show "—")
- [ ] Update accessibility labels for preview metadata

### Phase E: Testing

- [ ] Create test fixtures:
  - `pr-details-response.json` (full metadata)
  - `pr-details-minimal.json` (zero changes, no reviewers)
  - `pr-details-large.json` (10k+ lines, many reviewers)
- [ ] Add integration tests:
  - `testPRListLoadsWithCommentsAndLabels`
  - `testMetadataEnrichmentSucceeds`
  - `testMetadataEnrichmentHandlesPartialFailures`
  - `testMetadataCache`
  - `testFilteringWorksWithEnrichedMetadata`
- [ ] Update existing tests to provide comment/label data

---

## Key Decisions

| Decision | Rationale |
|----------|-----------|
| **Inline metadata on `PullRequest`** | Simpler than separate state; aligns with Observation |
| **Phased loading** | Fast initial render; progressive enhancement |
| **Parallel enrichment** | 50 PRs enriched in ~1-2s vs 5-10s sequential |
| **Session-level cache** | Reduces API calls; acceptable staleness |
| **Graceful per-PR degradation** | Individual failures don't break list |
| **Optional `previewMetadata`** | Clear semantic: `nil` = not loaded, value = known (possibly zero) |

---

## Testing Strategy

**Focus**: Integration-level tests. Mock only network boundary (HTTPClient).

**Coverage**:
1. ✅ PR list loads with comments/labels from Search API
2. ✅ Metadata enrichment adds change stats/reviewers
3. ✅ Partial failures (some PRs enrich, others fail)
4. ✅ Cache prevents duplicate API calls
5. ✅ Zero values distinct from unavailable
6. ✅ Filtering/searching works with metadata
7. ✅ Rate limit handling (stop enrichment, preserve existing data)

**Fixtures**:
- Reuse `prs-response.json` (add `comments`/`labels` fields)
- New: `pr-details-response.json`, `pr-details-minimal.json`, `pr-details-large.json`

---

## Error Handling

| Error | Behavior | User Sees |
|-------|----------|-----------|
| API 404 | Skip PR enrichment | "—" for change stats/reviewers |
| API 403 (permission) | Skip PR enrichment | "—" for change stats/reviewers |
| API 403 (rate limit) | Stop all enrichment | Already-enriched PRs show data, rest show "—" |
| Network timeout | Skip PR enrichment | "—" for change stats/reviewers |
| Decoding failure | Skip PR enrichment | "—" for change stats/reviewers |

**Principle**: Never fail PR list display due to metadata enrichment issues.

---

## Performance Targets

- **Initial PR list load**: <1s (existing, no change)
- **Metadata enrichment** (50 PRs): 1-2s (parallel)
- **UI responsiveness**: No blocking during enrichment
- **API calls**: 1 per PR (cached for session)

---

## Future Enhancements (Out of Scope)

- Live metadata updates (poll for changes)
- Viewport-based lazy enrichment (enrich only visible PRs)
- Persistent cache across app launches
- Team reviewers display (currently only individual reviewers)
- Review states (approved/changes requested/pending)
- GraphQL for batch PR details fetching

---

## Quick Reference: File Locations

```
Models:
  app/GitReviewItApp/Sources/GitReviewItApp/Features/PullRequests/Models/
    ├─ PullRequest.swift (MODIFY)
    ├─ PRPreviewMetadata.swift (NEW)
    ├─ Reviewer.swift (NEW)
    └─ PRLabel.swift (NEW)

API:
  app/GitReviewItApp/Sources/GitReviewItApp/Infrastructure/Networking/
    ├─ GitHubAPI.swift (MODIFY - add protocol method)
    └─ GitHubAPIClient.swift (MODIFY - implement method)

State:
  app/GitReviewItApp/Sources/GitReviewItApp/Features/PullRequests/State/
    └─ PullRequestListContainer.swift (MODIFY)

Views:
  app/GitReviewItApp/Sources/GitReviewItApp/Features/PullRequests/Views/
    ├─ PullRequestRow.swift (MODIFY)
    └─ PreviewMetadataView.swift (NEW)

Tests:
  app/GitReviewItApp/Tests/GitReviewItAppTests/
    ├─ Fixtures/
    │   ├─ pr-details-response.json (NEW)
    │   ├─ pr-details-minimal.json (NEW)
    │   └─ pr-details-large.json (NEW)
    ├─ IntegrationTests/
    │   ├─ PRPreviewMetadataTests.swift (NEW)
    │   └─ PullRequestListTests.swift (MODIFY)
    └─ TestDoubles/
        └─ MockGitHubAPI.swift (MODIFY)
```

---

## Next Steps

1. ✅ Read full plan in [plan.md](plan.md)
2. ✅ Review data models in [data-model.md](data-model.md)
3. ✅ Review API contracts in [contracts/protocols.md](contracts/protocols.md)
4. ▶️ Begin implementation with Phase A (Models & API Contract)
5. Run `just test` after each phase to ensure nothing breaks

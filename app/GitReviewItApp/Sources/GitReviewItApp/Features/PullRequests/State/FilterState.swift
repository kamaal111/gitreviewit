//
//  FilterState.swift
//  GitReviewItApp
//
//  Created by Kamaal M Farah on 23/12/2025.
//

import OSLog
import Observation
import SwiftUI

@Observable
@MainActor
final class FilterState {
    private(set) var searchQuery: String = ""
    private(set) var configuration: FilterConfiguration = .empty
    private(set) var metadata: FilterMetadata = FilterMetadata(organizations: [], repositories: [], teams: .idle)
    private(set) var errorMessage: String?
    private let persistence: FilterPersistence
    private let timeProvider: TimeProvider
    private let logger = Logger(subsystem: "com.gitreviewit.app", category: "FilterState")

    private var searchTask: Task<Void, Never>?

    init(persistence: FilterPersistence, timeProvider: TimeProvider = RealTimeProvider()) {
        self.persistence = persistence
        self.timeProvider = timeProvider
    }

    func updateSearchQuery(_ query: String) {
        searchTask?.cancel()
        searchTask = Task {
            do {
                try await timeProvider.sleep(nanoseconds: 300 * 1_000_000)
            } catch {
                return
            }

            guard !Task.isCancelled else { return }
            self.searchQuery = query
        }
    }

    func clearSearchQuery() {
        searchTask?.cancel()
        searchTask = nil
        searchQuery = ""
    }

    /// Await completion of any pending search query update. For testing purposes.
    func awaitSearchCompletion() async {
        await searchTask?.value
    }

    func updateFilterConfiguration(_ newConfiguration: FilterConfiguration) async {
        configuration = newConfiguration
        do {
            try await persistence.save(newConfiguration)
        } catch {
            logger.error("Failed to save filter configuration: \(error.localizedDescription)")
            errorMessage = "Failed to save filter preferences. Your selections may not persist after restart."
        }
    }

    func loadPersistedConfiguration() async {
        do {
            if let loaded = try await persistence.load() {
                configuration = loaded
            }
        } catch {
            logger.warning(
                "Failed to load filter configuration: \(error.localizedDescription). Clearing corrupted data."
            )
            try? await persistence.clear()
            errorMessage = "Previous filter preferences could not be loaded and have been reset."
        }
    }

    func clearAllFilters() async {
        configuration = .empty
        do {
            try await persistence.clear()
        } catch {
            logger.error("Failed to clear filter configuration: \(error.localizedDescription)")
            errorMessage = "Failed to clear filter preferences. Some filters may still be saved."
        }
    }

    func clearError() {
        errorMessage = nil
    }

    func updateMetadata(from pullRequests: [PullRequest]) {
        metadata = FilterMetadata.from(pullRequests: pullRequests)
    }

    func updateMetadata(
        from pullRequests: [PullRequest],
        api: GitHubAPI,
        credentials: GitHubCredentials
    ) async {
        // Update organizations and repositories synchronously
        let organizations = Set(pullRequests.map { $0.repositoryOwner })
        let repositories = Set(pullRequests.map { $0.repositoryFullName })

        // Set teams to loading state
        metadata = FilterMetadata(
            organizations: organizations,
            repositories: repositories,
            teams: .loading
        )

        // Fetch teams asynchronously
        do {
            let teams = try await api.fetchTeams(credentials: credentials)
            metadata = FilterMetadata(
                organizations: organizations,
                repositories: repositories,
                teams: .loaded(teams)
            )
        } catch {
            guard
                let apiError = error as? APIError
            else {
                logger.error("Failed to fetch teams with unexpected error: \(error.localizedDescription)")
                metadata = FilterMetadata(
                    organizations: organizations,
                    repositories: repositories,
                    teams: .failed(.unknown(error))
                )
                return
            }

            logger.warning("Failed to fetch teams: \(apiError.localizedDescription)")
            metadata = FilterMetadata(
                organizations: organizations,
                repositories: repositories,
                teams: .failed(apiError)
            )

            // Clear invalid team filters if teams unavailable
            await clearInvalidTeamFilters()
        }
    }

    private func clearInvalidTeamFilters() async {
        guard
            !configuration.selectedTeams.isEmpty
        else {
            return
        }

        logger.info("Clearing team filters due to unavailable team data")
        let clearedConfig = FilterConfiguration(
            version: configuration.version,
            selectedOrganizations: configuration.selectedOrganizations,
            selectedRepositories: configuration.selectedRepositories,
            selectedTeams: []
        )

        await updateFilterConfiguration(clearedConfig)
        errorMessage = "Team filtering is unavailable. Your team filter selections have been cleared."
    }
}

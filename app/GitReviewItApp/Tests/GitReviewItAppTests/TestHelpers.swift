//
//  TestHelpers.swift
//  GitReviewItApp
//
//  Created by Kamaal M Farah on 24/12/2025.
//

import Foundation
import Testing

/// Available test fixtures
enum Fixture: String {
    case userResponse = "user-response"
    case prsResponse = "prs-response"
    case teamsResponse = "teams-response"
    case teamsFullResponse = "teams-full-response"
    case errorResponses = "error-responses"
}

/// Shared test utilities for loading fixtures and other common test operations
enum TestHelpers {
    /// Loads fixture data from the Fixtures directory in the test bundle
    /// - Parameter fixture: The fixture to load
    /// - Returns: The fixture data
    /// - Throws: If the fixture file is not found or cannot be read
    static func loadFixture(_ fixture: Fixture) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: fixture.rawValue, withExtension: "json"))
        return try Data(contentsOf: url)
    }
}

//
//  TeamTests.swift
//  GitReviewItApp
//
//  Created by Kamaal M Farah on 23/12/2025.
//

import Foundation
import Testing

@testable import GitReviewItApp

struct TeamTests {
    @Test
    func `Team decodes correctly from GitHub API format`() throws {
        let json = Data(
            """
            [
                {
                    "slug": "justice-league",
                    "name": "Justice League",
                    "organization": {
                        "login": "dc"
                    },
                    "repositories": ["dc/batmobile", "dc/watchtower"]
                }
            ]
            """.utf8)

        let teams = try JSONDecoder().decode([Team].self, from: json)

        #expect(teams.count == 1)

        let justiceLeague = teams[0]
        #expect(justiceLeague.name == "Justice League")
        #expect(justiceLeague.slug == "justice-league")
        #expect(justiceLeague.organizationLogin == "dc")
        #expect(justiceLeague.fullSlug == "dc/justice-league")
        #expect(justiceLeague.repositories == ["dc/batmobile", "dc/watchtower"])
    }

    @Test
    func `Team decodes without repositories field`() throws {
        let json = Data(
            """
            [
                {
                    "slug": "avengers",
                    "name": "Avengers",
                    "organization": {
                        "login": "marvel"
                    }
                }
            ]
            """.utf8)

        let teams = try JSONDecoder().decode([Team].self, from: json)

        #expect(teams.count == 1)

        let avengers = teams[0]
        #expect(avengers.name == "Avengers")
        #expect(avengers.slug == "avengers")
        #expect(avengers.organizationLogin == "marvel")
        #expect(avengers.repositories == [])
    }

    @Test
    func `Team encodes and decodes round-trip correctly`() throws {
        let original = Team(
            slug: "test-team",
            name: "Test Team",
            organizationLogin: "testorg",
            repositories: ["testorg/repo1", "testorg/repo2"]
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode([original])

        let decoder = JSONDecoder()
        let decoded = try decoder.decode([Team].self, from: data)

        #expect(decoded.count == 1)
        #expect(decoded[0] == original)
    }
}

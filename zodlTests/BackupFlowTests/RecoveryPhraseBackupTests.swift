//
//  RecoveryFlowTests.swift
//  secantTests
//
//  Created by Francisco Gindre on 10/29/21.
//

import Testing
@testable import zodl_internal

@Suite struct RecoveryPhraseBackupTests {
    /// `RecoveryPhrase.toGroups()` always splits the phrase into three equal groups
    /// (designed for the 3-column visual layout on the backup screen). For a 24-word
    /// BIP39 phrase that's three groups of eight words each.
    @Test func given24WordsBIP39ChunkItIntoThirds() throws {
        let words = [
            // group 0
            "bring", "salute", "thank",
            "require", "spirit", "toe",
            "boil", "hill",
            // group 1
            "casino", "trophy", "drink", "frown",
            "bird", "grit", "close", "morning",
            // group 2
            "bind", "cancel", "daughter", "salon",
            "quit", "pizza", "just", "garlic"
        ]
        let phrase = RecoveryPhrase(words: words.map { $0.redacted })

        let chunks = phrase.toGroups()

        #expect(chunks.count == 3)
        #expect(chunks[0].startIndex == 0)
        #expect(chunks[0].words == [
            "bring", "salute", "thank", "require", "spirit", "toe", "boil", "hill"
        ].map { $0.redacted })
        #expect(chunks[1].startIndex == 8)
        #expect(chunks[1].words == [
            "casino", "trophy", "drink", "frown", "bird", "grit", "close", "morning"
        ].map { $0.redacted })
        #expect(chunks[2].startIndex == 16)
        #expect(chunks[2].words == [
            "bind", "cancel", "daughter", "salon", "quit", "pizza", "just", "garlic"
        ].map { $0.redacted })
    }
}

//
//  RecoveryPhraseTests.swift
//  zodlTests
//
//  Extended — pure logic. Covers RecoveryPhrase toString / toGroups / Group.words (Models/RecoveryPhrase.swift).
//

import Testing
import Foundation
@testable import zodl_internal

@Suite struct RecoveryPhraseTests {
    @Test func toStringJoinsWordsWithSpaces() {
        let phrase = RecoveryPhrase(words: ["alpha", "bravo", "charlie"].map { $0.redacted })
        #expect(phrase.toString().data == "alpha bravo charlie")
    }

    @Test func toGroupsSplitsTwentyFourWordsIntoThreeGroupsOfEight() {
        let groups = RecoveryPhrase.placeholder.toGroups() // 24 words
        #expect(groups.count == 3)
        #expect(groups.map(\.words.count) == [8, 8, 8])
        #expect(groups.map(\.startIndex) == [0, 8, 16])
    }

    @Test func groupWordsReplacesMissingIndexWithEmpty() {
        let group = RecoveryPhrase.Group(startIndex: 0, words: ["one", "two", "three"].map { $0.redacted })
        #expect(group.words(with: 1).map(\.data) == ["one", "", "three"])
    }
}

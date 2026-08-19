//
//  MnemonicClientTests.swift
//  zodlTests
//
//  Batch 4 — dependency logic. Covers MnemonicClient.liveValue (Dependencies/MnemonicClient/MnemonicLiveKey.swift).
//

import Testing
import Foundation
@testable import zodl_internal

@Suite struct MnemonicClientTests {
    private let validPhrase =
        "still champion voice habit trend flight survey between bitter process artefact blind " +
        "carbon truly provide dizzy crush flush breeze blouse charge solid fish spread"

    @Test func randomMnemonicProducesTwentyFourValidWords() throws {
        let client = MnemonicClient.liveValue
        #expect(try client.randomMnemonicWords().count == 24)
        try client.isValid(client.randomMnemonic()) // generated phrase validates
    }

    @Test func toSeedIsDeterministicAndSixtyFourBytes() throws {
        let client = MnemonicClient.liveValue
        let seed = try client.toSeed(validPhrase)
        #expect(seed.count == 64)
        #expect(try client.toSeed(validPhrase) == seed) // deterministic
    }

    @Test func isValidAcceptsValidPhrase() throws {
        try MnemonicClient.liveValue.isValid(validPhrase)
    }

    @Test func isValidRejectsInvalidPhrase() {
        #expect(throws: (any Error).self) {
            try MnemonicClient.liveValue.isValid("totally not a valid mnemonic phrase at all")
        }
    }

    @Test func suggestWordsFiltersByPrefix() throws {
        let suggestions = try MnemonicClient.liveValue.suggestWords("aban")
        #expect(suggestions.contains("abandon"))
        #expect(suggestions.allSatisfy { $0.hasPrefix("aban") })
    }

    @Test func asWordsSplitsOnSpaces() throws {
        #expect(try MnemonicClient.liveValue.asWords("alpha bravo charlie") == ["alpha", "bravo", "charlie"])
    }
}

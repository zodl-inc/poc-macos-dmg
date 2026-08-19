//
//  MemoByteCountingTests.swift
//  secantTests
//
//  Created by Cosmos on 18.05.2026.
//

import Testing
@testable import zodl_internal

@Suite struct MemoByteCountingTests {
    @Test func byteLengthEmptyTextIsZero() {
        let state = MessageEditor.State(charLimit: 512, text: "")

        #expect(
            state.byteLength == 0,
            "MemoByteCountingTests: `testByteLengthEmptyTextIsZero` byteLength is expected to be 0 but it is \(state.byteLength)"
        )
    }

    @Test func byteLengthMultipleEmojiAccumulateBytes() {
        let text = String(repeating: "🎉", count: 10)
        let state = MessageEditor.State(charLimit: 512, text: text)

        #expect(
            state.byteLength == 40,
            "MemoByteCountingTests: `testByteLengthMultipleEmojiAccumulateBytes` byteLength is expected to be 40 but it is \(state.byteLength)"
        )
    }

    @Test func byteLengthJapaneseTextCountsAsMultipleBytes() {
        let state = MessageEditor.State(charLimit: 512, text: "日本語")

        #expect(
            state.byteLength == 9,
            "MemoByteCountingTests: `testByteLengthJapaneseTextCountsAsMultipleBytes` byteLength is expected to be 9 but it is \(state.byteLength)"
        )
    }

    @Test func byteLengthSpanishAccentsCountsCorrectly() {
        let state = MessageEditor.State(charLimit: 512, text: "café")

        #expect(
            state.byteLength == 5,
            "MemoByteCountingTests: `testByteLengthSpanishAccentsCountsCorrectly` byteLength is expected to be 5 but it is \(state.byteLength)"
        )
    }

    @Test func byteLengthMixedContentCountsCorrectly() {
        let state = MessageEditor.State(charLimit: 512, text: "Hi 🎉 日本")

        #expect(
            state.byteLength == 14,
            "MemoByteCountingTests: `testByteLengthMixedContentCountsCorrectly` byteLength is expected to be 14 but it is \(state.byteLength)"
        )
    }

    @Test func isValidExactlyAtLimitIsTrue() {
        let text = String(repeating: "a", count: 512)
        let state = MessageEditor.State(charLimit: 512, text: text)

        #expect(
            state.isValid,
            "MemoByteCountingTests: `testIsValidExactlyAtLimitIsTrue` is expected to be true but it is \(state.isValid)"
        )
    }

    @Test func isValidEmojiPushingOverLimitIsFalse() {
        let text = String(repeating: "a", count: 510) + "🎉"
        let state = MessageEditor.State(charLimit: 512, text: text)

        #expect(
            !state.isValid,
            "MemoByteCountingTests: `testIsValidEmojiPushingOverLimitIsFalse` is expected to be false but it is \(state.isValid)"
        )
    }

    @Test func isValidEmojiExactlyAtLimitIsTrue() {
        let text = String(repeating: "a", count: 508) + "🎉"
        let state = MessageEditor.State(charLimit: 512, text: text)

        #expect(
            state.isValid,
            "MemoByteCountingTests: `testIsValidEmojiExactlyAtLimitIsTrue` is expected to be true but it is \(state.isValid)"
        )
    }

    @Test func isValidEmptyTextIsTrue() {
        let state = MessageEditor.State(charLimit: 512, text: "")

        #expect(
            state.isValid,
            "MemoByteCountingTests: `testIsValidEmptyTextIsTrue` is expected to be true but it is \(state.isValid)"
        )
    }

    @Test func charLimitTextAtLimitShowsZeroRemaining() {
        let text = String(repeating: "a", count: 512)
        let state = MessageEditor.State(charLimit: 512, text: text)

        #expect(
            state.charLimitText == "0/512",
            "MemoByteCountingTests: `testCharLimitTextAtLimitShowsZeroRemaining` charLimitText is expected to be \"0/512\" but it is \"\(state.charLimitText)\""
        )
    }

    @Test func charLimitTextEmojiCountedAsBytes() {
        let state = MessageEditor.State(charLimit: 512, text: "🎉")

        #expect(
            state.charLimitText == "508/512",
            "MemoByteCountingTests: `testCharLimitTextEmojiCountedAsBytes` charLimitText is expected to be \"508/512\" but it is \"\(state.charLimitText)\""
        )
    }

    @Test func charLimitTextShowsRemainingBytes() {
        let state = MessageEditor.State(charLimit: 512, text: "Hello")

        #expect(
            state.charLimitText == "507/512",
            "MemoByteCountingTests: `testCharLimitTextShowsRemainingBytes` charLimitText is expected to be \"507/512\" but it is \"\(state.charLimitText)\""
        )
    }
}

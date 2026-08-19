//
//  StringsTests.swift
//  zodlTests
//
//  Batch 1 — pure logic. Covers String truncation / USD parsing / ValidationType (Utils/Strings.swift).
//

import Testing
import Foundation
@testable import zodl_internal

@Suite struct StringsTests {
    // MARK: - zip316 / truncation

    @Test func zip316KeepsShortStrings() {
        let twenty = String(repeating: "a", count: 20)
        #expect(twenty.zip316 == twenty)
    }

    @Test func zip316TruncatesOverTwenty() {
        let input = String(repeating: "a", count: 21)
        #expect(input.zip316 == "\(String(repeating: "a", count: 20))...")
    }

    @Test func trailingZip316FallsBackToZip316UpToTwentyFive() {
        let input = String(repeating: "a", count: 25)
        // 25 is not > 25, so it falls back to zip316 (which truncates anything > 20).
        #expect(input.trailingZip316 == "\(String(repeating: "a", count: 20))...")
    }

    @Test func trailingZip316ShowsHeadAndTailOverTwentyFive() {
        let input = "\(String(repeating: "a", count: 26))bcde" // length 30
        #expect(input.trailingZip316 == "\(input.prefix(20))...\(input.suffix(4))")
    }

    @Test func truncateMiddleKeepsTenOrFewer() {
        let ten = String(repeating: "a", count: 10)
        #expect(ten.truncateMiddle == ten)
    }

    @Test func truncateMiddleShowsHeadAndTailOverTen() {
        let input = String(repeating: "a", count: 11)
        #expect(input.truncateMiddle == "\(input.prefix(5))...\(input.suffix(5))")
    }

    @Test func truncateMiddle10ShowsHeadAndTailOverTwenty() {
        let input = String(repeating: "x", count: 21)
        #expect(input.truncateMiddle10 == "\(input.prefix(10))...\(input.suffix(10))")
    }

    // MARK: - USD decimal parsing

    @Test func usDecimalParsesInteger() throws {
        let value = try #require("1234".usDecimal)
        #expect(value == Decimal(1234))
    }

    @Test func usDecimalReturnsNilForGarbage() {
        #expect("not a number".usDecimal == nil)
    }

    @Test func localeUsdDecimalParsesIntegerExactly() throws {
        let value = try #require("100".localeUsdDecimal)
        #expect(value == Decimal(100))
    }

    @Test func localeUsdDecimalReturnsNilForGarbage() {
        #expect("not a number".localeUsdDecimal == nil)
    }

    // MARK: - ValidationType

    @Test func nilValidationTypeIsAlwaysValid() {
        #expect("anything".isValid(for: nil))
    }

    @Test(arguments: ["a@b.com", "user.name+tag@example.co"])
    func emailValidationAcceptsValidAddresses(_ email: String) {
        #expect(String.ValidationType.email.isValid(text: email))
    }

    @Test(arguments: ["notanemail", "missing@tld", ""])
    func emailValidationRejectsInvalidAddresses(_ email: String) {
        #expect(!String.ValidationType.email.isValid(text: email))
    }

    @Test func maxLengthRejectsEmptyEvenWithinLimit() {
        // Notable behaviour: maxLength requires non-empty (text.count <= length && !text.isEmpty).
        #expect(!String.ValidationType.maxLength(5).isValid(text: ""))
        #expect(String.ValidationType.maxLength(5).isValid(text: "abc"))
        #expect(!String.ValidationType.maxLength(5).isValid(text: "abcdef"))
    }

    @Test func minLengthBoundary() {
        #expect(!String.ValidationType.minLength(3).isValid(text: "ab"))
        #expect(String.ValidationType.minLength(3).isValid(text: "abc"))
    }

    @Test func customRegexValidation() {
        let digitsOnly = String.ValidationType.custom("^[0-9]+$")
        #expect(digitsOnly.isValid(text: "12345"))
        #expect(!digitsOnly.isValid(text: "12a45"))
    }
}

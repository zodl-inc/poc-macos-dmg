//
//  DecimalsTests.swift
//  zodlTests
//
//  Batch 1 — pure logic. Covers `Decimal.simplified` (Utils/Decimals.swift).
//

import Testing
import Foundation
@testable import zodl_internal

@Suite struct DecimalsTests {
    @Test func simplifiedOfZeroIsZero() {
        #expect(Decimal(0).simplified == Decimal(0))
    }

    @Test func simplifiedKeepsExactTwoDecimalValue() throws {
        let value = try #require(Decimal(string: "1.23"))
        #expect(value.simplified == value)
    }

    @Test func simplifiedKeepsExactTwoDecimalValueWithTrailingDigits() throws {
        let value = try #require(Decimal(string: "12.34"))
        #expect(value.simplified == value)
    }

    @Test func simplifiedReducesToThreeDecimalsWhenWithinTolerance() throws {
        // 0.12 is 2.8% off (> 0.5%), 0.123 is 0.37% off (<= 0.5%) -> scale 3 wins.
        let value = try #require(Decimal(string: "0.123456789"))
        let expected = try #require(Decimal(string: "0.123"))
        #expect(value.simplified == expected)
    }

    @Test func simplifiedHandlesNegativeValues() throws {
        let value = try #require(Decimal(string: "-0.123456789"))
        let expected = try #require(Decimal(string: "-0.123"))
        #expect(value.simplified == expected)
    }

    @Test func simplifiedCollapsesWithinHalfPercentTolerance() throws {
        // 100.001 is within 0.5% of 100.00 at scale 2, so it simplifies to 100.
        let value = try #require(Decimal(string: "100.001"))
        let expected = try #require(Decimal(string: "100"))
        #expect(value.simplified == expected)
    }
}

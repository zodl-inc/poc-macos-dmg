//
//  CMCRateTests.swift
//  zodlTests
//
//  Batch 2 — persistence. Covers CMCPrice JSON decoding (Models/CMCRate.swift).
//

import Testing
import Foundation
@testable import zodl_internal

@Suite struct CMCRateTests {
    @Test func decodesZecUsdPrice() throws {
        let json = #"{"data":{"ZEC":{"quote":{"USD":{"price":123.45}}}}}"#
        let decoded = try JSONDecoder().decode(CMCPrice.self, from: Data(json.utf8))
        #expect(decoded.data["ZEC"]?.quote["USD"]?.price == 123.45)
    }

    @Test func decodesWithMissingZecKey() throws {
        let json = #"{"data":{}}"#
        let decoded = try JSONDecoder().decode(CMCPrice.self, from: Data(json.utf8))
        #expect(decoded.data["ZEC"] == nil)
    }

    @Test func throwsForMalformedPrice() {
        let json = #"{"data":{"ZEC":{"quote":{"USD":{"price":"not-a-number"}}}}}"#
        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode(CMCPrice.self, from: Data(json.utf8))
        }
    }
}

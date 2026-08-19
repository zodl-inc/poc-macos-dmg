//
//  SpendabilityTests.swift
//  zodlTests
//
//  Batch 2 — persistence. Covers Spendability Codable round-trip (Models/Spendability.swift).
//

import Testing
import Foundation
@testable import zodl_internal

@Suite struct SpendabilityTests {
    @Test(arguments: [Spendability.everything, .something, .nothing])
    func codableRoundTrip(_ value: Spendability) throws {
        let data = try JSONEncoder().encode(value)
        #expect(try JSONDecoder().decode(Spendability.self, from: data) == value)
    }
}

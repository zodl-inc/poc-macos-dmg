//
//  DateReadableTests.swift
//  zodlTests
//
//  Extended — pure logic. Covers Date.timestamp / asHumanReadable formats (Utils/Date+Readable.swift).
//  Asserts the format shape (timezone-independent) rather than an exact wall-clock string.
//

import Testing
import Foundation
@testable import zodl_internal

@Suite struct DateReadableTests {
    private let date = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func timestampMatchesFixedFormat() {
        let value = date.timestamp()
        #expect(value.range(of: #"^\d{4}/\d{2}/\d{2} \d{2}:\d{2}:\d{2}\.\d{4}$"#, options: .regularExpression) != nil)
    }

    @Test func asHumanReadableMatchesFixedFormat() {
        let value = date.asHumanReadable()
        #expect(value.range(of: #"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$"#, options: .regularExpression) != nil)
    }
}

//
//  AnyDecodableTests.swift
//  zodlTests
//
//  Batch 1 — pure logic. Covers `AnyDecodable` decode precedence (Utils/AnyDecodable.swift).
//

import Testing
import Foundation
@testable import zodl_internal

@Suite struct AnyDecodableTests {
    @Test func decodesIntegerAsInt() throws {
        let values = try decodeArray("[42]")
        #expect(values.first as? Int == 42)
    }

    @Test func decodesFractionalAsDouble() throws {
        let values = try decodeArray("[4.5]")
        #expect(values.first as? Double == 4.5)
    }

    @Test func decodesBooleanAsBool() throws {
        let values = try decodeArray("[true, false]")
        #expect(values.count == 2)
        #expect(values[0] as? Bool == true)
        #expect(values[1] as? Bool == false)
    }

    @Test func decodesString() throws {
        let values = try decodeArray("[\"hi\"]")
        #expect(values.first as? String == "hi")
    }

    @Test func decodesNestedArray() throws {
        let values = try decodeArray("[[1, 2, 3]]")
        let nested = try #require(values.first as? [Any])
        #expect(nested.compactMap { $0 as? Int } == [1, 2, 3])
    }

    @Test func decodesNestedObject() throws {
        let values = try decodeArray("[{\"k\": 1, \"s\": \"v\"}]")
        let dict = try #require(values.first as? [String: Any])
        #expect(dict["k"] as? Int == 1)
        #expect(dict["s"] as? String == "v")
    }

    @Test func decodingNullThrows() {
        #expect(throws: (any Error).self) {
            _ = try decodeArray("[null]")
        }
    }

    private func decodeArray(_ json: String) throws -> [Any] {
        let decoded = try JSONDecoder().decode([AnyDecodable].self, from: Data(json.utf8))
        return decoded.map(\.value)
    }
}

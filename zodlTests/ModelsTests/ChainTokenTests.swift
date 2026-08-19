//
//  ChainTokenTests.swift
//  zodlTests
//
//  Extended — pure logic. Covers ChainToken id + Codable (Models/ChainToken.swift).
//

import Testing
import Foundation
@testable import zodl_internal

@Suite struct ChainTokenTests {
    @Test func idIsChainDotTokenAndNotLowercased() {
        // Unlike SwapAsset.id, ChainToken.id preserves the original case.
        #expect(ChainToken(chain: "ETH", token: "USDC").id == "ETH.USDC")
    }

    @Test func codableRoundTrip() throws {
        let original = ChainToken(chain: "eth", token: "usdc")
        let data = try JSONEncoder().encode(original)
        #expect(try JSONDecoder().decode(ChainToken.self, from: data) == original)
    }
}

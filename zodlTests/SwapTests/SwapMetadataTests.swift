//
//  SwapMetadataTests.swift
//  zodlTests
//
//  Batch 1 — pure logic. Covers UMSwapId.swapStatus + UserMetadata Codable (Models/Swaps.swift).
//

import Testing
import Foundation
@testable import zodl_internal

@Suite struct SwapMetadataTests {
    @Test func swapStatusMapsAllKnownStatuses() {
        #expect(swapId(status: SwapConstants.failed).swapStatus == .failed)
        #expect(swapId(status: SwapConstants.refunded).swapStatus == .refunded)
        #expect(swapId(status: SwapConstants.expired).swapStatus == .expired)
        #expect(swapId(status: SwapConstants.success).swapStatus == .completed)
        #expect(swapId(status: SwapConstants.incompleteDeposit).swapStatus == .incomplete)
        #expect(swapId(status: SwapConstants.pendingDeposit).swapStatus == .pending)
        #expect(swapId(status: SwapConstants.processing).swapStatus == .pending)
    }

    @Test func swapStatusDefaultsToPendingForUnknown() {
        #expect(swapId(status: "SOMETHING_ELSE").swapStatus == .pending)
        #expect(swapId(status: "").swapStatus == .pending)
    }

    @Test func swapConstantsRawValues() {
        #expect(SwapConstants.zecAssetIdOnNear == "near.zec.zec")
        #expect(SwapConstants.pendingDeposit == "PENDING_DEPOSIT")
        #expect(SwapConstants.success == "SUCCESS")
    }

    @Test func umSwapIdCodableRoundTrip() throws {
        let original = swapId(status: SwapConstants.success)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(UMSwapId.self, from: data)
        #expect(decoded == original)
    }

    @Test func userMetadataCodableRoundTripPreservesFields() throws {
        let meta = UserMetadata(
            version: 3,
            lastUpdated: 42,
            accountMetadata: UMAccount(
                bookmarked: [UMBookmark(txId: "t", lastUpdated: 1, isBookmarked: true)],
                annotations: [UMAnnotation(txId: "t", content: "note", lastUpdated: 2)],
                read: ["r"],
                swaps: UMSwaps(
                    swapIds: [swapId(status: SwapConstants.success)],
                    lastUsedAssetHistory: ["near.eth.usdc"],
                    lastUpdated: 3
                )
            )
        )

        let data = try JSONEncoder().encode(meta)
        let decoded = try JSONDecoder().decode(UserMetadata.self, from: data)

        #expect(decoded.version == 3)
        #expect(decoded.lastUpdated == 42)
        #expect(decoded.accountMetadata.bookmarked.first?.isBookmarked == true)
        #expect(decoded.accountMetadata.annotations.first?.content == "note")
        #expect(decoded.accountMetadata.read == ["r"])
        #expect(decoded.accountMetadata.swaps.swapIds.first == swapId(status: SwapConstants.success))
        #expect(decoded.accountMetadata.swaps.lastUsedAssetHistory == ["near.eth.usdc"])
    }

    private func swapId(exactInput: Bool = true, status: String) -> UMSwapId {
        UMSwapId(
            depositAddress: "deposit",
            provider: "near",
            totalFees: 0,
            totalUSDFees: "0",
            lastUpdated: 0,
            fromAsset: "a",
            toAsset: "b",
            exactInput: exactInput,
            status: status,
            amountOutFormatted: "0"
        )
    }
}

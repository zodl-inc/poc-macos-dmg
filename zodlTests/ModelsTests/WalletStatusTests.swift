//
//  WalletStatusTests.swift
//  zodlTests
//
//  Extended — pure logic. Covers WalletStatus derivations (Models/WalletStatus.swift).
//

import Testing
@testable import zodl_internal

@Suite struct WalletStatusTests {
    @Test func isNotReadyForFullySyncedOperation() {
        #expect(WalletStatus.restoring.isNotReadyForFullySyncedOperation)
        #expect(WalletStatus.resyncing.isNotReadyForFullySyncedOperation)
        #expect(!WalletStatus.disconnected.isNotReadyForFullySyncedOperation)
        #expect(!WalletStatus.none.isNotReadyForFullySyncedOperation)
    }

    @Test func text() {
        #expect(WalletStatus.restoring.text() == String(localizable: .walletStatusRestoringWallet))
        #expect(WalletStatus.disconnected.text() == String(localizable: .walletStatusDisconnected))
        #expect(WalletStatus.none.text().isEmpty)
        #expect(WalletStatus.resyncing.text().isEmpty)
    }
}

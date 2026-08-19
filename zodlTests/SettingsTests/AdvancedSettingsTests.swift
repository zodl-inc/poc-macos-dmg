//
//  AdvancedSettingsTests.swift
//  zodlTests
//
//  Created by Michal Fousek on 12.06.2026.
//

import Testing
import ComposableArchitecture
@testable import zodl_internal

/// Covers MOB-1363: sensitive Advanced Settings rows must route through the
/// local-authentication gate (`operationAccessCheck`) before access is granted.
/// Without this, the Recovery Phrase row could regress to bypassing Face ID / Touch ID
/// while the `RecoveryPhraseDisplay` reducer tests still pass.
@Suite(.serialized) struct AdvancedSettingsTests {
    @MainActor @Test func recoveryPhraseGrantedOnlyAfterSuccessfulAuthentication() async {
        let store = TestStore(
            initialState: AdvancedSettings.State()
        ) {
            AdvancedSettings()
        } withDependencies: {
            $0.localAuthentication = .mockAuthenticationSucceeded
        }

        await store.send(.operationAccessCheck(.recoveryPhrase))

        await store.receive(.operationAccessGranted(.recoveryPhrase))

        await store.finish()
    }

    @MainActor @Test func recoveryPhraseDeniedWhenAuthenticationFails() async {
        let store = TestStore(
            initialState: AdvancedSettings.State()
        ) {
            AdvancedSettings()
        } withDependencies: {
            $0.localAuthentication = .mockAuthenticationFailed
        }

        // A failed authentication must NOT emit `operationAccessGranted`.
        await store.send(.operationAccessCheck(.recoveryPhrase))

        await store.finish()
    }

    @MainActor @Test func chooseServerSkipsAuthentication() async {
        let store = TestStore(
            initialState: AdvancedSettings.State()
        ) {
            AdvancedSettings()
        }
        // `localAuthentication` is intentionally left unimplemented: a call to
        // `authenticate()` for this non-sensitive operation would fail this test.

        await store.send(.operationAccessCheck(.chooseServer))

        await store.receive(.operationAccessGranted(.chooseServer))

        await store.finish()
    }
}

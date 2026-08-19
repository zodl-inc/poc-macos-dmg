//
//  TorSetupTests.swift
//  zodlTests
//
//  Created by Michal Fousek on 12.06.2026.
//

import Testing
import ComposableArchitecture
@testable import zodl_internal

/// Covers MOB-1364: every runtime Tor toggle must update the shared `swapAPIAccess`
/// routing flag immediately, so the exchange-rate, swap-and-pay and voting clients
/// (which read the flag per request) switch between `URLSession` and the protected
/// Tor path without an app restart.
@Suite struct TorSetupTests {
    private struct TorInitFailure: Error { }

    @MainActor @Test func enableRoutesProtectedImmediately() async {
        let store = TestStore(
            initialState: TorSetup.State()
        ) {
            TorSetup()
        } withDependencies: {
            $0.walletStorage.importTorSetupFlag = { _ in }
            $0.sdkSynchronizer.torEnabled = { _ in }
        }

        await store.send(.enableTapped) {
            $0.$swapAPIAccess.withLock { $0 = .protected }
        }

        await store.finish()
    }

    @MainActor @Test func enableKeepsProtectedRoutingWhenTorInitFails() async {
        let store = TestStore(
            initialState: TorSetup.State()
        ) {
            TorSetup()
        } withDependencies: {
            $0.walletStorage.importTorSetupFlag = { _ in }
            $0.sdkSynchronizer.torEnabled = { _ in throw TorInitFailure() }
        }

        await store.send(.enableTapped) {
            // Fail closed: the user opted into Tor, so requests must not silently
            // fall back to direct networking just because the Tor init failed.
            $0.$swapAPIAccess.withLock { $0 = .protected }
        }

        await store.receive(.torInitFailed)

        await store.finish()
    }

    @MainActor @Test func disableRoutesDirectImmediately() async {
        var initialState = TorSetup.State()
        initialState.$swapAPIAccess.withLock { $0 = .protected }

        let store = TestStore(
            initialState: initialState
        ) {
            TorSetup()
        } withDependencies: {
            $0.walletStorage.importTorSetupFlag = { _ in }
            $0.sdkSynchronizer.torEnabled = { _ in }
        }

        await store.send(.disableTapped) {
            $0.$swapAPIAccess.withLock { $0 = .direct }
        }

        await store.finish()
    }

    @MainActor @Test func saveChangesOptInRoutesProtectedImmediately() async {
        let store = TestStore(
            initialState: TorSetup.State(currentSettingsOption: .optIn)
        ) {
            TorSetup()
        } withDependencies: {
            $0.walletStorage.importTorSetupFlag = { _ in }
            $0.sdkSynchronizer.torEnabled = { _ in }
        }

        await store.send(.saveChangesTapped) {
            $0.activeSettingsOption = .optIn
            $0.$swapAPIAccess.withLock { $0 = .protected }
        }

        await store.receive(.settingsOptionChanged(.optIn))
        await store.receive(.torInitSucceeded)
        await store.receive(.backToHomeTapped)

        await store.finish()
    }

    @MainActor @Test func saveChangesOptOutRoutesDirectImmediately() async {
        var initialState = TorSetup.State(currentSettingsOption: .optOut)
        initialState.$swapAPIAccess.withLock { $0 = .protected }

        let store = TestStore(
            initialState: initialState
        ) {
            TorSetup()
        } withDependencies: {
            $0.walletStorage.importTorSetupFlag = { _ in }
            $0.userStoredPreferences.setExchangeRate = { _ in }
            $0.sdkSynchronizer.torEnabled = { _ in }
        }

        await store.send(.saveChangesTapped) {
            $0.activeSettingsOption = .optOut
            $0.$swapAPIAccess.withLock { $0 = .direct }
        }

        await store.receive(.settingsOptionChanged(.optOut))
        await store.receive(.backToHomeTapped)

        await store.finish()
    }
}

//
//  TorSetupGapsTests.swift
//  zodlTests
//
//  Extended — settings/security. Covers TorSetup onAppear / option selection / save-gating gaps
//  (Features/TorSetup/TorSetupStore.swift). Complements TorSetupTests.
//

import Testing
import ComposableArchitecture
@testable import zodl_internal

@Suite(.serialized) struct TorSetupGapsTests {
    @MainActor @Test func onAppearWithTorEnabledSelectsOptIn() async {
        let store = makeStore(torFlag: true)
        store.exhaustivity = .off
        await store.send(.onAppear)
        #expect(store.state.activeSettingsOption == .optIn)
        #expect(store.state.currentSettingsOption == .optIn)
    }

    @MainActor @Test func onAppearWithTorDisabledOrUnsetSelectsOptOut() async {
        for flag in [false, nil] as [Bool?] {
            let store = makeStore(torFlag: flag)
            store.exhaustivity = .off
            await store.send(.onAppear)
            #expect(store.state.activeSettingsOption == .optOut)
            #expect(store.state.currentSettingsOption == .optOut)
        }
    }

    @MainActor @Test func settingsOptionTappedUpdatesCurrentOption() async {
        let store = makeStore(torFlag: false)
        store.exhaustivity = .off
        await store.send(.settingsOptionTapped(.optIn))
        #expect(store.state.currentSettingsOption == .optIn)
    }

    @Test func isSaveButtonDisabledWhenCurrentEqualsActive() {
        var state = TorSetup.State(activeSettingsOption: .optIn, currentSettingsOption: .optIn)
        #expect(state.isSaveButtonDisabled)
        state.currentSettingsOption = .optOut
        #expect(!state.isSaveButtonDisabled)
    }

    @Test func settingsOptionsTitles() {
        #expect(TorSetup.State.SettingsOptions.optIn.title() == String(localizable: .currencyConversionEnable))
        #expect(TorSetup.State.SettingsOptions.optOut.title() == String(localizable: .currencyConversionLearnMoreOptionDisable))
    }

    @MainActor
    private func makeStore(torFlag: Bool?) -> TestStoreOf<TorSetup> {
        TestStore(initialState: TorSetup.State()) {
            TorSetup()
        } withDependencies: {
            $0.walletStorage.exportTorSetupFlag = { torFlag }
        }
    }
}

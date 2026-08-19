//
//  PrivateDataConsentTests.swift
//  secantTests
//
//  Created by Lukáš Korba on 01.11.2023.
//

import Testing
import Foundation
import ComposableArchitecture
@testable import zodl_internal

@MainActor
@Suite struct PrivateDataConsentTests {
    @Test func urlsProperlyPrepared() async throws {
        let store = TestStore(
            initialState: .initial
        ) {
            PrivateDataConsent()
        }

        let URL = URL(string: "https://electriccoin.co")!

        store.dependencies.databaseFiles = .noOp
        store.dependencies.databaseFiles.dataDbURLFor = { _ in URL }

        await store.send(.onAppear) { state in
            state.dataDbURL = [URL]
        }

        await store.finish()
    }

    @Test func exportRequestSet() async throws {
        let store = TestStore(
            initialState: PrivateDataConsent.State(
                dataDbURL: [],
                exportBinding: false,
                exportLogsState: .initial,
                exportOnlyLogs: true
            )
        ) {
            PrivateDataConsent()
        }

        store.dependencies.logsHandler = .noOp

        await store.send(.exportRequested) { state in
            state.exportOnlyLogs = false
            state.isExportingData = true
        }

        await store.receive(.exportLogs(.start)) { state in
            state.exportLogsState.exportLogsDisabled = true
        }

        await store.receive(.exportLogs(.finished(nil))) { state in
            state.exportLogsState.exportLogsDisabled = false
            state.exportLogsState.isSharingLogs = true
            state.exportBinding = true
        }

        await store.finish()
    }

    @Test func exportLogsRequestSet() async throws {
        let store = TestStore(
            initialState: PrivateDataConsent.State(
                dataDbURL: [],
                exportBinding: false,
                exportLogsState: .initial,
                exportOnlyLogs: false
            )
        ) {
            PrivateDataConsent()
        }

        store.dependencies.logsHandler = .noOp

        await store.send(.exportLogsRequested) { state in
            state.exportOnlyLogs = true
            state.isExportingLogs = true
        }

        await store.receive(.exportLogs(.start)) { state in
            state.exportLogsState.exportLogsDisabled = true
        }

        await store.receive(.exportLogs(.finished(nil))) { state in
            state.exportLogsState.exportLogsDisabled = false
            state.exportLogsState.isSharingLogs = true
            state.exportBinding = true
        }
        await store.finish()
    }

    @Test func exportingDoneWhenFinished() async throws {
        let store = TestStore(
            initialState: PrivateDataConsent.State(
                dataDbURL: [],
                exportBinding: true,
                exportLogsState: .initial,
                isExportingData: true,
                isExportingLogs: true
            )
        ) {
            PrivateDataConsent()
        }

        await store.send(.shareFinished) { state in
            state.exportBinding = false
            state.isExportingData = false
            state.isExportingLogs = false
        }

        await store.finish()
    }

    @Test func exportURLs_logsOnly() async throws {
        let URLdb = URL(string: "http://db.url")!
        let URLlogs = URL(string: "http://logs.url")!

        let state = PrivateDataConsent.State(
            dataDbURL: [URLdb],
            exportBinding: true,
            exportLogsState: .init(zippedLogsURLs: [URLlogs]),
            exportOnlyLogs: true
        )

        #expect(state.exportURLs == [URLlogs])
    }

    @Test func exportURLs_dbAndlogs() async throws {
        let URLdb = URL(string: "http://db.url")!
        let URLlogs = URL(string: "http://logs.url")!

        let state = PrivateDataConsent.State(
            dataDbURL: [URLdb],
            exportBinding: true,
            exportLogsState: .init(zippedLogsURLs: [URLlogs]),
            exportOnlyLogs: false
        )

        #expect(state.exportURLs == [URLdb, URLlogs])
    }

    @Test func isExportPossible_NoBecauseNotAcknowledged() async throws {
        let state = PrivateDataConsent.State(
            dataDbURL: [],
            exportBinding: true,
            exportLogsState: .initial,
            exportOnlyLogs: true,
            isAcknowledged: false
        )

        #expect(!state.isExportPossible)
    }

    @Test func isExportPossible_NoBecauseExportingLogs() async throws {
        let state = PrivateDataConsent.State(
            dataDbURL: [],
            exportBinding: true,
            exportLogsState: .initial,
            exportOnlyLogs: true,
            isAcknowledged: true,
            isExportingLogs: true
        )

        #expect(!state.isExportPossible)
    }

    @Test func isExportPossible_NoBecauseExportingData() async throws {
        let state = PrivateDataConsent.State(
            dataDbURL: [],
            exportBinding: true,
            exportLogsState: .initial,
            exportOnlyLogs: true,
            isAcknowledged: true,
            isExportingData: true
        )

        #expect(!state.isExportPossible)
    }

    @Test func isExportPossible() async throws {
        let state = PrivateDataConsent.State(
            dataDbURL: [],
            exportBinding: true,
            exportLogsState: .initial,
            exportOnlyLogs: true,
            isAcknowledged: true
        )

        #expect(state.isExportPossible)
    }
}

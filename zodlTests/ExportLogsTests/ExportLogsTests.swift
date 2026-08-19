//
//  ExportLogsTests.swift
//  zodlTests
//
//  Created by Michal Fousek on 12.06.2026.
//

import Foundation
import Testing
import ComposableArchitecture
@testable import zodl_internal

/// Covers MOB-1367: the support-log export keeps no plaintext staging files behind,
/// and the produced ZIP is removed once the share sheet is closed.
///
/// Serialized because the live exporter tests share the same on-disk
/// `tmp/logs-exports` directory and read the process-global OSLog store.
@Suite(.serialized) struct ExportLogsTests {
    @MainActor @Test func shareSheetClosedRemovesExportsAndResetsURLs() async throws {
        let cleanupCalled = LockIsolated(false)

        let initialState = ExportLogs.State(
            zippedLogsURLs: [URL(fileURLWithPath: "/tmp/logs-exports/some/zashiPrivateData.zip")]
        )

        let store = TestStore(
            initialState: initialState
        ) {
            ExportLogs()
        } withDependencies: {
            $0.logsHandler.cleanupExports = { cleanupCalled.setValue(true) }
        }

        await store.send(.shareSheetClosed) {
            $0.zippedLogsURLs = []
        }

        await store.finish()

        #expect(cleanupCalled.value)
    }

    @Test func liveExportLeavesOnlyTheZipBehind() async throws {
        let handler = LogsHandlerClient.liveValue

        let zipURL = try await handler.exportAndStoreLogs(
            LoggerConstants.sdkLogs,
            LoggerConstants.tcaLogs,
            LoggerConstants.walletLogs
        )

        let unwrappedZipURL = try #require(zipURL)
        #expect(FileManager.default.fileExists(atPath: unwrappedZipURL.path))
        #expect(unwrappedZipURL.lastPathComponent == "zashiPrivateData.zip")

        // The plaintext staging directory is removed as soon as the ZIP exists.
        let stagingURL = unwrappedZipURL.deletingLastPathComponent().appendingPathComponent("zashiPrivateData", isDirectory: true)
        #expect(!FileManager.default.fileExists(atPath: stagingURL.path))

        try handler.cleanupExports()

        #expect(!FileManager.default.fileExists(atPath: unwrappedZipURL.path))
        let exportsRoot = FileManager.default.temporaryDirectory.appendingPathComponent("logs-exports", isDirectory: true)
        #expect(!FileManager.default.fileExists(atPath: exportsRoot.path))
    }

    @Test func liveCleanupRemovesLegacyStagingDirectory() throws {
        let handler = LogsHandlerClient.liveValue

        // Simulate a staging directory left behind by a previous app version.
        let legacyURL = FileManager.default.temporaryDirectory.appendingPathComponent("zashiPrivateData", isDirectory: true)
        try FileManager.default.createDirectory(at: legacyURL, withIntermediateDirectories: true)
        let legacyLogURL = legacyURL.appendingPathComponent("walletLogs.txt")
        try Data("legacy".utf8).write(to: legacyLogURL)
        #expect(FileManager.default.fileExists(atPath: legacyLogURL.path))

        try handler.cleanupExports()

        #expect(!FileManager.default.fileExists(atPath: legacyURL.path))

        // Cleanup with nothing to remove must not throw.
        try handler.cleanupExports()
    }
}

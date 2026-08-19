//
//  ExportTransactionHistoryTests.swift
//  zodlTests
//
//  Created by Michal Fousek on 12.06.2026.
//

import Foundation
import Testing
import ComposableArchitecture
@testable import zodl_internal

/// Covers MOB-1368: the tax CSV export is written into a unique, file-protected
/// temporary directory and removed again once the share sheet is closed.
///
/// Serialized because the live exporter tests share the same on-disk
/// `tmp/tax-exports` directory.
@Suite(.serialized) struct ExportTransactionHistoryTests {
    @MainActor @Test func shareSheetClosedRemovesExportAndResetsURL() async throws {
        let cleanupCalled = LockIsolated(false)

        var initialState = ExportTransactionHistory.State()
        initialState.dataURL = URL(fileURLWithPath: "/tmp/tax-exports/some/export.csv")

        let store = TestStore(
            initialState: initialState
        ) {
            ExportTransactionHistory()
        } withDependencies: {
            $0.taxExporter.cleanupExports = { cleanupCalled.setValue(true) }
        }

        await store.send(.shareSheetClosed) {
            $0.dataURL = .emptyURL
        }

        await store.finish()

        #expect(cleanupCalled.value)
    }

    @Test func liveExporterWritesEachExportIntoUniqueDirectory() throws {
        let exporter = TaxExporterClient.liveValue

        let firstURL = try exporter.cointrackerCSVfor([], "Zashi")
        #expect(FileManager.default.fileExists(atPath: firstURL.path))

        let secondURL = try exporter.cointrackerCSVfor([], "Zashi")
        #expect(FileManager.default.fileExists(atPath: secondURL.path))

        // Unique directory per export and stale exports purged by the next one.
        #expect(firstURL != secondURL)
        #expect(firstURL.deletingLastPathComponent() != secondURL.deletingLastPathComponent())
        #expect(!FileManager.default.fileExists(atPath: firstURL.path))

        try exporter.cleanupExports()
    }

    @Test func liveExporterCleanupRemovesAllExports() throws {
        let exporter = TaxExporterClient.liveValue

        let exportURL = try exporter.cointrackerCSVfor([], "Zashi")
        #expect(FileManager.default.fileExists(atPath: exportURL.path))

        try exporter.cleanupExports()

        #expect(!FileManager.default.fileExists(atPath: exportURL.path))
        let exportsRoot = FileManager.default.temporaryDirectory.appendingPathComponent("tax-exports", isDirectory: true)
        #expect(!FileManager.default.fileExists(atPath: exportsRoot.path))

        // Cleanup with nothing to remove must not throw.
        try exporter.cleanupExports()
    }
}

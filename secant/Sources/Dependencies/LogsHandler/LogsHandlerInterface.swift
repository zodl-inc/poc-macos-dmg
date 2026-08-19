//
//  LogsHandlerInterface.swift
//  Zashi
//
//  Created by Lukáš Korba on 30.01.2023.
//

import Foundation
import ComposableArchitecture

extension DependencyValues {
    var logsHandler: LogsHandlerClient {
        get { self[LogsHandlerClient.self] }
        set { self[LogsHandlerClient.self] = newValue }
    }
}

@DependencyClient
struct LogsHandlerClient {
    var exportAndStoreLogs: @Sendable (String, String, String) async throws -> URL?
    /// Removes all log-export artifacts (ZIPs and any staging files) from the
    /// temporary directory. Call it once the share sheet is closed so exported
    /// logs never outlive the share flow on disk.
    var cleanupExports: @Sendable () throws -> Void
}

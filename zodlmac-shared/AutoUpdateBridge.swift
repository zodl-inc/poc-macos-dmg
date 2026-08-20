import Foundation

// Bridge to Updater (defined in secant/Sources/Features/AutoUpdate/Updater.swift).
// zodlmac-shared and secant are compiled as a single module for the zodlmac-internal
// target via fileSystemSynchronizedGroups — this typealias makes the call site cleaner.
typealias AutoUpdater = Updater

import Testing
import Foundation
import ComposableArchitecture
import os
@testable import zodl_internal

@Suite struct AutomaticServerSelectionStorageTests {
    @Test func flagDefaultsToNilThenRoundTrips() {
        let storage = UserPreferencesStorage(
            defaultExchangeRate: Data(),
            defaultServer: Data(),
            userDefaults: .ephemeralForTests()
        )

        #expect(storage.automaticServerSelection == nil, "Flag must be nil before it is ever set")

        storage.setAutomaticServerSelection(true)
        #expect(storage.automaticServerSelection == true)

        storage.setAutomaticServerSelection(false)
        #expect(storage.automaticServerSelection == false)
    }
}

private extension UserDefaultsClient {
    /// An in-memory `UserDefaultsClient` backed by a dictionary, for tests that need real read/write
    /// without touching `UserDefaults.standard`. The dictionary is the protected state of an
    /// `OSAllocatedUnfairLock` (itself `Sendable`, so the `@Sendable` client closures capture only the
    /// lock). `uncheckedState:` / `withLockUnchecked` are used because the `Any` values can't satisfy
    /// the `Sendable` constraints of the checked `initialState:` / `withLock` APIs.
    static func ephemeralForTests() -> UserDefaultsClient {
        let storage = OSAllocatedUnfairLock<[String: Any]>(uncheckedState: [:])
        return UserDefaultsClient(
            objectForKey: { key in storage.withLockUnchecked { $0[key] } },
            remove: { key in storage.withLockUnchecked { $0[key] = nil } },
            setValue: { value, key in storage.withLockUnchecked { $0[key] = value } }
        )
    }
}

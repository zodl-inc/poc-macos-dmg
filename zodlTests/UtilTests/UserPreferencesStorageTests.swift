//
//  UserPreferencesStorageTests.swift
//  secantTests
//
//  Created by Lukáš Korba on 22.03.2022.
//

import Testing
import Foundation
@testable import zodl_internal

// Uses a real, named UserDefaults suite ("test") shared across its test methods,
// so the suite is serialized to keep each test's setup/teardown isolated.
@Suite(.serialized)
final class UserPreferencesStorageTests {
    // swiftlint:disable:next implicitly_unwrapped_optional
    var storage: UserPreferencesStorage!

    init() throws {
        let userDefaults = try #require(
            UserDefaults(suiteName: "test"),
            "UserPreferencesStorageTests: UserDefaults(suiteName: \"test\") failed to initialize"
        )
        storage = UserPreferencesStorage(
            defaultExchangeRate: Data(),
            defaultServer: Data(),
            userDefaults: .live(userDefaults: userDefaults)
        )
        storage.removeAll()
    }

    deinit {
        storage.removeAll()
    }

    // MARK: - Default values in the live UserDefaults environment

    @Test func defaultServer_defaultValue() throws {
        #expect(storage.server == nil, "User Preferences: `defaultServer` default doesn't match.")
    }

    // MARK: - Set new values in the live UserDefaults environment

    @Test func defaultServer_setNewValue() throws {
        let serverConfig = UserPreferencesStorage.ServerConfig(host: "host", port: 13, isCustom: true)
        try storage.setServer(serverConfig)

        #expect(storage.server == serverConfig, "User Preferences: `server` default doesn't match.")
    }

    // MARK: - Mocked user defaults vs. default values

    @Test func defaultServer_mocked() throws {
        let mockedUD = UserDefaultsClient(
            objectForKey: { _ in Data() },
            remove: { _ in },
            setValue: { _, _ in }
        )

        let mockedStorage = UserPreferencesStorage(
            defaultExchangeRate: Data(),
            defaultServer: Data(),
            userDefaults: mockedUD
        )

        #expect(mockedStorage.server == nil, "User Preferences: `server` default doesn't match.")
    }

    // MARK: - Remove all keys from the live UD environment

    @Test func removeAll() throws {
        let userDefaults = try #require(
            UserDefaults(suiteName: "test"),
            "User Preferences: UserDefaults(suiteName: \"test\") failed to initialize"
        )

        // fill in the data
        UserPreferencesStorage.Constants.allCases.forEach {
            userDefaults.set("anyValue", forKey: $0.rawValue)
        }

        // remove it
        storage?.removeAll()

        // check the presence
        UserPreferencesStorage.Constants.allCases.forEach {
            #expect(
                userDefaults.object(forKey: $0.rawValue) == nil,
                "User Preferences: key \($0.rawValue) should be removed but it's still present in User Defaults"
            )
        }
    }
}

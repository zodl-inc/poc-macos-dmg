//
//  TransactionGuardTestKey.swift
//  Zashi
//

import ComposableArchitecture

extension TransactionGuardClient: TestDependencyKey {
    /// Tests get a pass-through guard: submissions and switches run immediately, never blocking.
    static let testValue = TransactionGuardClient(
        acquire: {},
        tryAcquire: { true },
        release: {}
    )
}

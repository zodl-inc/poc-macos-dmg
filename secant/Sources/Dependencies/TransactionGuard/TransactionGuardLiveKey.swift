//
//  TransactionGuardLiveKey.swift
//  Zashi
//

import ComposableArchitecture

extension TransactionGuardClient: DependencyKey {
    static let liveValue: TransactionGuardClient = {
        let guardActor = TransactionGuard()
        return TransactionGuardClient(
            acquire: { try await guardActor.acquire() },
            tryAcquire: { await guardActor.tryAcquire() },
            release: { await guardActor.release() }
        )
    }()
}

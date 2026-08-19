//
//  TransactionGuard.swift
//  Zashi
//

import Foundation

/// A fair (FIFO) async mutex shared between server switches and transaction submissions so the two
/// can never overlap. The SDK's `switchTo(endpoint:)` tears down and rebuilds the synchronizer and
/// is unsafe while a transaction is being broadcast, so a submission and a switch must be exclusive.
actor TransactionGuard {
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, Error>
    }

    private var isBusy = false
    private var waiters: [Waiter] = []

    /// Wait until the guard is free, then take it. Callers must `release()` when done.
    /// Cancellation-aware: a task cancelled while parked here is removed from the queue and
    /// resumes by throwing `CancellationError` without taking the guard — so a hung holder can
    /// never wedge a waiter indefinitely.
    func acquire() async throws {
        guard isBusy else {
            isBusy = true
            return
        }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                // Cancelled before we parked: don't enqueue a doomed waiter.
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                waiters.append(Waiter(id: id, continuation: continuation))
            }
            // Ownership was handed to us by `release()`; `isBusy` is already true.
        } onCancel: {
            Task { await self.cancelWaiter(id) }
        }
    }

    /// Take the guard only if it is free right now; never waits. Returns `false` if busy.
    func tryAcquire() -> Bool {
        guard !isBusy else { return false }
        isBusy = true
        return true
    }

    /// Release the guard, handing ownership to the next waiter (FIFO) if there is one.
    func release() {
        if waiters.isEmpty {
            isBusy = false
        } else {
            let next = waiters.removeFirst()
            next.continuation.resume() // `isBusy` stays true — ownership transfers to the resumed waiter.
        }
    }

    /// Resume a still-parked waiter that was cancelled, throwing `CancellationError`. A no-op if
    /// `release()` already handed it ownership (it is no longer in the queue), so the guard's
    /// `isBusy` state is left untouched — the cancelled waiter never owned it.
    private func cancelWaiter(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        let waiter = waiters.remove(at: index)
        waiter.continuation.resume(throwing: CancellationError())
    }
}

/// Error thrown by `withTimeout` when `operation` does not finish within the deadline.
struct TransactionTimeoutError: Error {}

/// Default deadline for a server switch. `switchTo` does stop → validate-over-Tor → start; the
/// validation has its own 5s single-call timeout, but `start()` and Tor circuit setup have no
/// Swift-level deadline. On expiry `withTimeout` *cancels* `switchTo`; the guard is released only
/// once `switchTo` actually returns. If `switchTo` ignored cancellation and hung, the guard would
/// stay held — a deliberate trade-off that favours switch/submission exclusivity over liveness:
/// abandoning a half-applied switch could race a submission against a synchronizer still being rebuilt.
let serverSwitchTimeout: Duration = .seconds(60)

/// Race `operation` against a `duration` timer; whichever finishes first wins and the loser is
/// *cancelled* (a cancellation request, not a forced stop). Throws `TransactionTimeoutError` when
/// the timer wins.
///
/// Caveat: this is a structured task group, so it returns only once *both* children have finished.
/// If `operation` ignores cancellation and never returns, neither does this call — a hard deadline
/// is only achievable when `operation` is cancellation-aware.
func withTimeout<T: Sendable>(
    _ duration: Duration,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: duration)
            throw TransactionTimeoutError()
        }
        defer { group.cancelAll() }
        guard let result = try await group.next() else {
            throw TransactionTimeoutError()
        }
        return result
    }
}

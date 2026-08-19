import Testing
@testable import zodl_internal

// Several tests drive the shared `TransactionGuardClient.liveValue`, which is backed by a single
// process-global mutex actor. They must not run concurrently or they would contend on that guard,
// so the suite is serialized (matching XCTest's previous serial execution).
@Suite(.serialized) struct TransactionGuardTests {
    @Test func tryAcquireFailsWhileHeld() async {
        let guardActor = TransactionGuard()
        try? await guardActor.acquire()
        let acquired = await guardActor.tryAcquire()
        #expect(!acquired, "tryAcquire must fail while the guard is held")
        await guardActor.release()
        let acquiredAfter = await guardActor.tryAcquire()
        #expect(acquiredAfter, "tryAcquire must succeed after release")
    }

    @Test func switchIsSkippedWhileSubmissionActive() async {
        let client = TransactionGuardClient.liveValue
        let submissionStarted = AsyncBox()
        let releaseSubmission = AsyncBox()

        let submission = Task {
            try await client.withSubmission {
                await submissionStarted.signal()
                await releaseSubmission.wait()
            }
        }

        await submissionStarted.wait()
        let didSwitch = try? await client.switchIfIdle { /* would switch here */ }
        #expect(didSwitch == false, "Auto switch must skip while a submission is active")

        await releaseSubmission.signal()
        _ = try? await submission.value

        let didSwitchAfter = try? await client.switchIfIdle { }
        #expect(didSwitchAfter == true, "Auto switch must run once the submission finished")
    }

    @Test func manualSwitchWaitsForSubmission() async {
        let client = TransactionGuardClient.liveValue
        let order = OrderRecorder()
        let submissionStarted = AsyncBox()
        let releaseSubmission = AsyncBox()

        let submission = Task {
            try await client.withSubmission {
                await submissionStarted.signal()
                await releaseSubmission.wait()
                await order.record("submission-end")
            }
        }
        await submissionStarted.wait()

        let manual = Task {
            try await client.switchWaiting {
                await order.record("switch")
            }
        }

        // Give the manual switch a moment to park on the guard, then let the submission finish.
        try? await Task.sleep(for: .milliseconds(50))
        await releaseSubmission.signal()
        _ = try? await submission.value
        _ = try? await manual.value

        let recorded = await order.values
        #expect(recorded == ["submission-end", "switch"], "Manual switch must wait for the submission")
    }

    @Test func parkedSubmissionCancelledDoesNotRunBody() async {
        let client = TransactionGuardClient.liveValue
        let holderAcquired = AsyncBox()
        let releaseHolder = AsyncBox()
        let bodyRan = BoolBox()

        // A holder takes the guard and waits, forcing the next acquirer to park.
        let holder = Task {
            try await client.withSubmission {
                await holderAcquired.signal()
                await releaseHolder.wait()
            }
        }
        await holderAcquired.wait()

        // A second submission parks in acquire(); once cancelled its body must NOT run.
        let parked = Task {
            try await client.withSubmission {
                bodyRan.value = true
            }
        }

        // Let it park on the guard, then cancel it.
        try? await Task.sleep(for: .milliseconds(50))
        parked.cancel()

        // Release the holder; the parked task is resumed but should bail on cancellation.
        await releaseHolder.signal()
        _ = try? await holder.value
        _ = try? await parked.value

        #expect(!bodyRan.value, "A cancelled, parked submission must not run its body")
    }

    @Test func parkedAcquireUnblocksOnCancellationEvenIfHolderNeverReleases() async {
        let guardActor = TransactionGuard()
        // Holder takes the guard and never releases — simulates a hung switch.
        try? await guardActor.acquire()

        let parkedStarted = AsyncBox()
        let parked = Task { () -> Bool in
            await parkedStarted.signal()
            do {
                try await guardActor.acquire()
                return false // acquired — must not happen while the guard is held
            } catch is CancellationError {
                return true
            } catch {
                return false
            }
        }

        await parkedStarted.wait()
        try? await Task.sleep(for: .milliseconds(50)) // let it park in acquire()
        parked.cancel()

        let unblockedByCancellation = await parked.value
        #expect(
            unblockedByCancellation,
            "A parked acquire() must throw CancellationError when cancelled, even if the holder never releases"
        )
        // Cancelling the waiter must not have released the holder's guard.
        let stillHeld = await guardActor.tryAcquire()
        #expect(!stillHeld, "Cancelling a waiter must not release the guard held by another task")
    }

    @Test func withTimeoutThrowsWhenOperationExceedsDeadline() async {
        // Cooperative case only: Task.sleep honors cancellation, so withTimeout can return and throw.
        // A non-cancellable operation would not surface the timeout (see withTimeout / serverSwitchTimeout).
        do {
            try await withTimeout(.milliseconds(50)) {
                try await Task.sleep(for: .seconds(10))
            }
            Issue.record("withTimeout should have thrown TransactionTimeoutError")
        } catch is TransactionTimeoutError {
            // expected
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func withTimeoutReturnsValueWhenOperationFinishesInTime() async throws {
        let value = try await withTimeout(.seconds(5)) { 42 }
        #expect(value == 42)
    }

    @Test func switchWaitingReleasesGuardWhenSwitchTimesOut() async {
        let client = TransactionGuardClient.liveValue
        // A *cancellation-aware* switch body (Task.sleep) that overruns its timeout must release the
        // guard, not wedge it. This holds only because Task.sleep honors cancellation; a body that
        // ignored it would keep withTimeout (a structured task group) from returning and the guard
        // would stay held. See serverSwitchTimeout for why that trade-off is intentional.
        let timedOut: Void? = try? await client.switchWaiting {
            try await withTimeout(.milliseconds(50)) {
                try await Task.sleep(for: .seconds(10))
            }
        }
        #expect(timedOut == nil, "switchWaiting must rethrow the timeout")

        let didSwitch = try? await client.switchIfIdle { }
        #expect(didSwitch == true, "Guard must be free after a timed-out switch")
    }
}

/// Minimal async one-shot signal for ordering test steps.
private actor AsyncBox {
    private var signaled = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func signal() {
        signaled = true
        let w = waiters
        waiters.removeAll()
        w.forEach { $0.resume() }
    }
    func wait() async {
        if signaled { return }
        await withCheckedContinuation { waiters.append($0) }
    }
}

private final class BoolBox: @unchecked Sendable {
    var value = false
}

private actor OrderRecorder {
    private(set) var values: [String] = []
    func record(_ value: String) { values.append(value) }
}

import Foundation
import Testing
@testable import Cue

@MainActor
struct CueTests {
    @Test func nextPressRetriesFailedPreparation() async {
        let (events, continuation) = AsyncStream<Cue.Event>.makeStream()
        var preparationAttempts = 0
        var recordingAttempts = 0
        var firstAttemptProgress: Cue.PreparationProgressHandler?

        let cue = Cue(
            prepare: { progress in
                preparationAttempts += 1
                if preparationAttempts == 1 {
                    firstAttemptProgress = progress
                    progress("Downloading Parakeet model files (1 of 3)…")
                    throw TestFailure("prepare failed")
                }
            },
            events: events,
            frontmostApplication: { 42 },
            startRecording: { recordingAttempts += 1 },
            stopRecording: { "" },
            signal: { _ in },
            paste: { _, _ in }
        )

        let run = Task { await cue.run() }

        await expectEventually { cue.status == .blocked("prepare failed") }
        continuation.yield(.pressed)
        await expectEventually {
            cue.status == .recording
                && preparationAttempts == 2
                && recordingAttempts == 1
        }
        firstAttemptProgress?("Late update from the failed attempt")
        #expect(cue.status == .recording)
        continuation.yield(.released)
        await expectEventually { cue.status == .ready }
        continuation.finish()
        await run.value
    }

    @Test func nextPressRetriesRuntimeFailureWithoutPreparingAgain() async {
        let (events, continuation) = AsyncStream<Cue.Event>.makeStream()
        var preparationAttempts = 0
        var recordingAttempts = 0

        let cue = Cue(
            prepare: { _ in preparationAttempts += 1 },
            events: events,
            frontmostApplication: { 42 },
            startRecording: {
                recordingAttempts += 1
                if recordingAttempts == 1 {
                    throw TestFailure("recording failed")
                }
            },
            stopRecording: { "" },
            signal: { _ in },
            paste: { _, _ in }
        )

        let run = Task { await cue.run() }

        await expectEventually { cue.status == .ready }
        continuation.yield(.pressed)
        await expectEventually { cue.status == .blocked("recording failed") }
        continuation.yield(.pressed)
        await expectEventually {
            cue.status == .recording
                && preparationAttempts == 1
                && recordingAttempts == 2
        }
        continuation.yield(.released)
        await expectEventually { cue.status == .ready }
        continuation.finish()
        await run.value
    }

    @Test func pressAndReleasePastesOneTranscriptIntoTheCapturedApplication() async {
        let (events, continuation) = AsyncStream<Cue.Event>.makeStream()
        var calls: [String] = []

        let cue = Cue(
            prepare: { _ in
                calls.append("prepare")
            },
            events: events,
            frontmostApplication: {
                calls.append("target")
                return 42
            },
            startRecording: {
                calls.append("start")
            },
            stopRecording: {
                calls.append("stop")
                return "  hello from Parakeet  "
            },
            signal: { signal in
                calls.append("sound:\(signal)")
            },
            paste: { text, processIdentifier in
                calls.append("paste:\(text):\(processIdentifier)")
            }
        )

        let run = Task { await cue.run() }

        await expectEventually { cue.status == .ready }
        continuation.yield(.pressed)
        await expectEventually { cue.status == .recording }
        continuation.yield(.released)
        await expectEventually { cue.status == .ready && calls.count == 7 }
        continuation.finish()
        await run.value

        #expect(calls == [
            "prepare",
            "target",
            "start",
            "sound:started",
            "sound:stopped",
            "stop",
            "paste:hello from Parakeet:42",
        ])
    }

    @Test func preparationProgressIsVisibleAndLateUpdatesDoNotRegressReady() async {
        let (events, eventContinuation) = AsyncStream<Cue.Event>.makeStream()
        var advanceFromChecking: CheckedContinuation<Void, Never>?
        var advanceFromDownloading: CheckedContinuation<Void, Never>?
        var capturedProgress: Cue.PreparationProgressHandler?

        let cue = Cue(
            prepare: { progress in
                capturedProgress = progress
                progress("Checking Parakeet model files…")
                await withCheckedContinuation { advanceFromChecking = $0 }
                progress("Downloading Parakeet model files (2 of 4)…")
                await withCheckedContinuation { advanceFromDownloading = $0 }
            },
            events: events,
            frontmostApplication: { 42 },
            startRecording: {},
            stopRecording: { "" },
            signal: { _ in },
            paste: { _, _ in }
        )

        let run = Task { await cue.run() }

        await expectEventually {
            cue.status == .preparing("Checking Parakeet model files…")
        }
        #expect(cue.status.message == "Checking Parakeet model files…")

        advanceFromChecking?.resume()
        await expectEventually {
            cue.status == .preparing("Downloading Parakeet model files (2 of 4)…")
        }
        #expect(cue.status.message == "Downloading Parakeet model files (2 of 4)…")

        advanceFromDownloading?.resume()
        await expectEventually { cue.status == .ready }

        capturedProgress?("Late update after preparation")
        #expect(cue.status == .ready)

        eventContinuation.finish()
        await run.value
    }

    private struct TestFailure: LocalizedError {
        let errorDescription: String?

        init(_ message: String) {
            errorDescription = message
        }
    }

    private func expectEventually(
        _ condition: @escaping @MainActor () -> Bool,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async {
        for _ in 0 ..< 100 {
            if condition() {
                return
            }
            try? await Task.sleep(for: .milliseconds(10))
        }

        Issue.record("Condition was not satisfied", sourceLocation: sourceLocation)
    }
}

import Foundation
import Testing
@testable import Cue

@MainActor
struct CueAppModelDictationTests {
    @Test func handlePushToTalkReleasedInsertsTranscriptAndStoresVisibleMetrics() async {
        let rig = CueAppModelTestRig()
        rig.transcriptionService.result = "milestone three transcript"
        rig.insertionService.pasteDuration = 0.18
        let model = rig.model

        await model.launch()
        model.handlePushToTalkPressed()
        await yieldUntil { model.state.session == .recording }
        model.handlePushToTalkReleased()
        await yieldUntil { rig.insertionService.insertCallCount == 1 }

        #expect(model.state.session == .idle)
        #expect(rig.insertionService.insertedTexts == ["milestone three transcript"])
        #expect(model.state.latencyMetrics != nil)
        #expect(model.state.latencyMetrics?.pasteDuration == 0.18)
        #expect(rig.transcriptionService.startRecordingCallCount == 1)
        #expect(rig.transcriptionService.stopRecordingCallCount == 1)
        #expect(!rig.transcriptionService.lastSaveDebugCapture)
        #expect(rig.insertionService.insertCallCount == 1)
        #expect(rig.soundService.playRecordingStartedCallCount == 1)
        #expect(rig.soundService.playRecordingStoppedCallCount == 1)
    }

    @Test func debugCaptureToggleIsPassedToTranscription() async {
        let rig = CueAppModelTestRig()
        let model = rig.model
        model.debugCapturesEnabled = true

        await model.launch()
        model.handlePushToTalkPressed()
        await yieldUntil { model.state.session == .recording }
        model.handlePushToTalkReleased()
        await yieldUntil { rig.insertionService.insertCallCount == 1 }

        #expect(rig.transcriptionService.lastSaveDebugCapture)
    }

    @Test func enabledRecordingPillReplacesCumulativePreviewTextAtomically() async {
        let rig = CueAppModelTestRig()
        let model = rig.model
        model.recordingPillEnabled = true

        await model.launch()
        model.handlePushToTalkPressed()
        await yieldUntil { model.state.session == .recording }

        let previewHandler = rig.transcriptionService.previewHandler
        rig.transcriptionService.reportPreview("rough words still changing")

        #expect(previewHandler != nil)
        #expect(model.state.recordingPreviewText == "rough words still changing")
        #expect(rig.defaults.bool(forKey: CueAppConfiguration.recordingPillEnabledDefaultsKey))

        rig.transcriptionService.reportPreview("rough words now revised as a complete sentence")
        #expect(model.state.recordingPreviewText == "rough words now revised as a complete sentence")

        model.handlePushToTalkReleased()
        await yieldUntil { model.state.session == .idle }

        #expect(model.state.recordingPreviewText.isEmpty)

        previewHandler?(.text("late preview from the previous run"))
        #expect(model.state.recordingPreviewText.isEmpty)
    }

    @Test func recordingPillSurfacesAndRecoversFromUnavailableLivePreview() async {
        let rig = CueAppModelTestRig()
        let model = rig.model
        model.recordingPillEnabled = true

        await model.launch()
        model.handlePushToTalkPressed()
        await yieldUntil { model.state.session == .recording }

        rig.transcriptionService.reportPreviewUnavailable()

        #expect(model.state.isRecordingPreviewUnavailable)
        #expect(model.state.recordingPreviewText.isEmpty)

        rig.transcriptionService.reportPreview("preview recovered")

        #expect(!model.state.isRecordingPreviewUnavailable)
        #expect(model.state.recordingPreviewText == "preview recovered")
    }

    @Test func recordingPillKeepsUnavailableUpdateReportedBeforeRecordingStartReturns() async {
        let rig = CueAppModelTestRig()
        let model = rig.model
        model.recordingPillEnabled = true
        rig.transcriptionService.previewUpdateDuringStart = .unavailable

        await model.launch()
        model.handlePushToTalkPressed()
        await yieldUntil { model.state.session == .recording }

        #expect(model.state.isRecordingPreviewUnavailable)
        #expect(model.state.recordingPreviewText.isEmpty)
    }

    @Test func disabledRecordingPillDoesNotRequestPreviewWork() async {
        let rig = CueAppModelTestRig()
        let model = rig.model

        await model.launch()
        model.handlePushToTalkPressed()
        await yieldUntil { model.state.session == .recording }

        #expect(!model.recordingPillEnabled)
        #expect(rig.transcriptionService.previewHandler == nil)
    }

    @Test func recordingPillCanBeHiddenDuringAnActiveRun() async {
        let rig = CueAppModelTestRig()
        let model = rig.model
        model.recordingPillEnabled = true

        await model.launch()
        model.handlePushToTalkPressed()
        await yieldUntil { model.state.session == .recording }
        rig.transcriptionService.reportPreview("private rough text")

        model.recordingPillEnabled = false

        #expect(!model.recordingPillEnabled)
        #expect(model.state.recordingPreviewText.isEmpty)
        await yieldUntil { rig.transcriptionService.disableRecordingPreviewCallCount == 1 }
        rig.transcriptionService.reportPreview("late text after disabling")
        #expect(model.state.recordingPreviewText.isEmpty)

        model.handlePushToTalkReleased()
        await yieldUntil { model.state.session == .idle }
    }

    @Test func releasingPushToTalkClearsRoughPreviewBeforeFinalTranscriptionCompletes() async {
        let rig = CueAppModelTestRig()
        let model = rig.model
        model.recordingPillEnabled = true
        rig.transcriptionService.suspendsStopRecording = true

        await model.launch()
        model.handlePushToTalkPressed()
        await yieldUntil { model.state.session == .recording }
        rig.transcriptionService.reportPreview("raw text that should disappear on release")

        model.handlePushToTalkReleased()
        await yieldUntil { rig.transcriptionService.stopRecordingCallCount == 1 }

        #expect(model.state.session == .transcribing)
        #expect(model.state.recordingPreviewText.isEmpty)

        rig.transcriptionService.resumeStopRecording()
        await yieldUntil { model.state.session == .idle }
    }

    @Test func releaseWhileRecordingStartIsSuspendedStillStopsAndInserts() async {
        let rig = CueAppModelTestRig()
        rig.transcriptionService.suspendsStartRecording = true
        let model = rig.model

        await model.launch()
        model.handlePushToTalkPressed()
        await yieldUntil { rig.transcriptionService.startRecordingCallCount == 1 }

        model.handlePushToTalkReleased()
        rig.transcriptionService.resumeStartRecording()
        await yieldUntil { rig.insertionService.insertCallCount == 1 }

        #expect(rig.transcriptionService.stopRecordingCallCount == 1)
        #expect(rig.insertionService.insertedTexts == [rig.transcriptionService.result])
        #expect(model.state.session == .idle)
    }

    @Test func launchFailureMovesStateToErrorWhenPermissionsAreSatisfied() async {
        let rig = CueAppModelTestRig()
        rig.transcriptionService.prepareError = CueError.modelDownloadFailed("offline")
        let model = rig.model

        await model.launch()

        #expect(model.presentation.errorMessage == "Cue could not prepare the small.en model: offline")
        #expect(model.state.modelStatus == .failed)
        #expect(rig.insertionService.insertCallCount == 0)
        #expect(rig.soundService.playErrorCallCount == 0)
    }

    @Test func successfulRetryClearsUnexpectedPreparationFailure() async {
        let rig = CueAppModelTestRig()
        rig.transcriptionService.prepareError = NSError(
            domain: "CueTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "temporary filesystem failure"]
        )
        let model = rig.model

        await model.launch()

        #expect(model.state.modelStatus == .failed)
        #expect(model.state.session == .failed(.unexpected("temporary filesystem failure")))

        rig.transcriptionService.prepareError = nil
        await model.retryModelPreparation()

        #expect(model.state.modelStatus == .ready)
        #expect(model.state.session == .idle)
    }

    @Test func successfulRetryDoesNotClearANewerPermissionFailure() async {
        let rig = CueAppModelTestRig()
        rig.transcriptionService.prepareError = CueError.modelLoadFailed("temporary failure")
        let model = rig.model
        await model.launch()

        rig.transcriptionService.prepareError = nil
        rig.transcriptionService.suspendsPrepareModel = true
        let retry = Task { await model.retryModelPreparation() }
        await yieldUntil { rig.transcriptionService.prepareCallCount == 2 }

        rig.permissionService.snapshot = CuePermissionSnapshot(
            microphone: .denied,
            accessibility: .granted
        )
        model.handlePushToTalkPressed()
        rig.transcriptionService.resumePrepareModel()
        await retry.value

        #expect(model.state.modelStatus == .ready)
        #expect(model.state.session == .failed(.microphonePermissionDenied))
    }

    @Test func transcriptionFailureDoesNotAttemptPaste() async {
        let rig = CueAppModelTestRig()
        rig.transcriptionService.stopRecordingError = CueError.transcriptionFailed("backend offline")
        let model = rig.model

        await model.launch()
        model.handlePushToTalkPressed()
        await yieldUntil { model.state.session == .recording }
        model.handlePushToTalkReleased()
        await yieldUntil { model.state.currentFailure != nil }

        #expect(model.presentation.errorMessage == "Cue could not transcribe the recording: backend offline")
        #expect(rig.insertionService.insertCallCount == 0)
        #expect(rig.soundService.playRecordingStartedCallCount == 1)
        #expect(rig.soundService.playRecordingStoppedCallCount == 1)
        #expect(rig.soundService.playErrorCallCount == 1)
    }

    @Test func startCuePlaysImmediatelyWhenAnAcceptedStartAttemptLaterFails() async {
        let rig = CueAppModelTestRig()
        rig.transcriptionService.startRecordingError = CueError.recordingFailed("audio device busy")
        let model = rig.model

        await model.launch()
        model.handlePushToTalkPressed()
        await yieldUntil { model.state.currentFailure != nil }

        #expect(rig.soundService.playRecordingStartedCallCount == 1)
        #expect(rig.soundService.playErrorCallCount == 1)
        #expect(model.presentation.errorMessage == "Cue could not start recording: audio device busy")
        #expect(model.state.session == .failed(.recordingFailed("audio device busy")))
    }

    @Test func pasteFailurePlaysErrorSound() async {
        let rig = CueAppModelTestRig()
        rig.insertionService.insertError = CueError.pasteFailed("event bridge down")
        let model = rig.model

        await model.launch()
        model.handlePushToTalkPressed()
        await yieldUntil { model.state.session == .recording }
        model.handlePushToTalkReleased()
        await yieldUntil { model.state.currentFailure != nil }

        #expect(rig.soundService.playRecordingStartedCallCount == 1)
        #expect(rig.soundService.playRecordingStoppedCallCount == 1)
        #expect(rig.soundService.playErrorCallCount == 1)
        #expect(model.presentation.errorMessage == "Cue could not paste the transcript: event bridge down")
    }
}

@MainActor
struct SystemSoundServiceTests {
    @Test func cuePlaybackRestartsTheDedicatedSoundInstanceEachTime() {
        let recordingStartedSound = FakePlayableSound()
        let recordingStoppedSound = FakePlayableSound()
        let errorSound = FakePlayableSound()
        let service = SystemSoundService(
            recordingStartedSound: recordingStartedSound,
            recordingStoppedSound: recordingStoppedSound,
            errorSound: errorSound
        )

        service.playRecordingStarted()
        service.playRecordingStarted()
        service.playRecordingStopped()
        service.playError()

        #expect(recordingStartedSound.stopCallCount == 2)
        #expect(recordingStartedSound.playCallCount == 2)
        #expect(recordingStoppedSound.stopCallCount == 1)
        #expect(recordingStoppedSound.playCallCount == 1)
        #expect(errorSound.stopCallCount == 1)
        #expect(errorSound.playCallCount == 1)
    }
}

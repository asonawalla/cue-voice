# Cue Onboarding Flow

Last validated: March 11, 2026

## Purpose

This document is the source of truth for Cue's onboarding flow as it is implemented today.

It describes shipped behavior, not historical flows or unused internal plumbing.

## Product Shape

Cue does not implement a multi-step onboarding wizard.

Cue is a menu bar app that:

1. launches in the background
2. evaluates permission and model readiness state
3. exposes setup UI only when the user opens the main window or triggers push-to-talk before setup is complete

The main window is suppressed by default and is opened from the menu bar menu.

## Required Setup Conditions

Cue is only fully ready to record when all of the following are true:

- Microphone permission is granted.
- Accessibility permission is granted.
- The local speech model has been prepared successfully.

If either permission is missing, Cue does not warm the model.

## Entry Points Into Onboarding

There are two live entry points into setup:

### 1. App launch and main-window flow

On app launch, Cue:

1. reads the current permission snapshot
2. marks permissions as loaded
3. attempts model warmup only if both permissions are already granted

If permissions are incomplete, the main window shows permission setup cards instead of the ready-state controls.

### 2. First use through push-to-talk

Push-to-talk is also an onboarding entry point.

On push-to-talk press, Cue refreshes permissions first.

From there:

- If microphone permission is `notDetermined`, Cue runs a first-use microphone bootstrap by triggering the microphone permission request.
- If microphone permission is denied, Cue does not start recording and shows a microphone permission error.
- If microphone is granted but Accessibility is missing, Cue does not start recording and shows an Accessibility permission error.
- If both permissions are granted but the model is not ready, Cue attempts model warmup instead of recording.
- Recording starts only after permissions and model readiness are satisfied.

Important: the first-use bootstrap is microphone-only. Accessibility remains an explicit separate step.

## Permission UI Contract

The setup UI reflects the current permission snapshot.

### Microphone

- `notDetermined`: show `Grant Microphone Access`
- `denied`: show `Open Microphone Settings`
- `granted`: show no microphone action

### Accessibility

- `notGranted`: show `Grant Accessibility Access` and `Open Accessibility Settings`
- `granted`: show no Accessibility action

`Open Accessibility Settings` currently triggers an Accessibility request call before opening System Settings.

## Return From System Settings

Cue does not currently require an app restart to complete onboarding.

Instead, when Cue becomes active again after the user returns from System Settings, it:

1. refreshes the permission snapshot
2. clears any resolved permission-related failure state
3. attempts model warmup if both permissions are now granted

This return-to-app refresh behavior is the live completion path for setup.

## Main Window States

The main window has three onboarding-relevant states:

### 1. Setup state

Shown when permissions are incomplete.

The user sees:

- the current top-level status in the header
- one or two permission cards
- any current error message

### 2. Model retry state

Shown only when:

- permissions are fully configured
- the model is not ready
- model preparation is not currently in progress

This state offers `Retry Model Preparation`.

### 3. Ready state

Shown only when permissions are fully configured and the setup prompt is no longer needed.

The user sees:

- push-to-talk shortcut controls
- the shortcut summary
- debug capture controls

## Menu Bar Status Contract

The menu bar status reflects onboarding state:

- before permission evaluation completes: `Checking Permissions`
- missing microphone: `Microphone Required`
- missing Accessibility: `Accessibility Required`
- permissions granted but model not ready: `Preparing Model`
- fully ready: `Ready`

## Failure Handling During Onboarding

Cue may enter a failed session state during onboarding, but permission-related failures are cleared automatically when a permission refresh shows the missing permission has been granted.

Non-permission failures are not cleared by permission refresh alone.

## Explicit Non-Goals Of The Current Flow

The following are not part of the current onboarding contract:

- a dedicated onboarding window
- a step that asks the user to restart Cue
- automatic recording after microphone bootstrap while Accessibility is still missing
- model warmup before both permissions are granted

## Legacy Plumbing That Is Not Part Of The Live Flow

Production code still contains a restart/relaunch path wired through the app action, app model, workflow coordinator, setup coordinator, and permission service.

Nothing in the current presentation layer emits that action.

As of March 11, 2026, the restart path is not part of Cue's live onboarding behavior and should not be treated as a user-visible setup step.

## Implementation References

Primary implementation references:

- `Cue/CueApp.swift`
- `Cue/CueAppModel.swift`
- `Cue/CueWorkflowCoordinator.swift`
- `Cue/CueSetupCoordinator.swift`
- `Cue/CueDictationCoordinator.swift`
- `Cue/CuePresentation.swift`
- `Cue/CueMainWindowView.swift`
- `Cue/CuePermissionService.swift`
- `Cue/CueDomain.swift`

Validation coverage:

- `CueTests/CueAppPresentationTests.swift`
- `CueTests/CueAppModelPermissionTests.swift`
- `CueTests/CueAppModelLifecycleTests.swift`
- `CueTests/CueHotkeyManagerTests.swift`
- `CueUITests/CueUITests.swift`

## Change Rule

If implementation changes the onboarding contract, update this document in the same change before treating the new behavior as settled.

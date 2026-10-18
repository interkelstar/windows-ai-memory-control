# Agent workflow

Goal: reduce unnecessary Windows AI background residency while keeping the NPU, Windows AI APIs, normal lexical search, and user control over individual features.

## Before changes

1. Read README and docs/controls.md. Run `scripts/WindowsAIMemory.ps1 -Action Status`. Confirm Windows build, CPU/NPU, RAM, current settings, and Search/AI Fabric service states. Never assume an adapter LUID survives reboot or a failed module read means no model exists.
2. Explain the lost features: semantic file/image matching and Settings-agent suggestions/actions. Check whether the user actually wants Recall/Click to Do Off; use their ordinary settings, not a policy lockout. Do not delete Recall history.
3. Apply is experimental on a single validated hardware/build combination. Do not bypass its gates by default. For another build, inspect the controls and obtain an informed choice before `-AllowUntestedSystem`.

## Apply and preserve

- Use the supplied scripts, not a generic debloat bundle. Preserve the first baseline. Existing values/keys may predate this toolkit.
- Keep WSAIFabricSvc and WSearch Running/Automatic. Do not stop/disable AI Fabric, NPU/GPU drivers, Windows AI packages, or private inference runtimes.
- Do not change registry owners/ACLs. A one-shot LOCAL SERVICE task for the fixed preload key is permitted by this implementation; confirm its removal. No persistent elevated task, service, watchdog, or UAC bypass.
- Gallery has a separate App Content Search preference. Close the app before modifying its config. Never copy its complete state file/provider keys into the repository or diagnostics.
- Install the current-user manual-unload shortcut if requested. Explain that UAC may still appear; do not promise silent elevation. The shortcut must point to the stable LocalAppData copy, not a temporary checkout.

## Validate honestly

1. Arrange a user-controlled reboot. Use the ordinary browser, Settings, and Windows search. Observe at least 6 minutes, covering the observed 300-second preload timer, and inspect memory/model-host residency. A single zero reading is not proof of permanent absence.
2. Test Phi Silica and OCR explicitly through Gallery, recording actual results. Do not treat model availability as a generated answer.
3. Close the client and observe natural residency **without terminating hosts**. Distinguish an app's process exit from system model eviction. If memory remains, report it.
4. Private NPU models are a separate runtime. Confirm its device is NPU, then test its configured idle deadline without calling unload/closing the server early. A successful idle-eviction test needs backend exit and released allocations; the small server process may legitimately remain.
5. If test-created system sessions are manually cleared afterward, record that separately. Do not label that automatic eviction. Do not keep resetting models to make an observation look clean.
6. Close AI clients before testing manual Unload. It interrupts Windows AI calls. Do not terminate private runtimes or unmatched process paths. Restore the pre-test application/server state afterward.

## Repo work

Run tests in Windows PowerShell 5.1 and PowerShell 7. Use fixture tests for rollback/conflicts. Never Apply/Restore on a user's live machine just to get a green test if it would change their chosen state. Document integration-test limits. Do not commit real registry backups, raw ETW/XML, dumps, personal paths, API credentials, usernames, or conversation exports. Keep facts for social writing separate from public operational documentation.

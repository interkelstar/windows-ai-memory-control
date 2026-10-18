# Controls, scope, and sources

This page describes the implementation, not an official Microsoft recommendation. Tested system: HP OmniBook X Flip 14-kc0xxx, Ryzen AI 7 445, Windows 11 Pro 26H2 **26300.9711**. Re-check after Windows updates.

## Semantic file indexing — internal

```text
HKLM\SOFTWARE\Microsoft\Windows Search\SemanticIndexer
EnableSemanticIndexing (DWORD) = 0
```

On the measured build, installed `mssrch.dll` checks this exact input and follows its explicit opt-out branch for zero. After the indexer restarts, Windows computes `IsSemanticIndexingAllowed = 0`. The tool never writes that computed output. The existing value was 1. A reboot/ordinary use and lexical index queries were checked. This does not prove every application-specific semantic search API is disabled.

[Microsoft's indexing documentation](https://support.microsoft.com/en-us/windows/experience/performance-optimization/search-indexing-in-windows) describes semantic indexing enabled by default on Copilot+ PCs and location/file-type exclusions. Classic/Enhanced are scope choices, not an AI-off switch. This exact global registry input is **not documented there as a public supported policy**.

## Automatic language preload — internal

```text
HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\WorkloadManager\SkipLanguageModelPreload
```

This is an **empty subkey whose presence matters**, not a DWORD value. The measured WorkloadsSessionManager had an approximately 300-second automatic language preload. Creating this key produced the observed skip-preload ETW branch while explicit Phi Silica requests still succeeded. It does not impose a universal idle-eviction deadline.

The Windows-owned parent grants LOCAL SERVICE the needed write access on the measured system. The toolkit runs a single fixed-purpose helper under that account using a temporary scheduled task. Its private job directory is administrator-owned, grants LOCAL SERVICE access only for that job, and is cleaned up after task removal. **No Windows registry ACL/owner changes and no persistent task are used.** If the helper cannot use the existing rights, stop; do not take ownership, disable security, or grant broad registry permissions.

## Settings agent — documented policy, build/edition dependent

```text
HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsAI
DisableSettingsAgent (DWORD) = 1
```

[Microsoft's configuration guide](https://learn.microsoft.com/en-us/windows/configuration/settings/agent) and [WindowsAI Policy CSP](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-windowsai#disablesettingsagent) describe this policy. Applicability listings can differ by edition/channel; the public CSP lists narrower availability than all Windows 11 Pro systems. The measured Pro build honored the setting. Do not promise that every Pro build does.

The Settings agent and semantic file indexing are distinct. Disabling the agent leaves static Settings search and can leave semantic Settings search available; don't describe it as a blanket removal of every natural-language match. [Microsoft explains these separate Settings experiences](https://support.microsoft.com/en-us/windows/experience/exploring-windows-settings).

## AI Dev Gallery's own search — optional per-user setting

GUI: **Settings → App Content Search → Enable app content search**.

The `IsAppContentSearchEnabled` Boolean is in Gallery's current-user `LocalState/state.json`. When true, Gallery's [main-window source](https://github.com/microsoft/ai-dev-gallery/blob/main/AIDevGallery/MainWindow.xaml.cs) starts its AppContentIndexer at launch. With it false, sample search falls back to in-memory lexical search. This preference does not disable the sample APIs.

The companion script requires Gallery closed, checks the exact schema, backs up only the Boolean, and changes only that Boolean. Future app schemas should be handled in the app UI, not guessed.

## Manual unload

`Unload` terminates only allowlisted Microsoft-package `WorkloadsSessionHost.exe` processes. It is not per-app eviction, not a graceful SDK `Dispose`, and not a guarantee that another active client won't request a model again. Close clients first. It does not terminate WorkloadsSessionManager, stop/reconfigure WSAIFabricSvc/WSearch, or terminate private NPU runtimes. GPU/NPU driver resets are not used.

Microsoft recommends disposing [LanguageModel and context objects](https://learn.microsoft.com/en-us/windows/ai/apis/language-model-best-practices). That guidance is not evidence of a system-wide 5-minute eviction guarantee. In the measured Gallery test, system model memory remained after the client exited; an attempted 120-second idle policy was ineffective and was reverted. The toolkit does not include that failed tweak.

Recall snapshots, Click to Do, app background permissions, ordinary search highlights, and accelerator drivers are separate controls. This toolkit does not administratively lock Recall/Click to Do or delete their history/data.

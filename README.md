# Windows AI Memory Control

[Русская инструкция](README.ru.md) · [Agent workflow](AGENTS.md) · [Controls and evidence](docs/controls.md)

Keep a Copilot+ PC responsive without disabling its NPU or Windows AI APIs. This small PowerShell toolkit makes selected Windows AI background loading optional and provides a **manual, on-demand command to release Windows AI model sessions** after using an AI app.

Built from measurements on an **HP OmniBook X Flip 14-kc0xxx, AMD Ryzen AI 7 445 / Radeon 840M, 24 GB RAM, Windows 11 Pro 26H2 build 26300.9711**. This is a narrowly tested configuration, not a universal Windows debloater.

## What it changes

| Control | Result | Support status |
|---|---|---|
| Windows semantic file indexing | Ordinary lexical search remains; file/image search by meaning is disabled | Internal registry control; tested on the build above |
| Automatic language-model preloading | Prevents the observed automatic preload; explicit Windows AI API calls remain available | Internal registry key; tested on the build above |
| Settings AI agent | Disables agentic suggestions/actions in Settings; normal Settings navigation/search remains | Documented policy; edition/build applicability varies |
| AI Dev Gallery's own App Content Search | Falls back to ordinary sample-name search; API samples remain available | Optional per-user Gallery preference |

**It preserves** Windows AI Fabric (`WSAIFabricSvc`), Windows Search (`WSearch`), NPU/GPU drivers, and private runtimes such as Lemonade/FastFlowLM. It does not install or configure local LLMs. It does not change Recall, Click to Do, System Restore, backups, Secure Boot, or power settings. Set unused Recall/Click to Do features **Off in their normal Settings UI** if that is your chosen profile; no administrative lockouts are imposed.

## Quick start

Download/clone the repository to a normal local folder. Inspect the scripts before running them. Use Windows PowerShell 5.1 or PowerShell 7 on 64-bit Windows.

```powershell
# Read-only, no elevation; default action is Status.
powershell.exe -NoProfile -File .\scripts\WindowsAIMemory.ps1

# Preview only: no writes, process termination, backup creation, or UAC.
powershell.exe -NoProfile -File .\scripts\WindowsAIMemory.ps1 -Action Apply -AllowExperimental -WhatIf

# Apply after reading docs/controls.md. Windows requests administrator approval.
powershell.exe -NoProfile -File .\scripts\WindowsAIMemory.ps1 -Action Apply -AllowExperimental

# Optional: close AI Dev Gallery, then disable its own semantic sample search.
powershell.exe -NoProfile -File .\scripts\Set-GallerySearch.ps1 -Mode Disable

# Install current-user Desktop/Start Menu shortcuts and a stable command.
powershell.exe -NoProfile -File .\scripts\Install-Shortcuts.ps1
```

The Apply action refuses untested OS/CPU combinations by default. `-AllowUntestedSystem` is an explicit override **after reviewing the controls**, not a compatibility guarantee. Apply also requires the existing semantic-indexer key and already-running Automatic Search/AI Fabric services. It does not change Windows registry ownership or permissions. Reboot manually after applying; the tool never forces a restart.

Execution policy may block downloaded unsigned scripts. Review/unblock only these downloaded files or run them with **process-scoped** `-ExecutionPolicy Bypass`; do not change machine-wide execution policy. UAC remains enabled.

## Release Windows AI memory without an agent

Close AI Dev Gallery and finish other Windows AI requests. Click **Free Windows AI memory** on the Desktop/Start Menu, or run:

```powershell
powershell.exe -NoProfile -File .\scripts\WindowsAIMemory.ps1 -Action Unload
```

The shortcut's stable command also lives at:

```text
%LOCALAPPDATA%\WindowsAIMemoryControl\Tools\Free-WindowsAI-Memory.cmd
```

The command terminates only `WorkloadsSessionHost.exe` instances whose executable path matches the Microsoft `windowsworkload.manager.*` package and publisher identity. It leaves the session manager, services, drivers, and your own `flm.exe`/Lemonade/LM Studio processes alone. It refuses to run while AI Dev Gallery is open. Other Windows AI clients cannot all be enumerated: **unloading interrupts outstanding Windows AI requests**. This is a deliberate manual reset after use, not graceful per-client disposal or an idle timer.

An administrator UAC prompt is expected when system hosts need termination. If no hosts exist, the command returns without elevation. No persistent privileged task, service, autorun, PATH modification, UAC bypass, or background watchdog is installed. The shortcut copies its scripts to LocalAppData, so moving this checkout does not break it. Re-run the installer after updating the toolkit.

## Restore

```powershell
powershell.exe -NoProfile -File .\scripts\WindowsAIMemory.ps1 -Action Restore
powershell.exe -NoProfile -File .\scripts\Set-GallerySearch.ps1 -Mode Restore
```

Machine originals are saved **before changes** in `%ProgramData%\WindowsAIMemoryControl\state.json`, in an administrator-owned directory. Repeated Apply does not overwrite the baseline. Restore preserves originally absent values and pre-existing preload keys, and refuses unexpected later changes/nonempty keys. It restores **the state before this tool first ran**, not guessed Windows factory defaults. If the machine was already tuned, that tuned state is its baseline. A failed Apply attempts rollback and retains its backup/error information. No success should be assumed after a reported failure.

The Gallery backup contains only its Boolean preference, never the complete preferences file/provider credentials. Restore it as the same normal Windows user. Its UI toggle is **Gallery → Settings → App Content Search → Enable app content search**.

## What was verified, and what was not

- After reboot and ordinary Settings/browser/search use: no system model hosts, about 10.3 GiB available RAM (56% used on the observed 24 GB machine). This is an example observation, not a promised amount of free memory.
- Phi Silica generated text and Windows OCR recognized an image after the background controls were applied.
- Opening Gallery with its own semantic search enabled loaded OCR/search models. With that preference disabled, reopening its home page did not load them.
- Qwen via Lemonade/FastFlowLM ran on the NPU with context 4096 and **automatically unloaded after about 302 seconds**; its backend exited and NPU allocations returned to zero without an unload command.
- **Windows AI API sessions did not fully unload naturally** after Gallery closed: about 3.1 GiB remained after 380 seconds in that test. These sessions were manually reset after measuring. Do not describe this toolkit as universal automatic Windows AI model eviction.

The 5-minute Qwen timeout belongs to that private runtime's configuration, not this toolkit. A running model host does not by itself prove ongoing NPU computation; shared accelerator RAM is part of system RAM, not extra memory to add to the total. Adapter IDs change after reboot; Status deliberately reports all raw adapter counters rather than guessing which one is the NPU.

Only the specified hardware/build was observed end to end. Future Windows/SDK updates can change internal controls. See [validation](docs/validation.md) for packaged-script testing limits and the agent checklist.

## Tests

```powershell
powershell.exe -NoProfile -File .\tests\Run-Tests.ps1
pwsh -NoProfile -File .\tests\Run-Tests.ps1
```

The dependency-free suite tests absent-value restoration, pre-existing settings, partial-Apply rollback planning, conflicting external changes, nonempty-key protection, exact process-path allowlisting, and Gallery preference editing. It does not mutate system settings or terminate processes.

MIT licensed. This project is independent of Microsoft, AMD, HP, LM Studio, and Lemonade.

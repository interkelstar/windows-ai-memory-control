# Validation

## Original measured system

- HP OmniBook X Flip 14-kc0xxx; AMD Ryzen AI 7 445 / Radeon 840M; 24 GB RAM.
- Windows 11 Pro 26H2, build 26300.9711; observations October 2026.
- Background controls survived reboot; a check about 25 minutes after boot/normal use showed no system model hosts, approximately 10.3 GiB free and 56% RAM used.
- Explicit Phi Silica generation and Windows OCR succeeded with AI Fabric running.
- With Gallery's own App Content Search enabled, startup loaded OCR/search sessions. With it disabled, reopening and leaving its home page open did not load system models.
- Following explicit Windows AI tests, Gallery exited but approximately 3.1 GiB remained resident after 380 seconds. One manual cleanup was recorded after measuring. Universal automatic Windows AI API eviction was **not** established.
- Independent Qwen NPU inference (Lemonade/FastFlowLM, context 4096) succeeded. Its backend exited automatically about 302 seconds after the answer; NPU memory returned to zero without an unload command. This is that runtime's own policy.

These are one-machine observations, not minimum RAM guarantees, proof that all workloads use the NPU, or proof that every future Windows build honors these keys.

## Packaged scripts

The dependency-free test suite runs on Windows PowerShell 5.1 and PowerShell 7 and does not change machine state. It covers planning correct restoration of originally absent values, existing preload keys/settings, partial changes, external-change conflicts, nonempty-key refusal, process path allowlisting, and byte-preserving Gallery preference changes. It also parses all shipped scripts.

`-WhatIf` performs no writes/elevation and is a high-level preview, not a complete compatibility probe. Status reads the current machine and exposes unavailable module information honestly.

Fresh-system Apply/Restore across different Windows builds is not covered by fixture tests. The protected-key helper and live unload path need targeted integration checks on the supported system. See `release-validation.json` for the actual packaged-release checks; do not substitute the original investigation for packaged-script test coverage.

## Reproduction checklist

Record build/hardware, original values, service startup states, available physical RAM, system host modules if readable, and accelerator allocations. Check baseline after reboot and normal search/Settings use, then explicit API use and natural idle as different phases. Run a private NPU workload separately. Stop test clients before a manual cleanup; verify required services/runtimes survived. Never publish raw machine captures without reviewing and sanitizing them.

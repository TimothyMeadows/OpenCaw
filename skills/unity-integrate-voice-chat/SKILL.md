---
name: unity-integrate-voice-chat
description: Integrate explicitly selected Vivox voice channels with identity, microphone permission, participant controls and lifecycle-safe teardown.
engines: [UNITY]
---

# Unity Integrate Voice Chat

## When to use

Build Vivox communication into a selected Unity project. Ordinary game sound effects and mixer authoring remain with `unity-build-audio`.

## Activation and inputs

Run `commands/resolve-engine.sh` and `commands/resolve-skill.sh unity-integrate-voice-chat` before edits or tool launches; require effective `UNITY`, compatibility and permitted output scope. Inspect the installed Vivox SDK, authentication provider, target devices, authorized development environment, channel types, privacy/moderation requirements and transmission policy. Do not create accounts, activate Vivox, obtain tokens or record voice implicitly.

## Workflow

1. Map initialize/login/channel join/leave/logout to explicit owners. Use server-authorized identity and channel access where required; keep token-signing keys outside the client and all tokens outside reports.
2. Handle microphone permission before transmitting. Preserve a usable receive-only or disabled state when permission is denied or devices are unavailable. Make push-to-talk, local microphone mute, local participant mute and moderator actions distinct.
3. Register participant, device and connection handlers once for the active login generation. Reconnect and scene transitions must not duplicate UI rows or resurrect an old channel after logout.
4. For positional channels, select audible/conversational distances and update rate against game scale and budget. Supply the locally owned actor to the SDK's Unity position API; do not manually repeat the SDK's coordinate conversion.
5. On teardown stop transmission, remove owned handlers, leave channels and log out through bounded awaited operations. Ignore stale presentation callbacks while retaining responsibility for late resource cleanup.

Read [voice ownership](references/voice-lifecycle.md) when implementing channels, permissions and devices.

## Verification and output

Provide package/channel configuration, permission and device-state transitions, connection/participant lifecycle tests and sanitized evidence. Test denied/revoked permission, unplugged devices, reconnect, duplicate callbacks, scene teardown and each mute scope. Physical capture/playback and spatial intelligibility require consenting participants on real target devices; headless or simulated checks cannot certify audible voice. Mark unavailable SDK/account/device checks blocked/not-run and keep observations under resolved `.opencaw/.cache`.

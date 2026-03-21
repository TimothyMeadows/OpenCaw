# EMBEDDED_FIRMWARE.md

This repository follows an **embedded firmware architecture** for MCU and RTOS systems.

Goals:
- deterministic behavior under constrained resources
- explicit timing and memory ownership
- hardware abstraction with clear board boundaries
- robust error handling and recovery paths

## Core rules

- Prefer static allocation after startup.
- Keep ISRs minimal and non-blocking.
- Separate drivers, platform adapters, and application logic.
- Fail fast on hardware initialization and communication errors.

## Suggested structure

```text
firmware/
  app/
  drivers/
  platform/
  rtos/
  tests/
```

## Language rules

- Primary implementation language is C (optionally C++ for isolated modules).
- Keep compiler flags strict and warnings-as-errors.
- Avoid undefined behavior and implementation-defined assumptions.

## Platform rules

- Keep ESP-IDF/Zephyr/STM32/Nordic specifics in `platform/`.
- Do not leak board-specific constants across modules.
- Pin SDK and toolchain versions for reproducible builds.

## Testing and validation

- Unit test protocol and state-machine logic off-target where possible.
- Run hardware-in-the-loop validation for timing-sensitive paths.
- Track stack/heap high-water marks under stress scenarios.
- Validate watchdog recovery and OTA/bootloader rollback behavior.

When in doubt:

**Prefer predictable firmware behavior over clever optimizations.**

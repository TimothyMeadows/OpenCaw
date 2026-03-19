# MAUI.md

This repository follows a **.NET MAUI client architecture**.

Goals:
- thin UI pages/views
- clear separation between presentation, application logic, and platform integration
- testable view models and services
- platform-specific behavior isolated behind abstractions

## Core rules

- Keep pages/views focused on rendering and binding
- Prefer view models for state and interaction flow
- Isolate device/platform capabilities behind interfaces
- Keep business logic out of code-behind when possible

## Suggested structure

```text
src/
  MyApp.Maui/
    Views/
    ViewModels/
    Services/
    Platforms/
    Resources/
```

## ViewModel rules

- Prefer explicit commands and observable state
- Avoid direct platform/service coupling when an abstraction can be used
- Keep long-running operations cancellable where appropriate

## Platform rules

- Platform-specific implementations belong in platform folders or infrastructure-style services
- Do not leak platform details into core view or view model logic unless unavoidable

## Testing

- unit test view models and service logic
- integration test platform abstractions where practical
- keep UI interaction flows deterministic and observable

When in doubt:

**Move logic out of the view and into view models or service abstractions.**

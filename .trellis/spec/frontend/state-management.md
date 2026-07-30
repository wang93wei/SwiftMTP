# State Management

> How state is managed in this project.

---

## Overview

<!--
Document your project's state management conventions here.

Questions to answer:
- What state management solution do you use?
- How is local vs global state decided?
- How do you handle server state?
- What are the patterns for derived state?
-->

(To be filled by the team)

---

## State Categories

- View-only interaction state, such as the selected row ID inside a SwiftUI
  `List`, stays in local `@State`.
- Application state and USB session state stay in the appropriate
  `@MainActor` manager, such as `DeviceManager`.
- Views request state transitions through manager methods that enforce backend
  invariants; they do not publish application state directly.

---

## When to Use Global State

<!-- Criteria for promoting state to global -->

(To be filled by the team)

---

## Server State

<!-- How server data is cached and synchronized -->

(To be filled by the team)

---

## Common Mistakes

- Do not bind `List(selection:)` directly to an `@Published` application
  property. SwiftUI can write that binding during a view update, producing
  `Publishing changes from within view updates is not allowed`.
- Bind selection to a stable local identifier, then yield out of the view
  update before calling the manager action. For device selection, always call
  `DeviceManager.selectDevice(_:)`; assigning `selectedDevice` directly skips
  the provider-bound MTP session open.

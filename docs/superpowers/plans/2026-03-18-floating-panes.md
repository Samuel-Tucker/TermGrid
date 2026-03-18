# Pack 014: Floating Panes Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `Cmd+Shift+F` floating terminal pane that overlays the grid for quick one-off commands.

**Architecture:** Create `FloatingPaneView` (draggable overlay with terminal + compose), add `floatingSession` to `TerminalSessionManager`, mount as overlay on `gridContent` in ContentView.

**Tech Stack:** Swift, SwiftUI, SwiftTerm, Swift Testing

---

## File Structure

| Action | File | Responsibility |
|--------|------|---------------|
| Create | `Sources/TermGrid/Views/FloatingPaneView.swift` | Floating terminal pane UI with drag gesture |
| Modify | `Sources/TermGrid/Terminal/TerminalSessionManager.swift` | Add `floatingSession`, `createFloatingSession()`, `killFloatingSession()`, update `killAll()` |
| Modify | `Sources/TermGrid/Views/ContentView.swift` | Add `showFloatingPane` state, overlay on `gridContent`, notification receiver |
| Modify | `Sources/TermGrid/TermGridApp.swift` | Add `Cmd+Shift+F` Commands menu item |
| Modify | `Sources/TermGrid/CommandPalette/CommandRegistry.swift` | Add notification name + "Quick Terminal" command |

---

### Task 1: Create FloatingPaneView

**Files:**
- Create: `Sources/TermGrid/Views/FloatingPaneView.swift`

- [ ] **Step 1: Write FloatingPaneView**

```swift
// Sources/TermGrid/Views/FloatingPaneView.swift
import SwiftUI
import SwiftTerm

struct FloatingPaneView: View {
    let session: TerminalSession
    let onDismiss: () -> Void

    @State private var offset: CGSize = .zero
    @State private var dragOffset: CGSize = .zero

    var body: some View {
        VStack(spacing: 0) {
            // Title bar — draggable
            HStack {
                Text("Quick Terminal")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Theme.headerText)
                Spacer()
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.headerIcon)
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Theme.headerBackground)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        dragOffset = value.translation
                    }
                    .onEnded { value in
                        offset.width += value.translation.width
                        offset.height += value.translation.height
                        dragOffset = .zero
                    }
            )

            Theme.divider.frame(height: 1)

            // Terminal
            VStack(spacing: 0) {
                TerminalContainerView(session: session)
                    .id(session.sessionID)

                ComposeBox { text in
                    session.send(text)
                }
            }
        }
        .frame(width: 350, height: 250)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.cellBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.accent, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.4), radius: 12)
        .offset(x: offset.width + dragOffset.width, y: offset.height + dragOffset.height)
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `swift build 2>&1 | tail -10`

- [ ] **Step 3: Commit**

```bash
git add Sources/TermGrid/Views/FloatingPaneView.swift
git commit -m "feat: add FloatingPaneView UI with drag gesture"
```

---

### Task 2: Add Floating Session to TerminalSessionManager

**Files:**
- Modify: `Sources/TermGrid/Terminal/TerminalSessionManager.swift`

- [ ] **Step 1: Add floatingSession property and methods**

After existing properties (line 15), add:

```swift
var floatingSession: TerminalSession? = nil
```

Add methods after existing `killAll()`:

```swift
@discardableResult
func createFloatingSession() -> TerminalSession {
    floatingSession?.kill()
    let session = TerminalSession(
        cellID: UUID(),
        workingDirectory: FileManager.default.homeDirectoryForCurrentUser.path,
        sessionType: .primary,
        environment: buildEnvironment()
    )
    floatingSession = session
    return session
}

func killFloatingSession() {
    floatingSession?.kill()
    floatingSession = nil
}
```

- [ ] **Step 2: Update killAll() to include floating session**

In `killAll()`, add before the closing brace:

```swift
floatingSession?.kill()
floatingSession = nil
```

- [ ] **Step 3: Build and run tests**

Run: `swift test 2>&1 | tail -20`
Expected: All tests pass

- [ ] **Step 4: Commit**

```bash
git add Sources/TermGrid/Terminal/TerminalSessionManager.swift
git commit -m "feat: add floatingSession lifecycle to TerminalSessionManager"
```

---

### Task 3: Wire Floating Pane into ContentView + Shortcuts

**Files:**
- Modify: `Sources/TermGrid/Views/ContentView.swift`
- Modify: `Sources/TermGrid/TermGridApp.swift`
- Modify: `Sources/TermGrid/CommandPalette/CommandRegistry.swift`

- [ ] **Step 1: Add state and notification name**

In ContentView, add after `commandRegistry` state (line 17):

```swift
@State private var showFloatingPane = false
```

In CommandRegistry.swift's `Notification.Name` extension, add:

```swift
static let toggleFloatingPane = Notification.Name("TermGrid.toggleFloatingPane")
```

- [ ] **Step 2: Add overlay on gridContent**

In ContentView's `gridContent` computed property, add `.overlay` after the `.padding(padding)` closing brace (around line 100):

```swift
.overlay(alignment: .bottomTrailing) {
    if showFloatingPane, let session = sessionManager.floatingSession {
        FloatingPaneView(session: session, onDismiss: {
            sessionManager.killFloatingSession()
            showFloatingPane = false
        })
        .padding(16)
    }
}
```

- [ ] **Step 3: Add notification receiver**

In ContentView's body, add after existing `.onReceive` handlers:

```swift
.onReceive(NotificationCenter.default.publisher(for: .toggleFloatingPane)) { _ in
    if showFloatingPane {
        sessionManager.killFloatingSession()
        showFloatingPane = false
    } else {
        sessionManager.createFloatingSession()
        showFloatingPane = true
    }
}
```

- [ ] **Step 4: Add Cmd+Shift+F to NSEvent monitor**

In ContentView's `.onAppear` NSEvent monitor, add alongside the Cmd+Shift+P handler:

```swift
if event.type == .keyDown,
   event.modifierFlags.contains([.command, .shift]),
   event.charactersIgnoringModifiers == "f" {
    if showFloatingPane {
        sessionManager.killFloatingSession()
        showFloatingPane = false
    } else {
        sessionManager.createFloatingSession()
        showFloatingPane = true
    }
    return nil
}
```

- [ ] **Step 5: Add Commands menu in TermGridApp**

In TermGridApp's `.commands` modifier, add after the Command Palette button:

```swift
Button("Quick Terminal") {
    NotificationCenter.default.post(name: .toggleFloatingPane, object: nil)
}
.keyboardShortcut("f", modifiers: [.command, .shift])
```

- [ ] **Step 6: Build and run all tests**

Run: `swift test 2>&1 | tail -20`
Expected: All tests pass

- [ ] **Step 7: Commit**

```bash
git add Sources/TermGrid/Views/ContentView.swift Sources/TermGrid/TermGridApp.swift Sources/TermGrid/CommandPalette/CommandRegistry.swift
git commit -m "feat: wire floating pane with Cmd+Shift+F shortcut"
```

---

### Task 4: Manual Verification

- [ ] **Step 1: Build and launch**

Run: `swift build 2>&1 | tail -5`
Verify:
- `Cmd+Shift+F` opens floating terminal in bottom-right
- Terminal is functional (type commands)
- Title bar is draggable
- X button dismisses
- `Cmd+Shift+F` again dismisses
- Quitting app kills floating session cleanly

- [ ] **Step 2: Run full test suite**

Run: `swift test 2>&1 | tail -20`
Expected: All tests pass

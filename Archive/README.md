# Archive

Superseded code, kept for reference. **Not part of the Swift package build.**

- `TreescopeApp/` — the original native SwiftUI macOS viewer GUI.
- `TreescopeViewerCore/` — its client/session layer (async TCP `TransportClient`, `InspectorSession`).
- `TreescopeViewerCoreTests/` — tests for the above, including the original TCP end-to-end test.

These were replaced by the browser viewer (`Web/`) served over HTTP + WebSocket. The Swift wire
model in `TreescopeProtocol` is unchanged in shape (now with an explicit JSON contract), so this
code is straightforward to revive if a native viewer is ever wanted again.

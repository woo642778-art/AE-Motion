AE Motion Extensions v2.0.1 — Preset Studio stabilization

Device-confirmed fixes only:
- Restores a visible back path from Preset Studio.
- Reworks Apply Preset so a tool-opened library applies back to that original tool.

Apply behavior:
- Speed Remap shows only compatible speed presets and returns to the existing Speed Remap Studio after applying.
- Easing Curve, Camera Shake, and Color Palette use the same tool-aware behavior.
- Standalone Preset Studio explicitly resolves supported targets instead of using the first raw target string.
- Duplicate Apply taps are ignored.
- Failed application preserves the existing tool state.

No other v2.0 feature is intentionally changed.

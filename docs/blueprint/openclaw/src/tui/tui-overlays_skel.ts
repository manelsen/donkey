import type { Component, TUI } from "@mariozechner/pi-tui";
type OverlayHost = Pick<TUI, "showOverlay" | "hideOverlay" | "hasOverlay" | "setFocus">;
export function createOverlayHandlers(host: OverlayHost, fallbackFocus: Component);

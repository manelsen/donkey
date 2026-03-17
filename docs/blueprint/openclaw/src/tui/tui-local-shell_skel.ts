import { spawn } from "node:child_process";
import type { Component, SelectItem } from "@mariozechner/pi-tui";
import { createSearchableSelectList } from "./components/selectors.js";
type LocalShellDeps = {
export function createLocalShellRunner(deps: LocalShellDeps);

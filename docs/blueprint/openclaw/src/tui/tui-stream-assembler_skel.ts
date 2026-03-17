import {
type RunStreamState = {
type BoundaryDropMode = "off" | "streamed-only" | "streamed-or-incoming";
function extractTextBlocksAndSignals(message: unknown):;
function isDroppedBoundaryTextBlockSubset(params:;
function shouldPreserveBoundaryDroppedText(params:;
export class TuiStreamAssembler {

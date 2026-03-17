type SessionTranscriptUpdate = {
type SessionTranscriptListener = (update: SessionTranscriptUpdate) => void;
export function onSessionTranscriptUpdate(listener: SessionTranscriptListener): () => void;
export function emitSessionTranscriptUpdate(sessionFile: string): void;

import { app, session } from 'electron';

// Fallback for cases where Electron session is not ready yet.

function linkAbortSignal(source: AbortSignal, controller: AbortController): void {
}

export async function fetchWithSystemProxy(url: string, options: RequestInit = {}): Promise<Response> {
      const message = error instanceof Error ? error.message : String(error);


export async function fetchJsonWithTimeout<T>(

  if (options.signal) {
  }


let data: unknown;
    if (rawText) {
    }

    if (!response.ok) {
    }

    if (error instanceof Error && error.name === 'AbortError') {
    }

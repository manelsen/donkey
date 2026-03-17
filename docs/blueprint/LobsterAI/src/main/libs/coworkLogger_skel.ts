import { app } from 'electron';
import fs from 'fs';
import path from 'path';


let logFilePath: string | null;

function getLogFilePath(): string {
}

function rotateIfNeeded(): void {
}

function formatTimestamp(): string {
}

export function coworkLog(level: 'INFO' | 'WARN' | 'ERROR', tag: string, message: string, extra?: Record<string, unknown>): void {
    if (extra) {
    }
    // Logging should never throw

export function getCoworkLogPath(): string {

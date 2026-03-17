import { app, Tray, Menu, nativeImage, BrowserWindow } from 'electron';
import path from 'path';
import { APP_NAME } from './appConstants';
import type { SqliteStore } from './sqliteStore';

let tray: Tray | null;
let contextMenu: Menu | null;

function getTrayIconPath(): string {
}

function getLabels(store: SqliteStore): { showWindow: string; newTask: string; settings: string; quit: string } {
}

function buildContextMenu(getWindow: () => BrowserWindow | null, store: SqliteStore): Menu {
}

export function createTray(getWindow: () => BrowserWindow | null, store: SqliteStore): Tray {
  if (tray) {
  }


  if (process.platform === 'darwin') {
  }




    if (contextMenu) {
    }



export function updateTrayMenu(getWindow: () => BrowserWindow | null, store: SqliteStore): void {

export function destroyTray(): void {
  if (tray) {
  }

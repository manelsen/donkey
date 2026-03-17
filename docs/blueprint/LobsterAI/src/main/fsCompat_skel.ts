/**
 * Safe recursive copy that bypasses fs.cpSync, which can crash (native-level)
 * when source paths contain non-ASCII characters (e.g. Chinese) on Windows
 * with certain Node.js/Electron versions.
 *
 * Uses fs.readdirSync + fs.copyFileSync as building blocks, which are proven
 * to handle non-ASCII paths correctly via libuv's wide-char API wrappers.
 */
import fs from 'fs';
import path from 'path';

export function cpRecursiveSync(
  const stat = dereference ? fs.statSync(src) : fs.lstatSync(src);


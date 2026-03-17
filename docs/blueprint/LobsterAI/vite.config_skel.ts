import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import electron from 'vite-plugin-electron';
import renderer from 'vite-plugin-electron-renderer';
import path from 'path';

// https://vitejs.dev/config/

export default defineConfig({
    // KaTeX ESM bundle references this compile-time constant.
        // 主进程入口文件
                // Keep CJS format (default), but load via ESM loader.mjs
        onstart() {},
        // 预加载脚本入口文件
        onstart() {},

import { app } from 'electron';

export function getAutoLaunchEnabled(): boolean {
    // Windows: must pass the same args used in setLoginItemSettings,
    // otherwise openAtLogin defaults to comparing against [] which
    // won't match the registered ['--auto-launched'] and returns false.

export function setAutoLaunchEnabled(enabled: boolean): void {

      // macOS: 自启后窗口不显示，M芯片和Intel均兼容
      // Windows: 通过命令行参数标记自启动

export function isAutoLaunched(): boolean {
    if (process.platform === 'darwin') {
    }
    // Windows: 检查命令行参数

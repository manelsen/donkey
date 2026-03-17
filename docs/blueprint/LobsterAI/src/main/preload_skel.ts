import { contextBridge, ipcRenderer } from 'electron';

// 暴露安全的 API 到渲染进程
    // 普通 API 请求（非流式）

    // 流式 API 请求

    // 取消流式请求

    // 监听流式数据
      const handler = (_event: any, chunk: string) => callback(chunk);

    // 监听流式完成

    // 监听流式错误
      const handler = (_event: any, error: string) => callback(error);

    // 监听流式取消
      const handler = (_event: any, ...args: any[]) => func(...args);
      const handler = (_event: any, state: { isMaximized: boolean; isFullscreen: boolean; isFocused: boolean }) => callback(state);
    // Session management

    // Permission handling

    // Configuration
      const handler = (_event: any, data: any) => callback(data);
    // Stream event listeners
      const handler = (_event: any, data: { sessionId: string; message: any }) => callback(data);
      const handler = (_event: any, data: { sessionId: string; messageId: string; content: string }) => callback(data);
      const handler = (_event: any, data: { sessionId: string; request: any }) => callback(data);
      const handler = (_event: any, data: { sessionId: string; claudeSessionId: string | null }) => callback(data);
      const handler = (_event: any, data: { sessionId: string; error: string }) => callback(data);
      const handler = (_event: any, data: any) => callback(data);
    // Configuration

    // Gateway control

    // Status

    // Event listeners
      const handler = (_event: any, status: any) => callback(status);
      const handler = (_event: any, message: any) => callback(message);
    // Task CRUD

    // Execution

    // Run history

    // Stream event listeners
      const handler = (_event: any, data: any) => callback(data);
      const handler = (_event: any, data: any) => callback(data);

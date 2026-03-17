# LobsterAI Architecture - IPC Communication

## Overview

LobsterAI é uma aplicação Electron com dois processos principais:

1. **Main Process** (`src/main/`): Processo Node.js com acesso direto ao sistema operacional, sistema de arquivos, e APIs nativas
2. **Renderer Process** (`src/renderer/`): Processo Chromium executando React UI, isolado por segurança

A comunicação entre esses processos é feita via **IPC (Inter-Process Communication)** através de canais definidos e tipados.

## Process Model

```
┌─────────────────────────────────────────────────────────────┐
│                    Main Process                            │
│  ┌─────────────┐  ┌─────────────┐  ┌───────────────┐  │
│  │ CoworkRunner│  │ IMGateway   │  │  SqliteStore  │  │
│  │             │  │ Manager     │  │               │  │
│  └─────────────┘  └─────────────┘  └───────────────┘  │
│         │                │                 │              │
│         └────────────────┼─────────────────┘              │
│                          ▼                               │
│                  ┌───────────┐                          │
│                  │ ipcMain   │  <-- IPC Handlers         │
│                  └───────────┘                          │
└───────────────────────────┬───────────────────────────────┘
                            │ IPC
                            │ (invoke/send)
                            │
┌───────────────────────────┼───────────────────────────────┐
│ Renderer Process          ▼                               │
│  ┌──────────────────────────────────────────────────┐      │
│  │              preload.ts                         │      │
│  │         (contextBridge.exposeInMainWorld)       │      │
│  └──────────────────────────────────────────────────┘      │
│                          │                                 │
│                          ▼                                 │
│  ┌──────────────────────────────────────────────────┐      │
│  │         window.electron.* API                   │      │
│  └──────────────────────────────────────────────────┘      │
│                          │                                 │
│         ┌────────────────┴────────────────┐              │
│         ▼                                 ▼              │
│  ┌──────────┐                      ┌──────────┐        │
│  │ Services │                      │ Redux    │        │
│  │ (IPC     │                      │ Store    │        │
│  │ Wrappers)│                      │ (Slices) │        │
│  └──────────┘                      └──────────┘        │
│                          │                                 │
│                          ▼                                 │
│  ┌──────────────────────────────────────────────────┐      │
│  │              React Components                   │      │
│  └──────────────────────────────────────────────────┘      │
└─────────────────────────────────────────────────────────────┘
```

## Security Model

A arquitetura de segurança do LobsterAI segue os melhores práticas do Electron:

1. **Context Isolation**: Ativado (`contextIsolation: true`)
2. **Node Integration**: Desativado no renderer (`nodeIntegration: false`)
3. **Preload Script**: Único ponto de contato exposto ao renderer via `contextBridge`
4. **Sandbox**: Ativado para isolamento adicional

Isso garante que:
- O renderer não tem acesso direto ao Node.js ou APIs do sistema
- Todas as operações sensíveis passam pelo processo principal
- O preload script valida e filtra todas as chamadas IPC

## IPC Channels

### Invokable Channels (Request/Response)

Canais usados para chamadas síncronas/assíncronas onde o resultado é esperado:

#### Store Operations
```typescript
ipcMain.handle('store:get', (event, key) => any);
ipcMain.handle('store:set', (event, key, value) => void);
ipcMain.handle('store:remove', (event, key) => void);
```

#### Cowork Session Management
```typescript
ipcMain.handle('cowork:session:start', (event, options) => {
  success: boolean;
  session?: CoworkSession;
  error?: string;
});
ipcMain.handle('cowork:session:continue', (event, options) => { ... });
ipcMain.handle('cowork:session:stop', (event, sessionId) => { ... });
ipcMain.handle('cowork:session:delete', (event, sessionId) => { ... });
ipcMain.handle('cowork:session:get', (event, sessionId) => { ... });
ipcMain.handle('cowork:session:list', () => { ... });
```

#### Cowork Configuration
```typescript
ipcMain.handle('cowork:config:get', () => { config: CoworkConfig });
ipcMain.handle('cowork:config:set', (event, config) => void);
ipcMain.handle('cowork:memory:listEntries', (event, input) => { ... });
ipcMain.handle('cowork:memory:createEntry', (event, input) => { ... });
ipcMain.handle('cowork:memory:updateEntry', (event, input) => { ... });
ipcMain.handle('cowork:memory:deleteEntry', (event, input) => { ... });
ipcMain.handle('cowork:memory:getStats', () => { ... });
```

#### Cowork Streaming Events
```typescript
ipcMain.handle('cowork:permission:respond', (event, { requestId, result }) => void);
ipcMain.handle('cowork:sandbox:status', () => { ... });
ipcMain.handle('cowork:sandbox:install', () => { ... });
```

#### Skills Management
```typescript
ipcMain.handle('skills:list', () => { skills: Skill[] });
ipcMain.handle('skills:setEnabled', (event, { id, enabled }) => void);
ipcMain.handle('skills:delete', (event, id) => void);
ipcMain.handle('skills:download', (event, source) => void);
ipcMain.handle('skills:getConfig', (event, skillId) => { ... });
ipcMain.handle('skills:setConfig', (event, skillId, config) => void);
ipcMain.handle('skills:autoRoutingPrompt', () => { prompt: string });
```

#### MCP (Model Context Protocol) Servers
```typescript
ipcMain.handle('mcp:list', () => { servers: McpServer[] });
ipcMain.handle('mcp:create', (event, data) => void);
ipcMain.handle('mcp:update', (event, id, data) => void);
ipcMain.handle('mcp:delete', (event, id) => void);
ipcMain.handle('mcp:setEnabled', (event, { id, enabled }) => void);
ipcMain.handle('mcp:fetchMarketplace', () => { data: MarketplaceData });
```

#### IM (Instant Messaging) Gateway
```typescript
ipcMain.handle('im:config:get', () => { config: IMConfig });
ipcMain.handle('im:config:set', (event, config) => void);
ipcMain.handle('im:gateway:start', (event, platform) => void);
ipcMain.handle('im:gateway:stop', (event, platform) => void);
ipcMain.handle('im:gateway:test', (event, platform, configOverride) => { ... });
ipcMain.handle('im:status:get', () => { status: IMStatus });
```

#### Scheduled Tasks
```typescript
ipcMain.handle('scheduledTask:list', () => { tasks: ScheduledTask[] });
ipcMain.handle('scheduledTask:get', (event, id) => { task: ScheduledTask });
ipcMain.handle('scheduledTask:create', (event, input) => { task: ScheduledTask });
ipcMain.handle('scheduledTask:update', (event, id, input) => void);
ipcMain.handle('scheduledTask:delete', (event, id) => void);
ipcMain.handle('scheduledTask:toggle', (event, id, enabled) => void);
ipcMain.handle('scheduledTask:runManually', (event, id) => void);
ipcMain.handle('scheduledTask:stop', (event, id) => void);
ipcMain.handle('scheduledTask:listRuns', (event, taskId, limit, offset) => { ... });
ipcMain.handle('scheduledTask:listAllRuns', (event, limit, offset) => { ... });
```

#### Window Management
```typescript
ipcMain.on('window-minimize', () => mainWindow?.minimize());
ipcMain.on('window-maximize', () => mainWindow?.maximize() || mainWindow?.unmaximize());
ipcMain.on('window-close', () => mainWindow?.close());
ipcMain.handle('window:isMaximized', () => boolean);
ipcMain.handle('window:showSystemMenu', (event, position) => void);
```

#### Dialog Operations
```typescript
ipcMain.handle('dialog:selectDirectory', () => { path?: string });
ipcMain.handle('dialog:selectFile', (event, options) => { path?: string });
ipcMain.handle('dialog:selectFiles', (event, options) => { paths: string[] });
ipcMain.handle('dialog:saveInlineFile', (event, options) => { path?: string });
ipcMain.handle('dialog:readFileAsDataUrl', (event, filePath) => { dataUrl: string });
```

### Event Channels (One-way / Streaming)

Canais usados para notificações do main process para o renderer (streaming):

#### Cowork Streaming Events
```typescript
// Event: nova mensagem adicionada à sessão
webContents.send('cowork:stream:message', {
  sessionId: string;
  message: CoworkMessage;
});

// Event: atualização de conteúdo de mensagem (streaming)
webContents.send('cowork:stream:messageUpdate', {
  sessionId: string;
  messageId: string;
  content: string;
});

// Event: solicitação de permissão de ferramenta
webContents.send('cowork:stream:permission', {
  sessionId: string;
  request: PermissionRequest;
});

// Event: sessão concluída
webContents.send('cowork:stream:complete', {
  sessionId: string;
  claudeSessionId: string | null;
});

// Event: erro na sessão
webContents.send('cowork:stream:error', {
  sessionId: string;
  error: string;
});

// Event: progresso de download do sandbox
webContents.send('cowork:sandbox:downloadProgress', {
  stage: 'runtime' | 'image';
  received: number;
  total?: number;
  percent?: number;
  url?: string;
});
```

#### IM Events
```typescript
// Event: mudança de status do gateway IM
webContents.send('im:status:change', {
  platform: string;
  status: 'connected' | 'disconnected' | 'error';
  error?: string;
});

// Event: mensagem recebida via IM
webContents.send('im:message:received', {
  platform: string;
  message: IMMessage;
});
```

#### Scheduled Task Events
```typescript
// Event: atualização de status de tarefa
webContents.send('scheduledTask:statusUpdate', {
  taskId: string;
  status: 'idle' | 'running' | 'completed' | 'error';
});

// Event: atualização de execução de tarefa
webContents.send('scheduledTask:runUpdate', {
  runId: string;
  status: string;
  output?: string;
  error?: string;
});
```

#### Window Events
```typescript
// Event: mudança de estado da janela
webContents.send('window:state-changed', {
  isMaximized: boolean;
  isFullscreen: boolean;
  isFocused: boolean;
});
```

#### Network Events
```typescript
// Event: mudança de status de rede
ipcRenderer.on('network:status-change', (status: 'online' | 'offline') => {
  // Handler no main process para reconectar gateways IM
});
```

## Preload Script API

O preload script (`src/main/preload.ts`) expõe uma API tipada e segura ao renderer:

```typescript
contextBridge.exposeInMainWorld('electron', {
  platform: process.platform,
  arch: process.arch,

  // Store operations
  store: {
    get: (key: string) => ipcRenderer.invoke('store:get', key),
    set: (key: string, value: any) => ipcRenderer.invoke('store:set', key, value),
    remove: (key: string) => ipcRenderer.invoke('store:remove', key),
  },

  // Cowork session management
  cowork: {
    startSession: (options: CoworkStartOptions) => ipcRenderer.invoke('cowork:session:start', options),
    continueSession: (options: CoworkContinueOptions) => ipcRenderer.invoke('cowork:session:continue', options),
    stopSession: (sessionId: string) => ipcRenderer.invoke('cowork:session:stop', sessionId),
    // ... outros métodos

    // Stream event listeners
    onStreamMessage: (callback) => {
      const handler = (event, data) => callback(data);
      ipcRenderer.on('cowork:stream:message', handler);
      return () => ipcRenderer.removeListener('cowork:stream:message', handler);
    },
    // ... outros listeners
  },

  // IM gateway management
  im: {
    getConfig: () => ipcRenderer.invoke('im:config:get'),
    setConfig: (config) => ipcRenderer.invoke('im:config:set', config),
    startGateway: (platform) => ipcRenderer.invoke('im:gateway:start', platform),
    stopGateway: (platform) => ipcRenderer.invoke('im:gateway:stop', platform),
    // ... outros métodos e listeners
  },

  // ... outras APIs
});
```

## Data Flow Examples

### Cowork Session Lifecycle

```
1. User submits prompt
   Renderer: coworkService.startSession(options)
   └─> IPC: cowork:session:start
       └─> Main: getCoworkRunner().startSession()
           └─> CoworkRunner: SDK execution
               ├─> Event: message
               │   └─> IPC: cowork:stream:message
               │       └─> Renderer: store.dispatch(addMessage())
               │           └─> Redux: Update UI
               ├─> Event: permissionRequest
               │   └─> IPC: cowork:stream:permission
               │       └─> Renderer: Show Permission Modal
               │       └─> User approves
               │           └─> IPC: cowork:permission:respond
               │               └─> Main: Resume SDK execution
               └─> Event: complete
                   └─> IPC: cowork:stream:complete
                       └─> Renderer: Update session status
```

### IM Message Processing

```
1. IM Gateway receives message
   Main: IMGateway.on('message')
   └─> IMGatewayManager: Check Cowork mode
       └─> If Cowork enabled:
           └─> IPC: cowork:session:start (auto-create session)
               └─> CoworkRunner: Process message
                   └─> Stream events back to renderer
       └─> Always forward to renderer:
           └─> IPC: im:message:received
               └─> Renderer: Show in IM chat
```

### Scheduled Task Execution

```
1. Scheduler triggers task
   Main: Scheduler.executeTask(taskId)
   └─> If Cowork task:
       └─> IPC: cowork:session:start (auto-create session)
           └─> CoworkRunner: Execute prompt
               └─> Auto-approve permissions
               └─> Stream events
   └─> IPC: scheduledTask:runUpdate
       └─> Renderer: Update task status in UI
```

## Type Safety

Todos os canais IPC são tipados para garantir segurança de tipos:

- **Preload script**: Define a interface `ElectronAPI` com todos os métodos tipados
- **Renderer**: Usa `window.electron.*` com tipos inferidos
- **Main Process**: Handlers são tipados com parâmetros e retornos

Exemplo:
```typescript
// Preload script
export interface ElectronAPI {
  cowork: {
    startSession(options: CoworkStartOptions): Promise<CoworkSessionResult>;
    onStreamMessage(callback: (data: StreamMessageData) => void): () => void;
  };
}

// Renderer
const result = await window.electron.cowork.startSession({
  prompt: 'Write a hello world',
  cwd: '/path/to/project',
});
```

## Performance Considerations

1. **Payload Sanitization**: Mensagens IPC são truncadas para evitar problemas de memória
   - `IPC_STRING_MAX_CHARS = 4_000`
   - `IPC_MESSAGE_CONTENT_MAX_CHARS = 120_000`
   - `IPC_UPDATE_CONTENT_MAX_CHARS = 120_000`

2. **Streaming**: Para conteúdo longo (como streaming de respostas), usa-se eventos de streaming em vez de uma única mensagem grande

3. **Debouncing**: Atualizações de UI são debounced para evitar renderização excessiva

## Security Notes

1. **Input Validation**: Todos os inputs do renderer são validados no main process
2. **Path Sanitization**: Caminhos de arquivos são normalizados e validados
3. **Permission Checks**: Operações sensíveis (ex: execução de comandos) requerem aprovação explícita
4. **Sandbox**: Sandbox VM isolado para execução de código não confiável

## Key Files

- **`src/main/main.ts`**: Todos os handlers IPC do main process
- **`src/main/preload.ts`**: API exposta ao renderer via contextBridge
- **`src/main/libs/coworkRunner.ts`**: Motor de execução Cowork
- **`src/renderer/services/cowork.ts`**: Wrapper IPC no renderer
- **`src/renderer/store/slices/coworkSlice.ts`**: Redux state management para Cowork
- **`src/main/im/imGatewayManager.ts`**: Gerenciador de gateways IM

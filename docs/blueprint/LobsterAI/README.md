# LobsterAI Skeletons

## O que são Skeletons?

Skeletons são versões simplificadas dos arquivos TypeScript do projeto LobsterAI que contêm apenas a **API pública** dos módulos, sem a implementação detalhada. Eles são úteis para:

- **Estudo da arquitetura**: Entender a estrutura do projeto sem se perder na implementação
- **Documentação de API**: Ver rapidamente quais funções, classes e interfaces estão disponíveis
- **Integração**: Saber como os módulos se comunicam entre si
- **Refatoração**: Planejar mudanças sem quebrar a arquitetura existente

## Estrutura do Skeleton

Um skeleton preserva:

✓ **Imports**: Dependências entre módulos
✓ **Interfaces e tipos**: Definições de contratos
✓ **Classes**: Estrutura de classes com propriedades
✓ **Assinaturas de funções**: Nome, parâmetros e tipos de retorno
✓ **Comentários JSDoc**: Documentação da API
✓ **Declarações export**: O que é público no módulo

Um skeleton remove:

✗ **Corpo de funções**: Implementação detalhada
✗ **Lógica de negócio**: Algoritmos internos
✗ **Código auxiliar**: Variáveis temporárias, helpers internos
✗ **Strings longas**: Mensagens de log, textos de UI

## Como usar os Skeletons

### Navegação

Os skeletons estão organizados na mesma estrutura de diretórios do projeto original:

```
docs/blueprint/LobsterAI/
├── src/
│   ├── main/              # Processo principal do Electron
│   │   ├── main_skel.ts
│   │   ├── libs/
│   │   └── im/
│   └── renderer/          # Processo de renderização (React)
│       ├── services/
│       ├── store/slices/
│       └── types/
└── SKILLs/               # Skills personalizáveis
```

### Exemplo

**Arquivo original** (`src/main/libs/coworkRunner.ts`):
```typescript
export class CoworkRunner extends EventEmitter {
  constructor(store: CoworkStore) {
    super();
    this.store = store;
  }

  async startSession(sessionId: string, prompt: string): Promise<void> {
    // ... 500 linhas de implementação
  }
}
```

**Skeleton** (`src/main/libs/coworkRunner_skel.ts`):
```typescript
export class CoworkRunner extends EventEmitter {
  constructor(store: CoworkStore);
  async startSession(sessionId: string, prompt: string): Promise<void>;
}
```

### Arquivos importantes

Para entender a arquitetura do LobsterAI, comece por estes arquivos:

#### Processo Principal (Main Process)
- **`src/main/main_skel.ts`**: Ponto de entrada, handlers IPC
- **`src/main/preload_skel.ts`**: API exposta ao renderer
- **`src/main/libs/coworkRunner_skel.ts`**: Motor de execução de sessões Cowork

#### Processo de Renderização (Renderer Process)
- **`src/renderer/services/cowork_skel.ts`**: Serviço Cowork (IPC wrapper)
- **`src/renderer/store/slices/coworkSlice_skel.ts`**: Redux state management
- **`src/renderer/types/cowork_skel.ts`**: Tipos Cowork

#### IM (Instant Messaging)
- **`src/main/im/imGatewayManager_skel.ts`**: Gerenciador de gateways IM
- **`src/main/im/index_skel.ts`**: Exportações do módulo IM
- **`src/renderer/services/im_skel.ts`**: Serviço IM no renderer

## Fluxo de Dados

### Inicialização de uma Sessão Cowork

```
Renderer                    Main Process           CoworkRunner
    |                            |                        |
    |-- startSession() --------->|                        |
    |                            |                        |
    |                            |-- CoworkRunner        |
    |                            |   .startSession() -->|
    |                            |                        |
    |<--------- session --------|                        |
    |                            |                        |
    |                            |-- SDK events --------->|
    |                            |                        |
    |<-- stream:message --------|<-- on('message') -----|
    |<-- stream:permission -----|<-- on('permission') --|
    |<-- stream:complete ------|<-- on('complete') ----|
```

### Comunicação IPC

O LobsterAI usa **IPC (Inter-Process Communication)** para comunicação entre o processo principal e o processo de renderização:

- **Canais invoke**: Chamadas síncronas (resultados esperados)
- **Canais send/event**: Eventos assíncronos (notificações)

Para mais detalhes sobre a arquitetura IPC, veja [ARCHITECTURE.md](./ARCHITECTURE.md).

## Notas

- Arquivos `.d.ts` são copiados integralmente (já são apenas definições de tipos)
- Os skeletons são gerados automaticamente pelo script `extract_skeletons.js`
- Para regenerar os skeletons, execute: `node extract_skeletons.js`

## Recursos Adicionais

- **Documentação principal**: Veja [ARCHITECTURE.md](./ARCHITECTURE.md) para detalhes da arquitetura
- **Código fonte**: O projeto completo está em `/inspiration/LobsterAI/`
- **Skills**: Exemplos de skills personalizáveis em `SKILLs/`

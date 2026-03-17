# Canais de Comunicação do Nanobot

O nanobot suporta **13 canais de comunicação** diferentes, permitindo integração com diversas plataformas de chat e mensagens.

## Arquitetura de Canais

Todos os canais implementam a classe base `BaseChannel`, que define a interface padrão:

```python
class BaseChannel(ABC):
    """Abstract base class for chat channel implementations."""
    
    # Métodos obrigatórios (abstract)
    @abstractmethod
    async def start(self) -> None: ...
    @abstractmethod
    async def stop(self) -> None: ...
    @abstractmethod
    async def send(self, msg: OutboundMessage) -> None: ...
    
    # Métodos opcionais
    def is_allowed(self, sender_id: str) -> bool: ...
    @classmethod
    def default_config(cls) -> dict[str, Any]: ...
```

## Lista de Canais

### 1. **DingTalk** (`dingtalk`)
- **Arquivo**: `nanobot/channels/dingtalk_skel.py`
- **Plataforma**: DingTalk (Alibaba)
- **Classe**: `DingTalkChannel`
- **Features**: Mensagens, anexos, suporte a grupos

### 2. **Discord** (`discord`)
- **Arquivo**: `nanobot/channels/discord_skel.py`
- **Plataforma**: Discord
- **Classe**: `DiscordChannel`
- **Features**: Gateway websocket, rich embeds, arquivos, typing indicators, suporte a threads
- **API**: Discord Gateway + REST API

### 3. **Email** (`email`)
- **Arquivo**: `nanobot/channels/email_skel.py`
- **Plataforma**: Email (SMTP/IMAP)
- **Classe**: `EmailChannel`
- **Features**: Envio/recebimento de emails, anexos, HTML support

### 4. **Feishu** (`feishu`)
- **Arquivo**: `nanobot/channels/feishu_skel.py`
- **Plataforma**: Feishu/Lark (ByteDance)
- **Classe**: `FeishuChannel`
- **Features**: Rich text, cards, anexos, tabelas, threads

### 5. **Matrix** (`matrix`)
- **Arquivo**: `nanobot/channels/matrix_skel.py`
- **Plataforma**: Matrix (protocolo descentralizado)
- **Classe**: `MatrixChannel`
- **Features**: End-to-end encryption, rooms, rich messages, state events
- **API**: Matrix Client-Server API

### 6. **Mochat** (`mochat`)
- **Arquivo**: `nanobot/channels/mochat_skel.py`
- **Plataforma**: Mochat (WeChat Work / Enterprise)
- **Classe**: `MochatChannel`
- **Features**: Mensagens corporativas, suporte a múltiplos apps

### 7. **QQ** (`qq`)
- **Arquivo**: `nanobot/channels/qq_skel.py`
- **Plataforma**: QQ (Tencent)
- **Classe**: `QQChannel`
- **Features**: Mensagens de texto, imagens, voice, grupos
- **API**: QQ Bot API (botpy)

### 8. **Slack** (`slack`)
- **Arquivo**: `nanobot/channels/slack_skel.py`
- **Plataforma**: Slack
- **Classe**: `SlackChannel`
- **Features**: Webhook, RTM API, blocks, app mentions, modais
- **API**: Slack Web API + Events API

### 9. **Telegram** (`telegram`)
- **Arquivo**: `nanobot/channels/telegram_skel.py`
- **Plataforma**: Telegram
- **Classe**: `TelegramChannel`
- **Features**: Long polling, bot commands, inline queries, keyboard buttons
- **API**: Telegram Bot API

### 10. **WeCom** (`wecom`)
- **Arquivo**: `nanobot/channels/wecom_skel.py`
- **Plataforma**: WeCom (WeChat Work / Enterprise WeChat)
- **Classe**: `WecomChannel`
- **Features**: Mensagens corporativas, departamentos, anexos
- **API**: WeCom API

### 11. **WhatsApp** (`whatsapp`)
- **Arquivo**: `nanobot/channels/whatsapp_skel.py`
- **Plataforma**: WhatsApp Business
- **Classe**: `WhatsAppChannel`
- **Features**: Mensagens de texto, media, templates, webhooks
- **API**: WhatsApp Business API

## Componentes de Suporte

### ChannelManager
- **Arquivo**: `nanobot/channels/manager_skel.py`
- **Gerencia** múltiplos canais simultaneamente
- **Responsável por**: Inicialização, ciclo de vida, coordenação entre canais

### ChannelRegistry
- **Arquivo**: `nanobot/channels/registry_skel.py`
- **Registro dinâmico** de canais
- **Permite**: Adicionar canais customizados via plugins

## Eventos de Mensagens

Os canais utilizam o barramento de mensagens para comunicação:

### InboundMessage
- **source**: `channels/base_skel.py`
- **Campos**: `channel`, `sender_id`, `chat_id`, `content`, `media`, `metadata`

### OutboundMessage
- **source**: `bus/events_skel.py`
- **Campos**: `channel`, `recipient_id`, `content`, `media`, `reply_to`

## Transcrição de Áudio

Vários canais suportam transcrição automática de áudio via Groq Whisper:

```python
async def transcribe_audio(self, file_path: str | Path) -> str:
    """Transcribe an audio file via Groq Whisper."""
```

Canais com suporte a áudio:
- Discord
- Telegram
- WhatsApp
- (outros dependendo do tipo de mensagem)

## Configuração de Canais

Cada canal define seu esquema de configuração via Pydantic:

```python
class DiscordConfig(Base):
    enabled: bool = False
    token: str = ''
    allow_from: list[str] = []
    # ... config específica do canal
```

## Múltiplos Canais

O nanobot suporta execução simultânea de múltiplos canais:

```yaml
# config.json
{
  "channels": {
    "discord": {"enabled": true, "token": "..."},
    "telegram": {"enabled": true, "token": "..."},
    "slack": {"enabled": true, "token": "..."}
  }
}
```

## Desenvolvendo Canais Customizados

Para criar um novo canal:

1. Herdar de `BaseChannel`
2. Implementar métodos `start()`, `stop()`, `send()`
3. Definir `name` e `display_name`
4. Implementar `default_config()` para auto-configuração
5. Registrar via plugin ou diretamente no código

Veja `nanobot/channels/base_skel.py` para a interface completa.

## Segurança

### Controle de Acesso
```python
def is_allowed(self, sender_id: str) -> bool:
    """Verifica se sender_id está permitido."""
```

Configuração em `config.json`:
```json
{
  "allow_from": ["user123", "*", "admin@example.com"]
}
```

### Valores Especiais
- `[]` (vazio): nega todos
- `["*"]`: permite todos

## Referências

- [BaseChannel API](./nanobot/channels/base_skel.py)
- [Event System](./nanobot/bus/events_skel.py)
- [Message Bus](./nanobot/bus/queue_skel.py)
- [Channel Manager](./nanobot/channels/manager_skel.py)

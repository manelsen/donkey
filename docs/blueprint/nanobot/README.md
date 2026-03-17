# Nanobot Skeletons

Este diretório contém os **skeletons** (esqueletos) do projeto nanobot, que são versões simplificadas do código-fonte que preservam apenas a API pública.

## O que são Skeletons?

Skeletons são representações minimalistas do código Python que:
- ✅ Mantêm **assinaturas de funções e métodos** (nomes, parâmetros, tipos de retorno)
- ✅ Preservam **estrutura de classes** e herança
- ✅ Mantêm **docstrings** documentando o propósito
- ✅ Conservam **imports** e dependências
- ❌ **Removem implementação** (substituída por `...`)
- ❌ Omitem lógica interna, comentários de código e variáveis temporárias

## Por que usar Skeletons?

1. **Documentação de API**: Foco na interface pública sem distrações
2. **Compreensão rápida**: Entenda a estrutura do projeto em minutos
3. **Contratos de código**: Use como referência para integração
4. **Design review**: Avalie arquitetura sem ler implementação detalhada

## Estrutura dos Arquivos

Cada arquivo Python original possui um arquivo skeleton correspondente:
- **Original**: `nanobot/channels/base.py`
- **Skeleton**: `nanobot/channels/base_skel.py`

Os skeletons seguem a mesma estrutura de diretórios do projeto original.

## Exemplo

### Código Original
```python
def add(a: int, b: int) -> int:
    """Add two numbers."""
    result = a + b
    return result
```

### Skeleton
```python
def add(a: int, b: int) -> int:
    """Add two numbers."""
    ...
```

## Como Navegar

### Canais de Comunicação
Veja [`CHANNELS.md`](CHANNELS.md) para uma visão geral dos 13 canais disponíveis.

### Componentes Principais

| Diretório | Descrição |
|-----------|-----------|
| `agent/` | Núcleo do agente AI (loop, memória, contexto, skills) |
| `channels/` | Implementações de canais de chat (13 canais) |
| `providers/` | Provedores LLM (OpenAI, Azure, LiteLLM, custom) |
| `bus/` | Barramento de mensagens e eventos |
| `config/` | Gerenciamento de configuração |
| `agent/tools/` | Ferramentas do agente (web, shell, filesystem, etc.) |

### Classes Base Importantes

- **`BaseChannel`**: Interface para todos os canais de chat
- **`LLMProvider`**: Interface para provedores de LLM
- **`AgentLoop`**: Loop principal de execução do agente
- **`ChannelManager`**: Gerenciador de múltiplos canais

## Gerando Skeletons

Os skeletons foram gerados automaticamente usando análise AST (Abstract Syntax Tree) do Python.

Para regerar os skeletons:
```bash
python3 /path/to/extract_skeletons.py /path/to/nanobot /path/to/blueprint
```

## Estatísticas

- **Total de arquivos Python processados**: 67
- **Arquivos de teste excluídos**: 41
- **Diretórios incluídos**: agent, bus, channels, cli, config, cron, heartbeat, providers, security, session, skills, templates, utils

## Observações

- Todos os skeletons mantêm a compatibilidade de tipos (type hints)
- Métodos abstratos são marcados com `@abstractmethod`
- Propriedades são mantidas com decorador `@property`
- Dataclasses preservam seus atributos

## Links Relacionados

- [Código original](/inspiration/nanobot/)
- [Documentação completa](https://github.com/nanobot-ai/nanobot)

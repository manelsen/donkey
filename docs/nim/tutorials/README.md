# Nim Days - Tutoriais Práticos

> **Fonte**: https://xmonader.github.io/nimdays/

Este livro sobre dias Nim é sobre minha jornada usando Nim e criando coisas úteis/práticas com ele, incluindo:

- Parser INI
- Parser bencode
- Verificador de links
- TicTacToe (linha de comando e GUI)
- Framework de testes
- Sistema de build
- Roteador TCP
- Parser Redis
- Cliente Redis
- Empacotador de ativos
- Tabela de terminal
- Gerenciador de dotfiles
- Aplicação de encurtamento de URL

Este livro é influenciado pelos grandes livros [Practical Common Lisp](http://www.gigamonkeys.com/book/) e [Real World Haskell](http://book.realworldhaskell.org) e planejo seguir o mesmo modelo de ter o livro disponível gratuitamente online.

## Índice de Tutoriais

1. [Intro](#intro) - Introdução ao Nim Days
2. [Dia 1: DMIDecode](#dia-1) - Decodificador de DMI
3. [Dia 2: Parsing Bencode](#dia-2) - Parser do protocolo Bencode
4. [Dia 3: FFI e Libmagic](#dia-3) - Interface com C e libmagic
5. [Dia 4: Async LinksChecker](#dia-4) - Verificador de links assíncrono
6. [Dia 5: INI Parser](#dia-5) - Parser de arquivos INI
7. [Dia 6: Nistow](#dia-6) - Gerenciador de dotfiles
8. [Dia 7: URL Shortening Service](#dia-7) - Serviço de encurtamento de URL
9. [Dia 8: MiniTest](#dia-8) - Framework de testes minimalista
10. [Dia 9: TicTacToe CLI](#dia-9) - Jogo da velha em linha de comando
11. [Dia 10: TicTacToe GUI](#dia-10) - Jogo da velha com interface gráfica
12. [Dia 11: Bake build system](#dia-11) - Sistema de build
13. [Dia 12: Redis Protocol](#dia-12) - Protocolo Redis
14. [Dia 13: Redis Client](#dia-13) - Cliente Redis
15. [Dia 14: Nim-Assets](#dia-14) - Empacotador de ativos
16. [Dia 15: TCP Router](#dia-15) - Roteador TCP
17. [Dia 16: AsciiTables](#dia-16) - Tabelas ASCII
18. [Dia 17: Sonic-Client](#dia-17) - Cliente Sonic
19. [Dia 18: Webframework](#dia-18) - Framework web
20. [Dia 19: Wit.AI Client](#dia-19) - Cliente Wit.AI
21. [Dia 20: CacheTable](#dia-20) - Tabela de cache
22. [Dia 21: Parser Combinators](#dia-21) - Parser combinators

---

## Relatando Problemas

Você pode relatrar problemas ou criar pull requests no [repositório do livro](https://github.com/xmonader/nimdays).

---

## Introdução

Nim Days é uma coleção de tutoriais práticos que mostram como construir projetos reais usando a linguagem Nim. Cada tutorial (dia) aborda um problema específico e mostra como resolvê-lo usando as funcionalidades do Nim.

### O que você aprenderá

- **Manipulação de strings e parsing**: Desde arquivos INI simples até parsers Bencode
- **Programação assíncrona**: Verificadores de links eficientes
- **Interface com C (FFI)**: Integrando com bibliotecas C existentes
- **Desenvolvimento de GUI**: Aplicações gráficas com Nim
- **Programação web**: Frameworks web e clientes HTTP
- **Sistemas de build**: Automação de compilação
- **Protocolos de rede**: Implementação de protocolos como Redis
- **Testes**: Frameworks de testes e melhores práticas

### Pré-requisitos

- Conhecimento básico de programação
- Familiaridade com um editor de texto
- Nim instalado no seu sistema

### Como usar estes tutoriais

Cada tutorial é independente, então você pode:
- Seguir em ordem (Dia 1 ao Dia 21)
- Pular para tutoriais específicos que te interessam
- Usar como referência para problemas específicos

---

## Dia 1: DMIDecode

**Objetivo**: Criar um decodificador de DMI (Desktop Management Interface)

O DMI é um padrão para fornecer informações sobre o hardware do sistema. Neste tutorial, você aprenderá:
- Como ler arquivos binários em Nim
- Estruturas de dados para hardware
- Manipulação de bytes e endianness

**Conceitos cobertos**:
- Leitura de arquivos binários
- Conversão de endianness
- Parsing de estruturas complexas

**Veja também**: [Manipulação de Arquivos](../stdlib/files.md), [Endianness](../stdlib/endians.md)

---

## Dia 2: Parsing Bencode

**Objetivo**: Implementar um parser para o formato Bencode

Bencode é o formato de codificação usado pelo protocolo BitTorrent. Neste tutorial:
- Implementar parsing recursivo
- Lidar com tipos primitivos (inteiros, strings, listas, dicionários)
- Tratar erros de parsing

**Conceitos cobertos**:
- Parsing recursivo
- Manipulação de tipos variantes
- Tratamento de erros

**Veja também**: [Parseutils](../stdlib/parseutils.md), [Tipos](../manual/types.md)

---

## Dia 3: FFI e Libmagic

**Objetivo**: Integrar com a biblioteca C libmagic usando FFI

FFI (Foreign Function Interface) permite chamar código C de Nim. Neste tutorial:
- Declarar funções C em Nim
- Passar strings entre Nim e C
- Usar ponteiros e referências
- Gerenciar memória manualmente

**Conceitos cobertos**:
- Interface FFI do Nim
- Ponteiros e memória
- Wrappers de bibliotecas C

**Veja também**: [FFI no Manual](../manual/ffi.md), [Memória](../memory/README.md)

---

## Dia 4: Async LinksChecker

**Objetivo**: Criar um verificador de links assíncrono

Verificar se centenas de links estão funcionando pode demorar muito tempo se feito sequencialmente. Este tutorial mostra como:
- Usar o sistema async do Nim
- Fazer múltiplas requisições HTTP concorrentemente
- Limitar concorrência para não sobrecarregar servidores

**Conceitos cobertos**:
- Programação assíncrona em Nim
- Cliente HTTP assíncrono
- Controle de concorrência

**Veja também**: [Async](../stdlib/async.md), [HttpClient](../stdlib/httpclient.md)

---

## Dia 5: INI Parser

**Objetivo**: Escrever um parser para arquivos de configuração INI

Arquivos INI são um formato comum de configuração. Você aprenderá:
- Parsing de formato chave=valor
- Lidar com seções
- Validação de dados
- Tratamento de erros amigável

**Conceitos cobertos**:
- Parsing de arquivos texto
- Tratamento de erros
- Validação de entrada

**Veja também**: [Parsecfg](../stdlib/parsecfg.md), [Strings](../stdlib/strutils.md)

---

## Dia 6: Nistow (Dotfiles Manager)

**Objetivo**: Criar um gerenciador de arquivos de configuração

"Nistow" é um gerenciador para seus arquivos de configuração (dotfiles). Este tutorial ensina:
- Sincronizar arquivos entre sistemas
- Gerenciar conflitos
- Backups automáticos
- Interface de linha de comando

**Conceitos cobertos**:
- Manipulação de arquivos
- Sincronização
- CLI (Command Line Interface)

**Veja também**: [Arquivos](../stdlib/files.md), [Parseopt](../stdlib/parseopt.md)

---

## Dia 7: URL Shortening Service

**Objetivo**: Implementar um serviço de encurtamento de URL

Similar a bit.ly ou tinyurl, você criará:
- Servidor web simples
- Banco de dados para redirecionamentos
- API REST básica
- Interface web

**Conceitos cobertos**:
- Servidor HTTP
- Banco de dados
- APIs REST

**Veja também**: [Servidor HTTP](../stdlib/asynchttpserver.md), [Jester](https://github.com/dom96/jester)

---

## Dia 8: MiniTest Framework

**Objetivo**: Construir um framework de testes minimalista

Em vez de usar um framework existente, você criará o seu próprio para entender:
- Como frameworks de teste funcionam
- Macros para testes
- Output de resultados
- Asserções e comparações

**Conceitos cobertos**:
- Macros do Nim
- Metaprogramação
- Design de frameworks

**Veja também**: [Unittest](../stdlib/unittest.md), [Macros](../stdlib/macros.md)

---

## Dia 9: TicTacToe CLI

**Objetivo**: Implementar o jogo da velha em linha de comando

Um tutorial clássico de programação, você criará:
- Lógica do jogo da velha
- Interface de usuário baseada em texto
- Modos jogador vs jogador e jogador vs computador
- IA básica para o computador

**Conceitos cobertos**:
- Lógica de jogo
- I/O de terminal
- Algoritmos simples de IA

**Veja também**: [Terminal](../stdlib/terminal.md), [Matemática](../stdlib/math.md)

---

## Dia 10: TicTacToe GUI

**Objetivo**: Adicionar interface gráfica ao jogo da velha

Baseado no Dia 9, você adicionará:
- Janela gráfica
- Botões e layout
- Tratamento de eventos de mouse
- Integração com a lógica existente

**Conceitos cobertos**:
- Programação GUI em Nim
- Tratamento de eventos
- Layout de componentes

**Veja também**: [Nimx](https://github.com/yglukhov/nimx), [GUI frameworks](https://nim-lang.org/docs/lib.html#graphical-user-interfaces)

---

## Dia 11: Bake Build System

**Objetivo**: Criar um sistema de build automatizado

"Bake" é um sistema de build similar a Make, mas escrito em Nim. Você aprenderá:
- Dependências entre tarefas
- Execução paralela
- Caching de resultados
- Integração com compilador Nim

**Conceitos cobertos**:
- Sistemas de build
- Execução paralela
- Compilação incremental

**Veja também**: [OS](../stdlib/os.md), [Processos](../stdlib/osproc.md)

---

## Dia 12: Redis Protocol

**Objetivo**: Implementar o protocolo Redis

Redis usa um protocolo de rede específico. Neste tutorial:
- Entender o protocolo Redis
- Implementar parsing de comandos
- Serialização de respostas
- Testes de conformidade

**Conceitos cobertos**:
- Protocolos de rede
- Parsing de rede
- Serialização binária

**Veja também**: [Sockets](../stdlib/net.md), [Parseutils](../stdlib/parseutils.md)

---

## Dia 13: Redis Client

**Objetivo**: Criar um cliente Redis completo

Usando o protocolo do Dia 12, você implementará:
- Cliente Redis completo
- Pool de conexões
- Comandos básicos e avançados
- Tratamento de erros

**Conceitos cobertos**:
- Clientes de rede
- Pool de conexões
- Tratamento de erros de rede

**Veja também**: [Net](../stdlib/net.md), [Asyncnet](../stdlib/asyncnet.md)

---

## Dia 14: Nim-Assets

**Objetivo**: Empacotar ativos em binários

"Nim-Assets" permite incluir ativos (imagens, fontes, etc.) no executável. Você aprenderá:
- Conversão de ativos para código Nim
- Empacotamento em tempo de compilação
- Carregamento em runtime

**Conceitos cobertos**:
- Metaprogramação
- Recursos embutidos
- Manipulação de dados binários

---

## Dia 15: TCP Router

**Objetivo**: Implementar um roteador TCP genérico

Um roteador TCP pode:
- Distribuir conexões
- Balancear carga
- Implementar proxies
- Filtrar tráfego

**Conceitos cobertos**:
- Sockets TCP
- Roteamento
- Concorrência

**Veja também**: [Sockets](../stdlib/net.md), [Asyncnet](../stdlib/asyncnet.md)

---

## Dia 16: AsciiTables

**Objetivo**: Criar tabelas ASCII bonitas

Tabelas ASCII são úteis para:
- Saída de dados tabulares
- CLI e logs
- Relatórios de terminal

**Conceitos cobertos**:
- Manipulação de strings
- Formatação
- Cálculo de larguras

**Veja também**: [Strutils](../stdlib/strutils.md), [Strformat](../stdlib/strformat.md)

---

## Dia 17: Sonic-Client

**Objetivo**: Cliente para motor de busca Sonic

Sonic é um motor de busca leve. Este tutorial mostra:
- Protocolo Sonic
- Indexação de documentos
- Busca eficientes
- Tratamento de resultados

**Conceitos cobertos**:
- Protocolos de busca
- Indexação
- Queries

---

## Dia 18: Webframework

**Objetivo**: Criar um framework web mínimo

Aprenda como frameworks web funcionam criando o seu próprio:
- Roteamento de URLs
- Middlewares
- Gerenciamento de requisições/respotas
- Suporte a JSON e HTML

**Conceitos cobertos**:
- Programação web
- Middlewares
- Design de frameworks

**Veja também**: [AsyncHttpServer](../stdlib/asynchttpserver.md), [Jester](https://github.com/dom96/jester)

---

## Dia 19: Wit.AI Client

**Objetivo**: Cliente para API de NLP da Wit.AI

Wit.AI fornece APIs de processamento de linguagem natural. Você aprenderá:
- Clientes HTTP para APIs REST
- Autenticação
- Tratamento de JSON
- Integração com APIs externas

**Conceitos cobertos**:
- APIs REST
- Autenticação
- JSON

**Veja também**: [HttpClient](../stdlib/httpclient.md), [JSON](../stdlib/json.md)

---

## Dia 20: CacheTable

**Objetivo**: Implementar uma tabela de cache eficiente

Uma tabela de cache é fundamental para:
- Acelerar aplicações
- Reduzir carga em bancos de dados
- Implementar LRU (Least Recently Used)

**Conceitos cobertos**:
- Caching
- Estruturas de dados eficientes
- Políticas de evição

**Veja também**: [Tables](../stdlib/tables.md), [Algoritmos](../stdlib/algorithm.md)

---

## Dia 21: Parser Combinators

**Objetivo**: Implementar parser combinators

Parser combinators são uma técnica poderosa para criar parsers. Você aprenderá:
- O que são parser combinators
- Combinadores básicos
- Orquestração de parsers
- Tratamento de erros

**Conceitos cobertos**:
- Teoria de parsing
- Combinators
- Programação funcional

**Veja também**: [PEGs](../stdlib/pegs.md), [Parsing](../manual/parsing.md)

---

## Recursos Adicionais

### Documentação Essencial

- [Biblioteca Padrão](../stdlib/README.md) - Módulos e APIs do Nim
- [Manual da Linguagem](../manual/README.md) - Referência completa
- [Guia de Estilo](../style_guide/README.md) - Como escrever código Nim idiomático

### Ferramentas Úteis

- [Nimble](../tools/README.md#nimble) - Gerenciador de pacotes
- [Nimsuggest](../tools/README.md#nimsuggest) - Suporte para IDE
- [Testament](../tools/README.md#testament) - Executor de testes

### Comunidade

- [Nim Forum](https://forum.nim-lang.org) - Fórum da comunidade
- [Nim Discord](https://discord.gg/nim) - Chat ao vivo
- [Nim GitHub](https://github.com/nim-lang/Nim) - Código fonte

---

**Fonte Original**: https://xmonader.github.io/nimdays/  
**Data da Conversão**: 2025-03-16

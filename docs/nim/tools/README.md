# Ferramentas Disponíveis com Nim

> **Fonte**: https://nim-lang.org/docs/tools.html

A distribuição padrão vem com as seguintes ferramentas:

## Índice

1. [atlas](#atlas) - Clonador de pacotes
2. [Hot Code Reloading](#hot-code-reloading) - Recarregamento de código em tempo de execução
3. [Documentation Generator](#documentation-generator) - Gerador de documentação
4. [Nimsuggest](#nimsuggest) - Suporte para IDE
5. [C2nim](#c2nim) - Conversor C para Nim
6. [niminst](#niminst) - Gerador de instalador
7. [nimgrep](#nimgrep) - Utilitário de busca e substituição
8. [nimpretty](#nimpretty) - Formatador de código
9. [testament](#testament) - Executor de testes avançado

---

## atlas

`atlas` é uma ferramenta simples de clonagem de pacotes. Ele gerencia um espaço de trabalho isolado que contém projetos e dependências.

**Documentação**: [atlas.html](atlas.html)

---

## Hot Code Reloading

O recurso de "Hot code reloading" está embutido no compilador mas tem seu próprio documento explicando como funciona.

**Documentação**: [hcr.html](hcr.html)

---

## Documentation Generator

O gerador de documentação embutido `nim doc` gera documentação HTML de arquivos fonte `.nim`.

**Documentação**: [docgen.html](docgen.html)

**Uso**:
```nim
nim doc meu_programa.nim
```

---

## Nimsuggest for IDE Support

Através da ferramenta `nimsuggest`, qualquer IDE pode consultar um arquivo fonte `.nim` e obter informações úteis como definição de símbolos ou sugestões para autocompletar.

**Documentação**: [nimsuggest.html](nimsuggest.html)

---

## C2nim

Conversor de código C para Nim. Traduz arquivos de cabeçalho C para Nim.

**Documentação**: https://github.com/nim-lang/c2nim/blob/master/doc/c2nim.rst

**Uso**:
```nim
c2nim header.h > arquivo.nim
```

---

## niminst

niminst é uma ferramenta para gerar um instalador para um programa Nim.

**Documentação**: [niminst.html](niminst.html)

---

## nimgrep

Utilitário de busca e substituição do Nim.

**Documentação**: [nimgrep.html](nimgrep.html)

**Uso**:
```nim
nimgrep --pattern "foo" --replacement "bar" arquivos/
```

---

## nimpretty

`nimpretty` é um embelezador de código-fonte Nim, para formatar código de acordo com o guia de estilo oficial.

**Uso**:
```nim
nimpretty arquivo.nim
```

---

## testament

`testament` é um executor avançado e automático de *unittests* para testes Nim, usado para o desenvolvimento do próprio Nim, oferece isolamento de processo para seus testes, pode gerar estatísticas sobre casos de teste, suporta múltiplos alvos (C, JS, etc), tem logging, pode gerar relatórios HTML, pular testes de um arquivo, e muito mais, então pode ser útil para executar seus testes, até mesmo os mais complexos.

**Documentação**: [testament.html](testament.html)

**Características**:
- Execução isolada de processos
- Suporte a múltiplos alvos (C, JS, etc.)
- Logging detalhado
- Relatórios HTML
- Execução seletiva de testes
- Estatísticas de cobertura

---

## Links Relacionados

- [Biblioteca Padrão](../stdlib/README.md) - Módulos e APIs do Nim
- [Manual da Linguagem](../manual/README.md) - Documentação completa da linguagem
- [Guia de Estilo](../style_guide/README.md) - Convenções de formatação de código
- [Tutoriais](../tutorials/README.md) - Exemplos práticos de uso das ferramentas

---

**Fonte Original**: https://nim-lang.org/docs/tools.html  
**Última atualização**: 2026-02-23 03:21:57 UTC  
**Data da Conversão**: 2025-03-16

# Guia de Estilo da Biblioteca Padrão (Standard Library Style Guide)

> **Autores**: Clay Sweetser, Dominik Picheta  
> **Versão**: 2.2.8  
> **Fonte**: https://nim-lang.org/docs/nep1.html

## Índice

1. [Introdução](#introdução)
2. [Convenções de Espaçamento e Espaços em Branco](#convenções-de-espaçamento)
3. [Convenções de Nomenclatura](#convenções-de-nomenclatura)
4. [Convenções de Codificação](#convenções-de-codificação)
5. [Convenções para Declarações e Expressões Múltiplas Linhas](#convenções-para-multilinhas)
6. [Miscelânea](#miscelânea)

---

## Introdução

Embora o Nim suporte uma variedade de estilos de código e formatação, é no entanto benéfico que certos esforços da comunidade, como a biblioteca padrão, sigam um conjunto consistente de guias de estilo quando apropriado. Esta proposta de melhoria visa listar uma série de guias que a biblioteca padrão deve seguir.

**Nota**: Podem haver exceções a essas regras. O Nim sendo tão flexível quanto é, haverá partes deste guia de estilo que não fazem sentido em certos contextos. Além disso, assim como o [guia de estilo do Python](https://legacy.python.org/dev/peps/pep-0008/) muda com o tempo, este guia de estilo também mudará.

Essas regras só serão forçadas para contribuições à base de código do Nim e projetos oficiais, como o compilador Nim, a biblioteca padrão e várias ferramentas oficiais como C2Nim.

---

## Convenções de Espaçamento e Espaços em Branco

### Regras Básicas

1. **Comprimento da Linha**: As linhas não devem ter mais de 80 caracteres. Limitar a quantidade de informações presentes em cada linha torna o código mais legível - o leitor tem pedaços menores para processar.

2. **Indentação**: Devem ser usados dois espaços para indentação de blocos; tabulações não são permitidas (o compilador força isso). Usar espaços significa que a aparência do código é mais consistente entre editores. Ao contrário dos espaços, a largura da tabulação varia entre editores, e nem todos os editores fornecem meios de mudar essa largura.

3. **Alinhamento**: Embora o uso de espaços em branco por razões estilísticas diferentes das endossadas por este guia sejam permitidos, pensamento cuidadoso deve ser colocado em tais práticas. Nem todos os editores suportam alinhamento automático de seções de código, e realinhar seções longas de código à mão pode rapidamente se tornar tedioso.

**Exemplo ruim** (alinhamento vertical excessivo):
```nim
# Isso é ruim, pois da próxima vez que alguém vier
# editar este bloco de código, eles
# precisarão realinhar todas as atribuições novamente:
type
  WordBool*    = int16
  CalType*     = int
  ... # 5 linhas depois
  CalId*       = int
  LongLong*    = int64
  LongLongPtr* = ptr LongLong
```

---

## Convenções de Nomenclatura

### Regras Gerais

1. **Tipos em PascalCase**: Identificadores de tipo devem estar em PascalCase. Todos os outros identificadores devem estar em camelCase, com exceção de constantes que **podem** usar PascalCase mas não são obrigadas a.

**Exemplo**:
```nim
# Constantes podem começar com letra minúscula ou maiúscula.
const aConstant = 42
const FooBar = 4.2

var aVariable = "Meep" # Variáveis devem começar com letra minúscula.

# Tipos devem começar com letra maiúscula.
type
  FooBar = object
```

2. **Constantes de Wrappers C/C++**: Para constantes vindas de um wrapper C/C++, ALL_UPPERCASE são permitidos, mas são feios. (Por que gritar CONSTANT? Constantes não fazem mal, variáveis fazem!)

3. **Sufixos de Tipo**: Ao nomear tipos que vêm em variedades de valor, ponteiro e referência, use um nome regular para a variedade que será mais usada, e adicione um sufioo "Obj", "Ref" ou "Ptr" para as outras variedades. Se não houver uma única variedade que será mais usada, adicione sufioos apenas às variantes de ponteiro. O mesmo se aplica a wrappers C/C++.

**Exemplo**:
```nim
type
  Handle = object # Será mais usada comumente
    fd: int64
  HandleRef = ref Handle # Será menos usada
```

4. **Exceções e Erros**: Tipos de exceção e erro devem ter sufioo "Error" ou "Defect".

**Exemplo**:
```nim
type
  ValueError = object of CatchableError
  AssertionDefect = object of Defect
  Foo = object of Exception # estilo ruim, tente herdar CatchableError ou Defect
```

5. **Enums**: A menos que marcado com pragma `{.pure.}`, membros de enums devem ter um prefixo identificador, como uma abreviação do nome do enum.

**Exemplo**:
```nim
type
  PathComponent = enum
    pcDir
    pcLinkToDir
    pcFile
    pcLinkToFile
```

6. **Valores de Enum**: Valores de enums não puros devem usar camelCase, enquanto valores de enums puros devem usar PascalCase.

**Exemplo**:
```nim
type
  PathComponent{.pure.} = enum
    Dir
    LinkToDir
    File
    LinkToFile
```

7. **Acrônimos Tratados como Palavras Comuns**: Na era de HTTP, HTML, FTP, TCP, IP, UTF, WWW é tolo fingir que essas são de alguma forma palavras especiais exigindo todas maiúsculas. Em vez disso, trate-as pelo que são: palavras reais. Então é `parseUrl` em vez de `parseURL`, `checkHttpHeader` em vez de `checkHTTPHeader`, etc.

8. **Vistas de Mutação**: Operações como `mitems` ou `mpairs` (ou agora depreciado `mget`) que permitem uma *vista mutante* em alguma estrutura de dados devem começar com `m`.

9. **Versões de Transformação**: Quando tanto a mutação in-place quanto 'copia transformada retornado' estão disponíveis, a última é o particípio passado da primeira:
   - `reverse` e `reversed` em algorithm
   - `sort` e `sorted`
   - `rotate` e `rotated`

10. **Sufioo -In**: Quando a versão 'copia transformada retornado' já existe como `strutils.replace`, uma versão in-place deve receber um sufioo `-In` (`replaceIn` para este exemplo).

11. **Ordem Verbo-Sujeito**: Use `sujeitoVerbo`, não `verboSujeito`, por exemplo: `fileExists`, não `existsFile`.

### Tabela de Abreviações Comuns

A API da stdlib é projetada para ser **fácil de usar** e consistente. Facilidade de uso é medida pelo número de chamadas para atingir uma ação de alto nível concreta. O objetivo último é que o programador possa *adivinhar* um nome.

A biblioteca usa um esquema de nomenclatura simples que faz uso de abreviações comuns para manter nomes curtos mas significativos.

| Palavra em inglês | Para usar | Notas |
|------------------|-----------|---------|
| initialize | initFoo | inicializa um tipo de valor `Foo` |
| new | newFoo | inicializa um tipo de referência `Foo` via `new` ou um tipo de valor `Foo` com semântica de referência |
| this ou self | self | para procs semelhantes a métodos, por exemplo: `proc fun(self: Foo, a: int)`; racional: `self` é mais único em inglês que `this`, e `foo` não seria DRY |
| find | find | deve retornar a posição onde algo foi encontrado; para um resultado bool use `contains` |
| contains | contains | muitas vezes abreviação para `find() >= 0` |
| append | add | use `add` em vez de `append` |
| compare | cmp | deve retornar um int com semântica `< 0`, `== 0` ou `> 0`; para um resultado bool use `sameXYZ` |
| put | put, `[=]` | considere sobrecarregar `[=]` para put |
| get | get, `[]` | considere sobrecarregar `[]` para get; considere não usar `get` como prefixo: `len` em vez de `getLen` |
| length | len | também usado para *número de elementos* |
| size | size, len | size deve se referir a um tamanho em bytes |
| capacity | cap | |
| memory | mem | implica uma operação de baixo nível |
| items | items | iterador padrão sobre uma coleção |
| pairs | pairs | iterador sobre pares (chave, valor) |
| delete | delete, del | del deve ser mais rápido que delete, pois não mantém ordem; delete mantém ordem |
| remove | delete, del | inconsistente no momento |
| include | incl | |
| exclude | excl | |
| command | cmd | |
| execute | exec | |
| environment | env | |
| variable | var | |
| value | value, val | val é preferido, inconsistente no momento |
| executable | exe | |
| directory | dir | |
| path | path | path é uma string "/usr/bin" (por exemplo), dir é o conteúdo de "/usr/bin"; inconsistente no momento |
| extension | ext | |
| separator | sep | |
| column | col, column | col é preferido, inconsistente no momento |
| application | app | |
| configuration | cfg | |
| message | msg | |
| argument | arg | |
| object | obj | |
| parameter | param | |
| operator | opr | |
| procedure | proc | |
| function | func | |
| coordinate | coord | |
| rectangle | rect | |
| point | point | |
| symbol | sym | |
| literal | lit | |
| string | str | |
| identifier | ident | |
| indentation | indent | |

---

## Convenções de Codificação

### Procedimentos e Return

1. **Use `result` quando possível**: A declaração `return` deve idealmente ser usada quando suas propriedades de fluxo de controle são necessárias. Use a variável implícita `result` de um procedimento sempre que possível. Isso melhora a legibilidade.

**Exemplo bom**:
```nim
proc repeat(text: string, x: int): string =
  result = ""
  
  for i in 0..<x:
    result.add($i)
```

2. **Use procs sempre que possível**: Use um proc quando possível, usando apenas as facilidades mais poderosas de macros, templates, iteradores e conversores quando necessário.

3. **Use `let` para variáveis imutáveis**: Use a declaração `let` (não `var`) ao declarar variáveis que não mudam dentro de seu escopo. Usar a declaração `let` garante que as variáveis permanecem imutáveis, e dá a quem lê o código uma melhor ideia do propósito do código.

---

## Convenções para Declarações e Expressões Múltiplas Linhas

1. **Tuplas Múltiplas Linhas**: Tuplas que são mais longas que uma linha devem indentar seus parâmetros.

**Exemplo**:
```nim
type
  LongTupleA = tuple[
    wordyTupleMemberOne: int, wordyTupleMemberTwo: string,
    wordyTupleMemberThree: float
  ]
```

2. **Declarações de Procedimento**: Da mesma forma, qualquer declaração de procedimento e tipo de procedimento que seja mais longa que uma linha deve fazer a mesma coisa. Indentação dupla pode ser usada para distinguir do corpo que segue - isso se aplica a todos os construtos com corpo (if, while, etc.).

**Exemplo**:
```nim
type
  EventCallback = proc(
    timeReceived: Time, errorCode: int, event: Event,
    output: var string
  )

proc lotsOfArguments(
    argOne: string, argTwo: int, argThree: float,
    argFour: proc(), argFive: bool, argSix: int
  ): GenericType[int, string]{.heyLookALongPragma.} =
  discard
```

3. **Chamadas de Procedimento**: Chamadas de procedimento múltiplas linhas devem continuar indentadas (como declarações de procedimento múltiplas linhas).

**Exemplo**:
```nim
startProcess(
  nimExecutable, currentDirectory, compilerArguments
  environment, processOptions
  )
```

**Nota**: Versões anteriores deste guia defendiam alinhamento vertical ao longo da chave/parêntese de abertura - ambos os estilos são permissíveis com preferência pelo estilo atual em novo código.

---

## Miscelânea

1. **Intervalos**: Use `a..b` em vez de `a .. b`, exceto quando `b` contém um operador, por exemplo `a .. -3`. Da mesma forma com `a..<b`, `a..^b` e outros operadores começando com `..`.

2. **Prefixo std**: Use o prefixo `std` para módulos da biblioteca padrão, nomeadamente use `std/os` para único módulo e use `std/[os, sysrand, posix]` para múltiplos módulos.

3. **Strings de Três Aspas**: Prefira literais de três aspas multilinha para começar com uma nova linha; é semanticamente idêntico (é um recurso de literais de três aspas) mas mais claro pois se alinha com a próxima linha:

**Use isto**:
```nim
let a = """
foo
bar
"""
```

**Em vez disso**:
```nim
let a = """foo
bar
"""
```

4. **Getters**: Uma API getter para um campo privado `foo` deve preferencialmente ser nomeada `foo`, não `getFoo`. Uma API semelhante a getter deve preferencialmente ser nomeada `getFoo`, não `foo` se:
   - a API tem efeitos colaterais
   - ou o custo não é `O(1)`

Para casos intermediários, não há uma diretriz clara.

5. **Setters**: Da mesma forma com uma API setter, substituindo `foo` com `foo=` e `getFoo` com `setFoo` no texto acima.

---

## Links Relacionados

- [Biblioteca Padrão](../stdlib/README.md) - Documentação da stdlib
- [Manual da Linguagem](../manual/README.md) - Referência completa da linguagem
- [Ferramentas](../tools/README.md) - Ferramentas de desenvolvimento
- [Tutoriais](../tutorials/README.md) - Exemplos práticos

---

**Fonte Original**: https://nim-lang.org/docs/nep1.html  
**Versão Nim**: 2.2.8  
**Data da Conversão**: 2025-03-16

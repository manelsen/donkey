# Manual da Linguagem Nim

> **Autores**: Andreas Rumpf, Zahary Karadjov  
> **Versão**: 2.2.8  
> **Fonte**: https://nim-lang.org/docs/manual.html

> *"Complexidade" parece muito com "energia": você pode transferi-la do usuário final para um/alguns dos outros jogadores, mas a quantidade total parece permanecer praticamente constante para uma dada tarefa.* -- Ran

## Índice

1. [Sobre Este Documento](#sobre-este-documento)
2. [Definições](#definições)
3. [Análise Léxica](#análise-léxica)
4. [Sintaxe](#sintaxe)
5. [Ordem de Avaliação](#ordem-de-avaliação)
6. [Constantes e Expressões Constantes](#constantes-e-expressões-constantes)
7. [Tipos](#tipos)
8. [Relações de Tipo](#relações-de-tipo)
9. [Resolução de Sobrecarga](#resolução-de-sobrecarga)
10. [Conceitos](#conceitos)
11. [Declarações e Expressões](#declarações-e-expressões)
12. [Procedimentos](#procedimentos)
13. [Métodos](#métodos)
14. [Iteradores e o Comando for](#iteradores-e-o-comando-for)
15. [Conversores](#conversores)
16. [Seções de Tipo](#seções-de-tipo)
17. [Tratamento de Exceções](#tratamento-de-exceções)
18. [Sistema de Efeitos](#sistema-de-efeitos)
19. [Genéricos](#genéricos)
20. [Templates](#templates)
21. [Macros](#macros)
22. [Tipos Especiais](#tipos-especiais)
23. [Módulos](#módulos)
24. [Mensagens do Compilador](#mensagens-do-compilador)
25. [Pragmas](#pragmas)
26. [Interface de Função Estrangeira](#interface-de-função-estrangeira)
27. [Threads](#threads)
28. [Guardas e Travas](#guardas-e-travas)

---

## Sobre Este Documento

**Nota**: Este documento é um rascunho! Vários recursos do Nim podem necessitar de uma descrição mais precisa. Este manual está evoluindo constantemente em uma especificação adequada.

**Nota**: Os recursos experimentais do Nim são cobertos [aqui](experimental.md).

**Nota**: Atribuições, movimentos e destruição são especificados no documento de [destrutores](destrutores.md).

Este documento descreve a léxica, a sintaxe e a semântica da linguagem Nim.

Para aprender como compilar programas Nim e gerar documentação veja o [Guia do Usuário do Compilador](nimc.md) e o [Guia de Ferramentas DocGen](docgen.md).

Os construtos da linguagem são explicados usando um BNF estendido, no qual `(a)*` significa 0 ou mais `a`s, `a+` significa 1 ou mais `a`s, e `(a)?` significa um `a` opcional. Parênteses podem ser usados para agrupar elementos.

`&` é o operador de lookahead; `&a` significa que um `a` é esperado mas não consumido. Ele será consumido na regra seguinte.

Os símbolos `|`, `/` são usados para marcar alternativas e têm a menor precedência. `/` é a escolha ordenada que requer que o analisador tente as alternativas na ordem dada. `/` é freqüentemente usado para garantir que a gramática não é ambígua.

Não-terminais começam com uma letra minúscula, símbolos de terminais abstratos estão em MAIÚSCULAS. Símbolos terminais literais (incluindo palavras-chave) são citados com `'`. Um exemplo:

```bnf
ifStmt = 'if' expr ':' stmts ('elif' expr ':' stmts)* ('else' stmts)?
```

O operador binário `^*` é usado como abreviação para 0 ou mais ocorrências separadas por seu segundo argumento; da mesma forma `^+` significa 1 ou mais ocorrências: `a ^+ b` é abreviação para `a (b a)*` e `a ^* b` é abreviação para `(a (b a)*)?`. Exemplo:

```bnf
arrayConstructor = '[' expr ^* ',' ']'
```

Outras partes do Nim, como regras de escopo ou semântica de runtime, são descritas informalmente.

---

## Definições

O código Nim especifica uma computação que atua na memória consistindo em componentes chamados **locais**. Uma variável é basicamente um nome para um local. Cada variável e local é de um certo **tipo**. O tipo da variável é chamado de **tipo estático**, o tipo do local é chamado de **tipo dinâmico**. Se o tipo estático não é o mesmo que o tipo dinâmico, é um supertipo ou subtipo do tipo dinâmico.

Um **identificador** é um símbolo declarado como um nome para uma variável, tipo, procedimento, etc. A região do programa sobre a qual uma declaração se aplica é chamada de **escopo** da declaração. Escopos podem ser aninhados. O significado de um identificador é determinado pelo menor escopo delimitador no qual o identificador é declarado a menos que regras de resolução de sobrecarga sugiram de outro modo.

Uma expressão especifica uma computação que produz um valor ou local. Expressões que produzem locais são chamadas de **l-values**. Um l-value pode denotar tanto um local quanto o valor que o local contém, dependendo do contexto.

Um programa **Nim** consiste em um ou mais arquivos fonte de texto contendo código Nim. Ele é processado por um compilador **Nim** em um executável. A natureza desse executável depende da implementação do compilador; pode, por exemplo, ser um binário nativo ou código fonte JavaScript.

Em um programa Nim típico, a maior parte do código é compilada no executável. No entanto, algum código pode ser executado em **tempo de compilação**. Isso pode incluir expressões constantes, definições de macro, e procedimentos Nim usados por definições de macro. A maior parte da linguagem Nim é suportada em tempo de compilação, mas há algumas restrições — veja [Restrições na Execução em Tempo de Compilação](#restrições-em-tempo-de-compilação) para detalhes. Usamos o termo **runtime** para cobrir tanto execução em tempo de compilação quanto execução de código no executável.

---

## Análise Léxica

A análise léxica do Nim consiste em:

### Encoding

O compilador Nim aceita os seguintes encodings: UTF-8 (padrão), ASCII e UTF-16/32. Por padrão, arquivos .nim são assumidos como UTF-8. Outros encodings podem ser especificados com o encoding unicode BOM.

### Indentação

A indentação é significativa no Nim. O compilador infere o fim de um bloco pela indentação. Isso é semelhante ao Python.

### Comentários

```nim
# Comentário de uma linha

#[
  Comentário
  de múltiplas
  linhas
]
```

### Identificadores e Palavras-Chave

Identificadores começam com uma letra (a-z, A-Z) ou underscore (_) e podem conter letras, dígitos (0-9) e underscores adicionais. O Nim diferencia maiúsculas de minúsculas.

Palavras-chave são palavras reservadas:

```nim
addr and as asm atomic
bind block break
case cast concept const continue
converter defer discard distinct div do elif else end enum except export
finally for from func generic if import in include interface
iterator iterator let macro method mixin mod nil not object
or out proc ptr raise ref return shared shl static template
try tuple type using var when while with xor
yield
```

### Identificadores com Backticks

Você pode usar acentos graves (backticks) `` ` `` para permitir quase qualquer caractere em identificadores:

```nim
var `foo bar` = 42
echo `foo bar`  # 42
```

### Igualdade de Identificador

A igualdade de identificadores é determinada pela normalização Unicode. O compilador aplica a forma de normalização NFKC (Normalization Form Compatibility Composition).

### Palavras-Chave como Identificadores

Palavras-chave podem ser usadas como identificadores quando colocadas entre acentos graves:

```nim
var `if` = 42
echo `if`  # 42
```

### Literais de String

```nim
var
  a = "string simples"
  b = """
     string de múltiplas
     linhas
     """
  c = r"string crua"  # crua
```

### Literais de String de Três Aspas

```nim
var
  a = """string de três aspas"""
  b = """
     Esta string
     tem múltiplas
     linhas
     """
```

### Literais de String Crua

```nim
var
  a = r"c:\path\com\backslashes"
  b = r"""crua string
     com três aspas"""
```

### Literais de String Crua Generalizada

```nim
var
  a = r"string onde "aspas são ignorados"
  b = r"""onde "aspas são ignorados"
     mesmo com três aspas"""
```

### Literais de Caractere

```nim
var
  a = 'a'
  b = '\n'  # caractere de escape
```

### Literais Numéricos

```nim
var
  a = 42              # int
  b = 42'i8           # int8
  c = 42.0            # float
  d = 0x10            # hexadecimal
  e = 0o10            # octal
  f = 0b10            # binário
  g = 1_000_000       # com underscores
```

#### Literais Numéricos Personalizados

Você pode definir seus próprios literais numéricos usando o `macro` `intLiteral` ou `floatLiteral`.

### Operadores

```nim
+ - * / div mod
< <= == >= !=
and or xor not not shl shr
& ~ | ^ . ..
```

### Operadores Unicode

O Nim suporta operadores Unicode:

```nim
× ÷ ± ⊕ ⊗ ≠ ≥ ≤
```

### Outros Tokens

```nim
= : . , .. .. ..< ..> ..=
. : .. ( ) [ ] { } [ ]= {. .} { }
```

---

## Sintaxe

### Associatividade

Os operadores têm diferentes níveis de precedência. Consulte o manual completo para a tabela completa.

### Precedência

Da maior precedência para a menor:

1. `.` (acesso de membro)
2. `[]` (acesso de array)
3. `()` (chamada de função)
4. Prefixo: `- + not ~ & *` etc.
5. Multiplicativo: `* / div mod shl shr %`
6. Aditivo: `+ - or xor`
7. Comparativo: `<= < >= > == != in notin is isnot`
8. Lógico: `and`
9. Atribuição: `= :=`

### Operadores do Tipo Ponto

Operadores como `.`, `.()`, `.` podem ser usados para chamadas de método.

### Gramática

A gramática completa do Nim está disponível no arquivo fonte deste manual. Consulte a seção completa para detalhes sobre produção de BNF para cada construto.

---

## Constantes e Expressões Constantes

Constantes são símbolos que são ligados a um valor em tempo de compilação:

```nim
const
  maxItems = 100
  greeting = "Hello"

echo maxItems      # 100
echo greeting      # "Hello"
```

Expressões constantes podem ser usadas onde constantes são esperadas:

```nim
var x = 2 * maxItems  # Calculado em tempo de compilação
```

---

## Restrições em Tempo de Compilação

Nem todo o código Nim pode ser executado em tempo de compilação. As principais restrições incluem:

- Não podem ser usadas operações de E/S
- Código nativo (assembly) não pode ser executado
- Alguns pragmas não podem ser usados
- Chamadas de sistema operacional são limitadas

---

## Tipos

O Nim tem um sistema de tipos rico que inclui:

### Tipos Ordinais

Tipos ordinais são tipos que suportam uma relação de ordem bem definida:

- `int`, `int8`...`int64`
- `uint`, `uint8`...`uint64`
- `bool` (valores: `false`, `true`)
- `char`
- `enum` (tipos de enumeração)

### Tipos Inteiros Pré-Definidos

```nim
var
  a: int      # int de tamanho nativo (32 ou 64 bit)
  b: int8     # 8 bit
  c: int16    # 16 bit
  d: int32    # 32 bit
  e: int64    # 64 bit
  f: uint     # unsigned
  g: uint8    # unsigned 8 bit
```

### Tipos Subintervalo

```nim
type
  SubRange = range[1..10]

var x: SubRange = 5  # OK
var y: SubRange = 15 # Erro de tempo de execução
```

### Tipos de Ponto Flutuante Pré-Definidos

```nim
var
  a: float32  # IEEE float de 32 bit
  b: float64  # IEEE float de 64 bit
```

### Tipo Booleano

```nim
var
  a: bool = true
  b: bool = false
```

### Tipo de Caractere

```nim
var
  c: char = 'a'
```

### Tipos de Enumeração

```nim
type
  Color = enum
    Red
    Green
    Blue

var c: Color = Color.Red
```

### Tipo de String

Strings são seqs de caracteres (inteiros) com index começando em 0:

```nim
var s: string = "Hello, World!"
echo s[0]      # 'H'
echo s.len      # 13
```

### Tipo cstring

`cstring` é compatível com strings terminadas em nulo de C:

```nim
var s: cstring = "Hello"
```

### Tipos Estruturados

#### Arrays e Seqs

```nim
var
  a: array[5, int]     # array fixo de tamanho 5
  b: seq[int]         # seq (array dinâmico)
  c: array[1..10, int] # array com intervalo
```

#### Arrays Abertos

```nim
proc process(arr: openArray[int]) =
  for i in arr:
    echo i

process([1, 2, 3, 4, 5])  # OK
process(newSeq[int](10))   # OK
```

#### Varargs

```nim
proc test(args: varargs[int]) =
  for arg in args:
    echo arg

test(1, 2, 3, 4, 5)
```

#### Arrays Não Verificados

```nim
type
  BigArray = array[1000, int]  # array não verificado

var a: BigArray
```

#### Tuplas e Tipos de Objeto

```nim
type
  Point = tuple[x, y: int]

var p: Point = (x: 10, y: 20)

type
  Person = object
    name: string
    age: int

var person = Person(name: "Alice", age: 30)
```

#### Construção de Objeto

```nim
type
  Point = object
    x, y: int

var p1 = Point(x: 10, y: 20)
var p2 = Point(x: 10, y: 20)  # Com a mesma sintaxe
```

#### Variantes de Objeto

```nim
type
  NodeKind = enum
    Leaf
    Internal

  Node = object
    case kind: NodeKind
    of Leaf:
      value: int
    of Internal:
      left, right: ref Node
```

#### cast uncheckedAssign

```nim
type
  MyType = object
    x: int

var a = MyType(x: 42)
var b: int
uncheckedAssign(b, a.x)
```

#### Valores Padrão para Campos de Objeto

```nim
type
  Config = object
    host: string = "localhost"
    port: int = 8080

var c = Config()  # host = "localhost", port = 8080
```

### Tipo de Conjunto (Set)

```nim
type
  CharSet = set[char]

var s: CharSet = {'a', 'b', 'c'}

s.incl('d')  # false
s.incl('a')  # true
```

#### Campos de Bit

```nim
type
  Flags {.pure.} = enum
    FlagA = 0
    FlagB = 1
    FlagC = 2
```

### Tipos de Referência e Ponteiro

```nim
var
  a: int = 42
  b: ptr int = addr(a)      # ponteiro (não traçado)
  c: ref int = new(int)      # referência (traçada)

echo b[]  # desreferencia ponteiro
echo c[]  # desreferencia referência
```

### Nil

`nil` é o valor nulo para tipos ponteiro e referência:

```nim
var p: ptr int = nil
var r: ref string = nil
```

### Misturando Memória GC'ed com ptr

Você pode misturar memória gerenciada com ponteiros manuais, mas deve ter cuidado para evitar coleta prematura.

### Tipo Procedimental

```nim
type
  Callback = proc (x: int): int

var cb: Callback = proc (x: int): int =
  return x * 2
```

### Tipo Distinto

Tipos distintos criam novos tipos que não podem ser implicitamente convertidos:

```nim
type
  Dollars = distinct int
  Euros = distinct int

var d: Dollars = 100.Dollars
var e: Euros = 200.Euros

# d + e  # Erro: tipos incompatíveis
```

#### Modelando Moedas

```nim
type
  Currency {.pure.} = enum
    USD
    EUR

  Money = object
    amount: int
    currency: Currency
```

#### Evitando Ataques de Injeção SQL

```nim
type
  SqlQuery = distinct string

proc safeQuery(query: SqlQuery): string =
  # Query é distinto de string - não pode ser concatenado diretamente
  return "SELECT * FROM table WHERE id = " & $query
```

### Tipo Auto

`auto` é um tipo especial que pode representar qualquer valor, exceto `nil`:

```nim
var x: auto = 42
x = "agora é uma string"
```

---

## Relações de Tipo

O Nim define várias relações entre tipos:

### Igualdade de Tipo

Dois tipos são iguais se tiverem a mesma definição exata.

### Relação de Subtipo

O subtipo `A` pode ser usado onde o supertipo `B` é esperado.

### Relação Conversível

Um tipo pode ser convertido para outro se a conversão for segura.

### Compatibilidade de Atribuição

Um valor pode ser atribuído a uma variável se o tipo do valor for compatível com o tipo da variável.

---

## Resolução de Sobrecarga

O Nim resolve sobrecarga de procedimento em três ensaios:

### Primeiro Ensaio: Correspondência de Categoria

Correspondência de tipo básico (int, float, etc.)

### Segundo Ensaio: Comparação de Ordem Hierárquica

Correspondência baseada em hierarquia de tipos.

### Terceiro Ensaio: Análise de Complexidade

Se houver múltiplas correspondências, escolha a mais específica.

### Alguns Exemplos

Consulte o manual completo para exemplos detalhados de resolução de sobrecarga.

### Variáveis de Tipo Correspondem

Genéricos com variáveis de tipo correspondem qualquer tipo.

### Sobrecarga Baseada em 'var T'

Procedimentos podem ser sobrecarregados com base em tipos de referência mutável.

### Resolução de Tipo Preguiçosa para untyped

Parâmetros `untyped` não têm sua resolução de tipo adiada até uso.

### Correspondência de Varargs

Varargs podem corresponder qualquer número de argumentos.

### iterável

Procedimentos iteráveis podem ser usados em loops `for`.

---

## Sobrecarga de Desambiguação

### Sobrecarga de Argumento Nomeado

Argumentos nomeados podem ajudar a resolver ambiguidades de sobrecarga.

---

## Conceitos

Conceitos são restrições genéricas em tipos:

```nim
type
  Addable = concept x, y, z =
    x + y is z

proc add[T: Addable](a, b: T): T =
  return a + b
```

### Resolução de Sobrecarga de Conceito

Conceitos participam da resolução de sobrecarga.

### Correspondência de Subconjunto de Conceito

Um conceito pode ser um subconjunto de outro.

### Conceitos Recursivos

Conceitos podem ser definidos recursivamente.

---

## Declarações e Expressões

### Expressão de Lista de Declarações

```nim
var x = (echo "a"; echo "b"; 5)  # 5
```

### Declaração Discard

`discard` avalia uma expressão mas descarta o resultado:

```nim
discard someFunction()
```

### Contexto Void

Em contexto void, o resultado de uma expressão é ignorado.

### Declaração Var

```nim
var x = 10
var y, z = 20, 30
```

### Declaração Let

`let` cria uma variável imutável:

```nim
let x = 10
# x = 20  # Erro: x é imutável
```

### Identificador Especial `_` (underscore)

`_` é um identificador especial para valores descartáveis:

```nim
for _ in 1..10:
  echo "iterando"
```

### Descompactação de Tupla

```nim
var (x, y) = (10, 20)
```

### Seção Const

```nim
const
  x = 10
  y = "Hello"
```

### Declaração/Expressão Static

`static` força avaliação em tempo de compilação:

```nim
static:
  echo "Executado em tempo de compilação"
```

### Declaração If

```nim
if x > 0:
  echo "positivo"
elif x < 0:
  echo "negativo"
else:
  echo "zero"
```

### Declaração Case

```nim
case x
of 1, 3, 5:
  echo "ímpar"
of 2, 4, 6:
  echo "par"
else:
  echo "outra"
```

### Declaração When

`when` é uma versão em tempo de compilação de `if`:

```nim
when defined(windows):
  echo "Windows"
else:
  echo "Outro SO"
```

### Declaração When nimvm

```nim
when nimvm:
  echo "Executando no compilador VM"
```

### Declaração Return

```nim
proc foo(): int =
  return 42
```

### Declaração Yield

```nim
iterator countUp(n: int): int =
  for i in 0..<n:
    yield i
```

### Declaração Block

```nim
block minhaLabel:
  echo "dentro do bloco"
  break minhaLabel
```

### Declaração Break

```nim
for i in 1..10:
  if i == 5:
    break
```

### Declaração While

```nim
while x > 0:
  echo x
  dec x
```

### Declaração Continue

```nim
for i in 1..10:
  if i mod 2 == 0:
    continue
  echo i  # apenas ímpares
```

### Declaração Assembler

```nim
proc foo() {.asmNoStackFrame.} =
  asm """
    mov eax, 42
  """
```

### Declaração Using

`using` traz campos de um tipo para o escopo atual:

```nim
type
  Point = object
    x, y: int

proc foo() =
  var p = Point(x: 10, y: 20)
  using p
  echo x  # p.x
  echo y  # p.y
```

### Expressão If

```nim
var x = if a > 0: "positivo" else: "não positivo"
```

### Expressão When

```nim
type
  IntOrString = when sizeof(int) == 4: int32 else: int64
```

### Expressão Case

```nim
var x = case y
           of 0: "zero"
           of 1, 2: "um ou dois"
           else: "outro"
```

### Expressão Block

```nim
var z = block:
  var x = 10
  echo x
  x * 2
```

### Construtor de Tabela

```nim
var t = {
  "chave": "valor",
  "outra": 123
}
```

### Conversões de Tipo

```nim
var x: int = int(3.14)  # conversão explícita
```

### Casts de Tipo

```nim
var p: pointer = cast[pointer](x)
```

### O Operador addr

```nim
var x = 10
var p = addr(x)  # p é do tipo ptr int
```

### O Operador unsafeAddr

```nim
var x = 10
var p = unsafeAddr(x)  # similar a addr, mas não verifica segurança
```

---

## Procedimentos

### Marcador de Export

```nim
proc foo*() =  # * significa exportado
  echo "Hello"
```

### Sintaxe de Chamada de Método

```nim
proc add(a: var int, b: int) =
  a += b

var x = 10
x.add(5)  # método call syntax
add(x, 5)  # sintaxe normal
```

### Propriedades

```nim
type
  Container = object
    items*: seq[string]

proc items*(c: Container): seq[string] =
  return c.items

var c = Container()
c.items.add("Hello")
```

### Sintaxe de Invocação de Comando

```nim
echo "Hello" "World"  # equivalente a echo("Hello", "World")
```

### Closures

```nim
proc makeAdder(n: int): proc (x: int): int =
  return proc (x: int): int = x + n

var add10 = makeAdder(10)
echo add10(5)  # 15
```

#### Criando Closures em Loops

```nim
var procs: seq[proc ()]

for i in 0..<5:
  procs.add(proc () = echo i)

for p in procs:
  p()  # imprime 0, 1, 2, 3, 4
```

### Procedimentos Anônimos

```nim
var anon = proc (x: int): int =
  return x * 2

echo anon(5)  # 10
```

### Notação Do

```nim
open strutils

proc test() =
  "Hello".toUpper().echo  # usando do notation
```

### Func

`func` é um açúcar sintático para procedimento sem efeitos:

```nim
func square(x: int): int = x * x
```

### Rotinas

Rotinas incluem procedimentos, métodos, iteradores e macros.

### Operadores Ligados ao Tipo

```nim
type
  Vec2 = object
    x, y: float

proc `+`(a, b: Vec2): Vec2 =
  result = Vec2(x: a.x + b.x, y: a.y + b.y)

var v1 = Vec2(x: 1.0, y: 2.0)
var v2 = Vec2(x: 3.0, y: 4.0)
echo v1 + v2
```

### Builtins Não Sobrecarregáveis

Alguns builtins não podem ser sobrecarregados.

### Parâmetros Var

```nim
proc modify(x: var int) =
  x += 1

var y = 10
modify(y)
echo y  # 11
```

### Tipo de Retorno Var

```nim
proc getData(): var seq[int] =
  result = @[1, 2, 3]
  result[0] = 100
```

#### Direções Futuras

Suporte para tipos de retorno var pode ser expandido.

### NRVO

NRVO (Named Return Value Optimization) é aplicado automaticamente.

### Sobrecarga do Operador de Subscrito

```nim
type
  Matrix = object
    data: seq[seq[int]]

proc `[]`(m: Matrix, i, j: int): int =
  return m.data[i][j]
```

---

## Métodos

O suporte a métodos do Nim é baseado em invocação dinâmica em tempo de execução.

### Multi-Métodos

Multi-métodos permitem despacho múltiplo baseado em tipos.

### Inibir Resolução Dinâmica via procCall

```nim
type
  Base = object
  method foo(b: Base) = echo "Base.foo"

  Derived = object of Base
  method foo(d: Derived) = echo "Derived.foo"

var d = Derived()
procCall foo(d)  # Base.foo
d.foo()         # Derived.foo
```

---

## Iteradores e o Comando for

### Invocações Implícitas de items/pairs

```nim
for i, item in @[10, 20, 30]:
  echo i, item
```

### Iteradores de Primeira Classe

Iteradores podem ser passados como valores:

```nim
proc myIterator(): iterator (int, string) =
  yield (1, "one")
  yield (2, "two")

var it = myIterator()
for i, s in it():
  echo i, s
```

---

## Conversores

Conversores são usados para conversões implícitas de tipo:

```nim
converter dollarToInt(x: string): int =
  result = parseInt(x)

var s: string = "123"
var i: int = s  # conversão implícita
```

---

## Seções de Tipo

```nim
type
  Point = object
    x, y: int

  PointRef = ref Point

  PointPtr = ptr Point
```

---

## Tratamento de Exceções

### Declaração Try

```nim
try:
  riskyOperation()
except:
  echo "Exceção ocorreu"
```

### Expressão Try

```nim
var x = try:
  riskyFunction()
except:
  getDefault()
```

### Cláusulas Except

```nim
try:
  risky()
except IOError as e:
  echo "Erro de E/S: ", e.msg
except:
  echo "Outra exceção"
```

### Exceções Personalizadas

```nim
type
  MyError = object of ValueError

proc raiseMyError() =
  raise newException(MyError, "Meu erro")
```

### Declaração Defer

```nim
proc processFile() =
  let f = open("data.txt")
  defer: f.close()
  # fazer processamento
```

### Declaração Raise

```nim
raise newException(ValueError, "Valor inválido")
```

### Hierarquia de Exceção

```nim
type
  MyError = object of ValueError

raise newException(MyError, "Erro específico")
```

### Exceções Importadas

Exceções importadas precisam ser qualificadas se necessário.

---

## Sistema de Efeitos

O Nim rastreia efeitos de procedimentos para melhor análise de programa.

### Rastreamento de Exceção

O compilador infere quais exceções um procedimento pode lançar.

### Anotação EffectsOf

```nim
proc foo(): EffectsOf [IOError] = ...
```

### Rastreamento de Tag

Efeitos de tag podem ser definidos e rastreados.

### Efeitos Colaterais

Efeitos colaterais como efeitos de E/S podem ser rastreados.

### Efeito de Segurança GC

Procedimentos podem ser marcados como seguros ou inseguros para GC.

### Pragma Effects

```nim
proc foo() {.effectsOf: [].} =
  # sem efeitos
```

---

## Genéricos

### Procedimentos Genéricos

```nim
proc foo[T](x: T): T =
  return x

echo foo[int](42)
echo foo[string]("Hello")
```

### Operador is

```nim
proc bar[T](x: T) =
  when T is int:
    echo "int"
  else:
    echo "outro tipo"
```

### Classes de Tipo

Classes de tipo são uma forma de restrições de tipo.

### Genéricos Implícitos

O Nim pode inferir parâmetros genéricos automaticamente.

### Restrições de Inferência Genérica

Há algumas restrições sobre inferência genérica.

### Lookup de Símbolo em Genéricos

O escopo para lookup em genéricos é definido.

#### Símbolos Abertos e Fechados

Símbolos podem ser abertos ou fechados em genéricos.

### Declaração Mixin

```nim
mixin toString(x) =
  $x

var y = 10
mixin toString(y)  # expansão em tempo de compilação
```

### Declaração Bind

`bind` declarações símbolos em contextos específicos.

### Declarações Bind Delegadas

Delegação de bind para símbolos.

---

## Templates

### Parâmetros Typed vs Untyped

```nim
template foo(x: untyped) =  # x é sem tipo
  echo x

template bar(x: typed) =    # x tem tipo
  echo x
```

### Passando um Bloco de Código para um Template

```nim
template withCode(code: untyped) =
  code

withCode:
  echo "executando"
  for i in 0..<5:
    echo i
```

### Varargs de untyped

```nim
template foo(args: varargs[untyped]) =
  for arg in args:
    echo arg
```

### Ligação de Símbolo em Templates

Templates têm regras específicas de escopo.

### Construção de Identificador

```nim
template makeId(name: untyped): untyped =
  bindSym(name)
```

### Regras de Lookup para Parâmetros de Template

Lookup em templates segue regras específicas.

### Higiene em Templates

Templates são higiênicos — evitam conflitos de escopo.

### Limitações da Sintaxe de Chamada de Método

Algumas limitações existem para sintaxe de método com templates.

---

## Macros

### Exemplo de Debug

```nim
macro debugEcho(x: untyped): untyped =
  result = quote do:
    echo `x`, "=", `x`

var y = 10
debugEcho(y)  # y = 10
```

### bindSym

```nim
macro bindExample(name: untyped): untyped =
  bindSym(name)
```

### Blocos Pós-Declaração

Macros podem ser aplicados após blocos.

### Macro de Loop For

```nim
macro times(n: int, body: untyped): untyped =
  result = quote do:
    for i in 0..<`n`:
      `body`

5.times:
  echo i
```

### Macros de Declaração Case

Macros podem transformar declarações case.

---

## Tipos Especiais

### static[T]

`static[T]` força avaliação em tempo de compilação:

```nim
proc foo(x: static[int]) =
  echo x
```

### typedesc[T]

`typedesc[T]` é o descritor de tipo de T.

### Operador typeof

`typeof` retorna o tipo de uma expressão:

```nim
var x = 42
echo typeof(x)  # "int"
```

---

## Módulos

### Declaração Import

```nim
import strutils, sequtils
```

### Declaração Include

```nim
include "meu_modulo.nim"
```

### Nomes de Módulo em Imports

Módulos podem ser importados com diferentes estratégias de nomes.

### Importes Coletivos de um Diretório

```nim
import std/[strutils, sequtils]
```

### Caminhos de Import/Include Pseudo

Caminhos relativos podem ser usados.

### Declaração From Import

```nim
from strutils import toUpper, toLower
```

### Declaração Export

```nim
export strutils  # exporta todos os símbolos
```

### Regras de Escopo

#### Escopo de Bloco

Escopo é determinado por blocos.

#### Escopo de Tupla ou Objeto

Escopo em tipos compostos.

#### Escopo de Módulo

Escopo em nível de módulo.

### Pacotes

Módulos podem ser organizados em pacotes.

---

## Mensagens do Compilador

Mensagens do compilador podem ser geradas para:
- Avisos (hints)
- Avisos (warnings)
- Erros

---

## Pragmas

Pragmas fornecem metadados e diretivas ao compilador:

### Pragma Deprecated

```nim
proc oldProc() {.deprecated: "Use newProc".} =
  echo "antigo"
```

### Pragma CompileTime

```nim
proc compileTimeOnly() {.compileTime.} =
  echo "em tempo de compilação"
```

### Pragma NoReturn

```nim
proc fatalError() {.noreturn.} =
  raise newException(Exception, "Fatal")
```

### Pragma Acyclic

```nim
type
  Tree {.acyclic.} = object
    left, right: ref Tree
```

### Pragma Final

```nim
type
  Immutable {.final.} = object
    data: int
```

### Pragma Shallow

```nim
type
  Shallow {.shallow.} = object
    value: int
```

### Pragma Pure

```nim
proc pureFunc(x: int): int {.pure.} =
  return x + 1
```

### Pragma AsmNoStackFrame

```nim
proc asmFunc() {.asmNoStackFrame.} =
  asm "nop"
```

### Pragma Error

```nim
proc check(x: int) =
  if x < 0:
    {.error: "x deve ser >= 0".}
```

### Pragma Fatal

Similar a error, mas fatal.

### Pragma Warning

```nim
proc warnIfZero(x: int) =
  if x == 0:
    {.warning: "x é zero".}
```

### Pragma Hint

```nim
proc infoIfNegative(x: int) =
  if x < 0:
    {.hint: "x é negativo".}
```

### Pragma Line

```nim
{.line: 100.}
```

### Pragma LinearScanEnd

Para fins de otimização.

### Pragma ComputedGoto

Para otimização de saltos.

### Pragma Immediate

Força geração imediata de código.

### Pragma Redefine

Permite redefinições.

### Pragmas de Opção de Compilação

```nim
{.checks: off.}
{.boundsCheck: on.}
```

### Pragmas Push e Pop

```nim
{.push checks: off.}
# código com checks desligados
{.pop.}
```

### Pragma Register

Para registro de CPU específico.

### Pragma Global

Torna símbolo global.

### Desabilitando Certas Mensagens

```nim
{.warning[UnusedImport]: off.}
```

### Pragma Used

Marca símbolo como usado.

### Pragma Experimental

Marca código como experimental.

---

## Interface de Função Estrangeira

### Pragma ImportC

```nim
proc cFunction(x: cint) {.importc: "mylib".} = ...
```

### Pragma ExportC

```nim
proc nimFunction(x: int) {.exportc: "nim_exported".} =
  echo x
```

### Pragma ExportCpp

```nim
proc nimFunction(x: int) {.exportcpp: "nim_exported".} =
  echo x
```

### Pragma Extern

```nim
var externVar {.importc, extern.}: cint
```

### Pragma ByCopy

Passar por cópia em vez de referência.

### Pragma ByRef

Passar por referência.

### Pragma Varargs

```nim
proc variadicFunc(args: varargs[cint]) {.importc, varargs.} = ...
```

### Pragma Union

```nim
type
  UnionType {.union.} = object
    asInt: int
    asFloat: float
```

### Pragma Packed

Empacotar estrutura sem alinhamento.

### Pragma Dynlib para Import

```nim
proc libFunction() {.importc, dynlib: "mylib.so".} = ...
```

### Pragma Dynlib para Export

```nim
proc exportedFunc() {.exportc, dynlib: "mylib.so".} = ...
```

---

## Threads

### Pragma Thread

```nim
proc threadedFunc() {.thread.} =
  echo "em thread"
```

### Pragma Threadvar

```nim
var threadLocal {.threadvar.}: int = 0
```

### Threads e Exceções

Exceções não podem ser propagadas entre threads.

---

## Guardas e Travas

### Seções de Guardas e Travas

#### Protegendo Variáveis Globais

```nim
var x {.guard: myLock.}: int

proc accessX() =
  withLock myLock:
    inc x
```

#### Protegendo Locais Gerais

Guardas também podem proteger locais arbitrários.

---

## Links Relacionados

- [Biblioteca Padrão](../stdlib/README.md) - Módulos e APIs
- [Guia de Estilo](../style_guide/README.md) - Convenções de código
- [Ferramentas](../tools/README.md) - Ferramentas de desenvolvimento
- [Tutoriais](../tutorials/README.md) - Exemplos práticos
- [Gerenciamento de Memória](../memory/README.md) - Como o Nim gerencia memória

---

**Fonte Original**: https://nim-lang.org/docs/manual.html  
**Versão Nim**: 2.2.8  
**Data da Conversão**: 2025-03-16

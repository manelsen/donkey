# O Modelo de Memória do Nim

> **Fonte**: https://zevv.nl/nim-memory/

Este é um pequeno tutorial explicando como o Nim armazena dados na memória. Ele explicará essenciais que todo programador Nim deve saber, mas também se aprofundará na forma como o Nim organiza suas estruturas de dados como strings e seqs.

Para a maioria dos propósitos práticos, o Nim cuidará de todo o gerenciamento de memória para o seu programa sem incomodar você com os detalhes. Contanto que você se atenha às partes seguras da linguagem, você raramente precisará trabalhar com endereços de memória ou fazer alocações explícitas de memória. Isso muda, entretanto, quando você quer que seu código Nim interopere com código C externo ou bibliotecas C - neste caso, você pode precisar saber onde e como seus objetos Nim são armazenados na memória para poder passar isso para C, ou precisará saber como acessar dados alocados em C para torná-los acessíveis pelo Nim.

As primeiras partes deste documento serão familiares para leitores com um fundo em C ou C++, pois muito disso não é único para a linguagem Nim. Em contraste, algumas coisas podem ser novas para programadores vindos de linguagens dinâmicas como Python ou Javascript, onde o manuseio de memória é mais abstrato.

> **Nota**: A maioria — se não todas — deste documento se aplica ao gerador de código C/C++, pois o backend Javascript não usa memória crua mas depende de objetos Javascript em vez disso.

## Índice

1. [Introdução](#introdução)
2. [Conceitos Básicos de Memória de Computador](#conceitos-básicos-de-memória)
   - [Tamanho de Palavra](#tamanho-de-palavra)
   - [Endianness](#endianness)
3. [Duas Formas de Organizar Memória](#duas-formas-de-organizar-memória)
   - [A Pilha (Stack)](#a-pilha-stack)
     - [Teoria da Pilha](#teoria-da-pilha)
     - [Pilhas na Prática](#pilhas-na-prática)
   - [O Heap](#o-heap)
     - [Teoria do Heap](#teoria-do-heap)
     - [O Heap na Prática](#o-heap-na-prática)
4. [Organização de Memória no Nim](#organização-de-memória-no-nim)
   - [Usando Ponteiros](#usando-ponteiros)
   - [A Pilha: Variáveis Locais](#a-pilha-variáveis-locais)
   - [Referências Traçadas e o Coletor de Lixo](#referências-traçadas-e-o-coletor-de-lixo)
5. [Como o Nim Armazena Dados na Memória](#como-o-nim-armazena-dados-na-memória)
   - [Tipos Primitivos](#tipos-primitivos)
   - [Tipos Compostos: Objects](#tipos-compostos-objects)
   - [Strings e Seqs](#strings-e-seqs)
     - [Vamos Falar de Seqs](#vamos-falar-de-seqs)
     - [Crescendo uma Seq](#crescendo-uma-seq)
6. [Conclusão](#conclusão)

---

## Introdução

Este tutorial fornece uma base sólida sobre como o Nim gerencia memória. É especialmente útil se você:

- Quer interop com código C/C++
- Está escrevendo código de performance crítica
- Precisa entender como funcionam ponteiros e referências
- Quer evitar vazamentos de memória

O Nim abstrai grande parte do gerenciamento de memória, mas entender o que acontece "por baixo dos panos" pode ajudar você a:

- Escrever código mais eficiente
- Depurar problemas de memória
- Interagir com bibliotecas C/C++
- Entender melhor como estruturas de dados funcionam

---

## Conceitos Básicos de Memória de Computador

Esta seção fornece uma introdução breve e abstrata (aviso: simplificações grossas à frente!) sobre memória de computador, e como ela parece do ponto de vista de uma CPU e um programa de computador.

### Tamanho de Palavra

A memória principal (RAM) de um computador consiste em muitos locais de memória, cada um com um endereço único. Dependendo da arquitetura da CPU, o tamanho de cada local de memória (o "tamanho de palavra") tipicamente varia entre um byte (8 bit) a oito bytes (64 bit), enquanto a CPU geralmente também é capaz de acessar palavras maiores como pedaços menores. Algumas arquiteturas podem ler e escrever memória de endereços arbitrários, enquanto outras só podem acessar memória em endereços que são múltiplos do tamanho de palavra.

A CPU acessa memória usando instruções específicas que permitem ler ou escrever dados de um determinado tamanho de palavra de ou para um determinado endereço. Por exemplo, ela pode armazenar o valor 0x12345 como um número de 32 bit no endereço 0x100000. A instrução de assembly de baixo nível para fazer isso pode parecer algo assim:

```asm
mov [0x100000], 0x12345
```

Aqui está como a memória no endereço 0x100000 parecerá após a instrução acima completar, com cada coluna representando um byte:

```
            00   01   02   03   04
          +----+----+----+----+----
0x100000  | 00 | 01 | 23 | 45 | ..
          +----+----+----+----+----
```

### Endianness

Para complicar um pouco mais, a ordem real dos bytes dentro de uma palavra varia entre tipos de CPU — algumas CPUs colocam o byte mais significativo primeiro, enquanto outras colocam o byte menos significativo primeiro. Isso é chamado de **endianness** de uma CPU.

- **Little Endian** (mais comum): A maioria das CPUs hoje em dia (Intel compatível, x86, amd64, a maioria das famílias ARM) são little endian. O inteiro 0x1234 é armazenado com o byte **menos** significativo primeiro:
  ```
  00   01
+----+----+
| 34 | 12 |
+----+----+
  ```

- **Big Endian**: Algumas outras CPUs como Freescale ou OpenRISC são big endian. O inteiro 0x1234 é armazenado com o byte **mais** significativo primeiro. A maioria dos protocolos de rede serializa dados em ordem big endian quando os envia na rede; é por isso que big endian também é conhecido como *endian de rede*:
  ```
  00   01
+----+----+
| 12 | 34 |
+----+----+
  ```

**Mais importante de tudo**: se você quer escrever código portátil, nunca faça suposições sobre a endianidade de sua máquina ao escrever dados binários em disco ou pela rede e certifique-se de converter explicitamente seus dados para a endianidade apropriada.

---

## Duas Formas de Organizar Memória

Tradicionalmente, programas C usam dois métodos comuns para organizar objetos na memória do computador: a **pilha** e o **heap**. Ambos os métodos servem propósitos diferentes e têm características muito diferentes. O código Nim é compilado para código C ou C++, então o Nim naturalmente compartilha o modelo de memória dessas linguagens.

### A Pilha (Stack)

Uma pilha é uma região de memória onde os dados são sempre adicionados e removidos de uma extremidade. Isso é chamado de "último-a-entrar, primeiro-a-sair" (LIFO - Last-In-First-Out).

#### Teoria da Pilha

Uma boa analogia para uma pilha é uma pilha de pratos na cozinha de um restaurante: pratos novos são tirados da lavadora e colocados no topo; quando pratos são necessários, eles também são tirados do topo. Pratos nunca são inseridos no meio ou no fundo, e pratos nunca são tirados do meio ou fundo da pilha.

Por razões históricas, pilhas de computador geralmente funcionam de cima para baixo: novos dados são adicionados a e removidos do fundo da pilha, mas isso não muda o mecanismo em si.

```
+--------------+ <-- topo da pilha
|              |
|   em uso     |
|              |
|              |
+--------------+ <-- ponteiro da pilha
|              |
|              | | novos dados adicionados
:    livre      : v no fundo
```

A administração para uma pilha é bem simples: o programa precisa manter registro de apenas um endereço que aponta para o fundo atual da pilha — isso é comumente conhecido como o **ponteiro da pilha**. Quando dados são adicionados à pilha, eles são copiados no local e o ponteiro da pilha é decrementado. Quando dados são removidos da pilha, eles são copiados para fora e o ponteiro da pilha é novamente incrementado.

#### Pilhas na Prática

No Nim, C e a maioria das outras linguagens compiladas, a pilha é usada para dois propósitos diferentes:

1. **Primeiro, é usada como um local para armazenar variáveis temporárias locais**. Essas variáveis só existem em uma função enquanto a função estiver ativa (ou seja, ela não retornou ainda).

2. **O compilador também usa a pilha para um tipo diferente de gerenciamento de livro**: cada vez que uma função é chamada, o endereço da próxima instrução após a instrução de chamada é colocado na pilha — esse é o **endereço de retorno**. Quando a função retorna, ela encontra esse endereço na pilha e salta para ele.

A combinação dos dados dos dois mecanismos acima compõem um **quadro de pilha** (stack frame): essa é uma seção da pilha que mantém o endereço de retorno da função ativa atual, junto com todas as suas variáveis locais.

Durante a execução do programa, é assim que a pilha parecerá se seu programa estiver duas funções aninhadas fundo:

```
+----------------+ <-- topo da pilha
| endereço de retorno |
| variável       | <-- quadro de pilha #1
| variável       |
| ...            |
+----------------+
| endereço de retorno |
| variável       | <-- quadro de pilha #2
| ...            |
+----------------+ <-- ponteiro da pilha
|     livre       |
:                :
```

Usar a pilha para ambos dados e endereços de retorno é um truque bem elegante e tem o efeito colateral agradável de oferecer alocação e limpeza automáticas de armazenamento de dados em um programa.

Pilhas também funcionam bem com threads: cada thread simplesmente tem sua própria pilha, armazenando suas próprias variáveis locais e mantendo seus próprios quadros de pilha.

Agora você sabe onde o Nim obtém as informações quando gera um **trace de pilha** (stack trace) quando atinge um erro de tempo de execução ou exceção: Ele encontrará o endereço da função mais ativa na pilha e imprimirá seu nome. Então ele vai procurar mais acima na pilha pela próxima função ativa, até o topo.

### O Heap

Ao lado da pilha, o heap é o outro local para armazenar dados em um programa de computador. Enquanto a pilha é tipicamente usada para manter variáveis locais, o heap pode ser usado para armazenamento mais dinâmico.

#### Teoria do Heap

Um heap é uma região de memória que é um pouco como um armazém. A região de memória é chamada de **arena**:

```
:              : ^ heap pode crescer no topo
|              | |
|              |
|    livre!     | <-- A arena do heap
|              |
|              |
+--------------+
```

Quando um programa quer armazenar dados, ele primeiro calculará quanto armazenamento precisará. Então ele irá ao caixeiro do armazém (o alocador de memória) e solicitar um local para armazenar os dados. O caixeiro tem um livro-caixa onde mantém registro de todas as alocações no armazém, e encontrará um local livre que seja grande o suficiente para caber os dados. Ele então fará uma entrada no livro-caixa de que a área naquele endereço e tamanho agora está ocupada, e retorna o endereço ao programa. O programa agora pode armazenar e recuperar seus dados dessa área na memória à vontade.

```
:              :
|    livre      |
+--------------+
|              |
|  alocado     | <-- endereço da alocação
+--------------+
```

O processo acima pode ser repetido, alocando outros blocos no heap, alguns de tamanhos diferentes:

```
:              :
|    livre      |
+--------------+
|              |
| alocado #3   |
|              |
+--------------+
| alocado #2   |
+--------------+
| alocado #1   |
+--------------+
```

Quando o bloco de dados não é mais usado, o programa dirá ao alocador de memória o endereço do bloco. O alocador procura o endereço no livro-caixa, e remove a entrada. Esse bloco agora está livre para uso futuro. É assim que a figura acima parecerá quando o bloco #2 é liberado:

```
:              :
|    livre      |
+--------------+
|              |
| alocado #3   |
|              |
+--------------+
|    livre      | <-- Há um buraco no heap!
+--------------+
| alocado #1   |
+--------------+
```

Como você pode ver, liberar o bloco #2 agora deixa um buraco no heap, o que pode levar a problemas no futuro. Considere a próxima solicitação de alocação:

- Se o tamanho da próxima alocação for menor então o tamanho do buraco, o alocador pode reusar o espaço livre no buraco; mas como a nova solicitação é menor, um novo buraco menor será deixado após o novo bloco
- Se o tamanho da próxima alocação for maior então o tamanho do buraco, o alocador terá que encontrar um local livre maior em algum lugar, deixando o buraco aberto

A única forma de reusar eficientemente o buraco é se a próxima alocação for do tamanho exato do buraco.

Uso pesado de um heap com muitos objetos de tamanhos diferentes pode levar a um fenômeno chamado **fragmentação**. Isso significa que o alocador não é capaz de usar eficientemente 100% do tamanho da arena para atender solicitações de alocação, eficientemente desperdiçando uma parte da memória disponível.

#### O Heap na Prática

No Nim, todos os seus dados são armazenados na pilha, a menos que você explicitamente solicite que vão para o heap: o proc `new()` é tipicamente usado para alocar memória no heap para um novo objeto:

```nim
type Thing = object
  a: int

var t = new Thing
```

O snippet acima alocará memória no heap para armazenar um objeto do tipo `Thing`. O **endereço** do bloco de memória recém-alocado é retornado por `new`, que agora é do tipo `ref Thing`. Um `ref` é um tipo especial de ponteiro que é geralmente gerenciado pelo Nim para você. Mais sobre isso na seção [Referências Traçadas e o Coletor de Lixo](#referências-traçadas-e-o-coletor-de-lixo)

---

## Organização de Memória no Nim

Contanto que você se atenha às partes **seguras** da linguagem, o Nim cuidará de gerenciar alocações de memória para você. Ele garantirá que seus dados são armazenados no local apropriado, e liberados quando você não mais precisar deles. No entanto, se a necessidade surgir, o Nim oferece a você controle completo também, permitindo que você escolha exatamente como e onde armazenar seus dados.

O Nim oferece algumas funções úteis para permitir que você inspecione como seus dados são organizados na memória. Estas serão usadas nos exemplos nas seções abaixo para inspecionar como e onde o Nim armazena seus dados:

| Função | Descrição |
|---------|------------|
| `addr(x)` | Este proc retorna o endereço da variável `x`. Para uma variável de tipo `T`, seu endereço terá tipo `ptr T` |
| `unsafeAddr(x)` | Este proc é basicamente o mesmo que `addr()`, mas pode ser usado mesmo se o Nim achar que não seria seguro obter o endereço de um objeto — mais sobre isso depois |
| `sizeof(x)` | Retorna o tamanho da variável `x` em bytes |
| `typeof(x)` | Retorna a representação em string do tipo da variável `x` |

O resultado de `addr(x)` e `unsafeAddr(x)` em um objeto do tipo `T` tem um resultado do tipo `ptr T`. O Nim não sabe como imprimir isso por padrão, então usaremos `repr()` para formatar o tipo bem para nós:

```nim
var a: int
echo a.addr.repr
# ptr 0x56274ece0c60 --> 0
```

### Usando Ponteiros

Basicamente, um ponteiro nada mais é do que um tipo especial de variável que mantém um endereço de memória — ele aponta para algo mais na memória. Como brevemente mencionado acima, há dois tipos de ponteiros no Nim:

- **`ptr T`** para **referências não traçadas**, também conhecidas como **ponteiros**
- **`ref T`** para **referências traçadas**, para memória que é gerenciada pelo Nim

O tipo de ponteiro `ptr T` é considerado **inseguro**. Ponteiros apontam para objetos alocados manualmente ou para objetos em algum outro lugar na memória, e é sua tarefa como programador garantir que seus ponteiros sempre apontem para dados válidos.

Quando você quer acessar os dados na memória para a qual o ponteiro aponta — o conteúdo do endereço com aquele índice numérico — você precisa **desreferenciar** (ou em curto, **deref**) o ponteiro.

No Nim você pode usar um subscrito de array vazio `[]` para fazer isso, análogo ao usar o operador de prefixo `*` em C. O snippet abaixo mostra como criar um alias para um int e mudar seu valor.

```nim
var a = 20   # 1
var p = a.addr   # 2
p[] = 30        # 3
echo a  # --> 30
```

| # | Explicação |
|---|-----------|
| 1 | Aqui uma variável normal `a` é declarada e inicializada com valor 20 |
| 2 | `p` é um ponteiro do tipo `ptr int`, apontando para o endereço do int `a` |
| 3 | O operador `[]` é usado para desreferenciar o ponteiro p. Como `p` é um ponteiro do tipo `ptr int` que aponta para o endereço da memória onde `a` está armazenado, a variável desreferenciada `p[]` é novamente do tipo int. As variáveis `a` e `p[]` agora se referem ao mesmo local de memória exato, então atribuir um valor a `p[]` também mudará o valor de `a` |

Para acesso a objeto ou tupla, o Nim realizará desreferenciamento automático para você: o operador de acesso normal `.` pode ser usado assim como em um objeto normal.

### A Pilha: Variáveis Locais

Variáveis locais (também chamadas variáveis **automáticas**) são o método padrão pelo qual o Nim armazena suas variáveis e dados.

O Nim reservará espaço para sua variável na pilha, e ela permanecerá lá enquanto estiver no escopo. Na prática, isso significa que a variável existirá enquanto a função na qual foi declarada não retornar. Assim que a função retornar, a pilha **desempilha** (unwinds) e as variáveis sumem.

Aqui estão alguns exemplos de variáveis que serão armazenadas na pilha:

```nim
type Thing = object
  a, b: int

var a: int
var b = 14
var c: Thing
var d = Thing(a: 5, b: 18)
```

### Referências Traçadas e o Coletor de Lixo

Nas seções anteriores vimos que ponteiros no Nim como retornados por `addr()` são do tipo `ptr T`, mas vimos que `new` retorna um `ref T`.

Embora ambos `ptr` e `ref` sejam ponteiros para dados, há uma diferença importante entre os dois:

- Um **`ptr T`** é apenas um ponteiro — uma variável mantendo um endereço que aponta para dados vivendo em outro lugar. Você como programador é responsável por garantir que este ponteiro está referenciando memória válida quando o usa.
- Um **`ref T`** é uma **referência traçada**: isso também é um endereço apontando para algo mais, mas o Nim manterá registro dos dados para os quais ele aponta para você, e garantirá que isso será liberado quando não for mais necessário. Isso é conhecido como **coleta de lixo** (garbage collection), ou **GC** para curto.

A única maneira de adquirir um ponteiro de tipo `ref T` é alocar a memória usando o proc `new()`. O Nim reservará a memória para você, e também começará a manter registro de onde no código esses dados são referenciados. Quando o runtime Nim vir que os dados não são mais referenciados, ele sabe que é seguro descartá-los e os liberará automaticamente para você.

---

## Como o Nim Armazena Dados na Memória

Esta seção mostrará alguns experimentos onde investigamos como o Nim armazena vários tipos de dados na memória.

### Tipos Primitivos

Um tipo **primitivo** ou **escalar** é um valor "único" como um `int`, um `bool` ou um `float`. Escalares são geralmente mantidos na pilha, a menos que sejam parte de um tipo de contêiner como um objeto.

Vamos ver como o Nim gerencia memória para tipos primitivos para nós. O snippet abaixo primeiro cria uma variável `a` do tipo `int` e imprime essa variável e seu tamanho. Então ele criará uma segunda variável `b` do tipo `ptr int` que é chamada de **ponteiro**, e agora mantém o **endereço** da variável `a`.

```nim
var a = 9
echo a.repr
echo sizeof(a)

var b = a.addr
echo b.repr
echo sizeof(b)
```

Na minha máquina posso receber a seguinte saída:

```
9           # 1
8           # 2
ptr 0x300000 --> 9  # 3
8           # 4
```

| # | Explicação |
|---|-----------|
| 1 | Sem surpresa aqui: este é o valor da variável `a` |
| 2 | Este é o tamanho da variável, em bytes. 8 bytes fazem 64 bit, o que acontece de ser o tamanho padrão para tipos `int` no Nim na minha máquina. Até aqui tudo bem. |
| 3 | Esta linha mostra uma representação da variável `b`. `b` mantém o endereço da variável `a`, que por acaso vive no endereço `0x300000`. No Nim um endereço é conhecido como um `ref` ou um `ponteiro`. |
| 4 | `b` em si também é uma variável, que não é do tipo `ptr int`. Na minha máquina endereços de memória também têm um tamanho de 64 bit, o que equivale a 8 bytes. |

O acima pode ser representado pelo seguinte diagrama:

```
           +---------------------------------------+
0x??????:  | 00 | 00 | 00 | 00 | 30 | 00 | 00 | 00 | b: ptr int =
           +---------------------------------------+    0x300000
                               |
                               |
                               v
           +---------------------------------------+
0x300000:  | 00 | 00 | 00 | 00 | 00 | 00 | 00 | 09 | a: int = 9
           +---------------------------------------+
```

### Tipos Compostos: Objects

Vamos colocar um objeto mais complicado na pilha e ver o que acontece:

```nim
type Thing = object   # 1
  a: uint32
  b: uint8
  c: uint16

var t: Thing   # 2

echo "size t.a ", t.a.sizeof
echo "size t.b ", t.b.sizeof
echo "size t.c ", t.c.sizeof
echo "size t   ", t.sizeof   # 3

echo "addr t.a ", t.a.addr.repr
echo "addr t.b ", t.b.addr.repr
echo "addr t.c ", t.c.addr.repr
echo "addr t   ", t.addr.repr   # 4
```

No Nim, um objeto é apenas uma forma de agrupar variáveis em um contêiner útil, garantindo que sejam colocadas próximas umas das outras na memória da mesma forma que C faria.

Aqui está a saída na minha máquina:

```
size t.a  4  # 1
size t.b  1
size t.c  2
size t   8  # 2
addr t   ptr 0x300000 --> [a = 0, b = 0, c = 0]  # 3
addr t.a ptr 0x300000 --> 0  # 4
addr t.b ptr 0x300004 --> 0
addr t.c ptr 0x300006 --> 0  # 5
```

Vamos através da saída:

| # | Explicação |
|---|-----------|
| 1 | Primeiro obter o tamanho dos campos do objeto. `a` foi declarado como um `uint32`, que é 4 bytes grande, `b` é um `uint8` que é 1 byte, e `c` é um `uint16` que é 2 bytes grande. conferido! |
| 2 | Aqui há um pouco de surpresa: imprimir o tamanho do objeto contêiner `t`, que parece ter 8 bytes. Mas isso não soma, pois o conteúdo do objeto é apenas 4+1+2 = 7 bytes! Mais sobre isso abaixo. |
| 3 | Vamos obter o endereço do objeto `t`: na minha máquina foi colocado no endereço `0x300000` na pilha. |
| 4 | Aqui podemos ver que o campo `t.a` fica exatamente no mesmo local na memória que o objeto em si: `0x300000`. O endereço de `t.b` é `0x300004`, que é 4 bytes depois de `t.a`. Isso faz sentido, pois `t.a` é quatro bytes grande. |
| 5 | O endereço de `t.c` é `0x300006`, que é 2 (!) bytes depois de `t.b`, mas `t.b` é apenas um byte grande? |

Vamos fazer um pequeno desenho do que aprendemos acima:

```
              00   01   02   03   04   05   06   07
            +-------------------+----+----+---------+
  0x300000:  | a                 | b  | ?? | c       |
            +-------------------+----+----+---------+
            ^                   ^         ^
            |                   |         |
         endereço de           addr      addr
         t e t.a             de t.b     de t.c
```

Então é assim que nosso objeto `Thing` parece na memória. Então o que há com o buraco marcado `??` no deslocamento 5, e por que o tamanho total não é 7 mas 8 bytes?

Isso é causado por algo que o compilador faz que é chamado de **alinhamento** (alignment), para tornar mais fácil para a CPU acessar dados na memória. Garantindo que objetos são bem alinhados na memória em múltiplos de seu tamanho (ou múltiplos do tamanho de palavra da arquitetura), a CPU pode acessar a memória mais eficientemente. Isso geralmente resulta em código mais rápido, ao preço de desperdiçar um pouco de memória.

(Você pode sugerir ao compilador Nim para não fazer alinhamento mas colocar os campos de um objeto de costas na memória usando o pragma `{.packed.}` — consulte o [Manual da Linguagem Nim](../manual/pragmas.md) para detalhes)

### Strings e Seqs

As seções acima descreveram como o Nim gerencia objetos relativamente simples e estáticos na memória. Esta seção entrará na implementação de tipos de dados mais complexos e dinâmicos que fazem parte da linguagem Nim: strings e seqs.

No Nim, os tipos de dados `string` e `seq` são intimamente relacionados. Estes são basicamente uma longa fila de objetos do mesmo tipo (caracteres para strings, qualquer outro tipo para seqs). O que é diferente para esses tipos é que eles podem crescer ou diminuir dinamicamente na memória.

#### Vamos Falar de Seqs

Vamos criar uma `seq` e fazer alguns experimentos com ela:

```nim
var a = @[ 30, 40, 50 ]
```

Vamos perguntar ao Nim qual é o tipo da variável `a`:

```nim
var a = @[ 30, 40, 50 ]
echo typeof(a)   # --> seq[int]
```

Vemos que o tipo é `seq[int]`, que era o esperado.

Agora, vamos adicionar algum código para ver como o Nim armazena os dados:

```nim
var a = @[ 0x30, 0x40, 0x50 ]
echo a.repr
echo a.len
echo a[0].addr.repr
echo a[1].addr.repr
```

E aqui está a saída na minha máquina:

```
ptr 0x300000 --> 0x900000@[0x30, 0x40, 0x50]  # 1
3  # 2
ptr 0x900010 --> 0x30  # 3
ptr 0x900018 --> 0x40  # 4
```

O que pode ser deduzido disso?

| # | Explicação |
|---|-----------|
| 1 | A variável `a` em si é colocada na pilha, que por acaso está no endereço `0x300000` na minha máquina. `A` é algum tipo de ponteiro que aponta para o endereço `0x900000` que está no heap! E é onde a seq real vive. |
| 2 | Esta seq contém 3 elementos, como deveria ser. |
| 3 | `a[0]` é o primeiro elemento da seq. Seu valor é `0x30`, e está armazenado no endereço `0x900010`, que é logo após a seq em si |
| 4 | O segundo item na seq é `a[1]`, que é colocado no endereço `0x900018`. Isso faz sentido perfeito, pois o tamanho de um `int` é 8 bytes, e todos os ints na seq são colocados de costas na memória. |

Vamos fazer outro pequeno desenho novamente. Sabemos que `a` é um ponteiro vivendo na pilha, que se refere a algo no heap com um tamanho de 16 bytes, seguido pelos elementos da nossa seq:

```
             pilha
           +---------------------------------------+
0x300000   | 00 | 00 | 00 | 00 | 90 | 00 | 00 | 00 | a: seq[int]
           +---------------------------------------+
                               |
             heap              v
           +---------------------------------------+
0x900000   | ?? | ?? | ?? | ?? | ?? | ?? | ?? | ?? |
           +---------------------------------------+
0x900008   | ?? | ?? | ?? | ?? | ?? | ?? | ?? | ?? |
           +---------------------------------------+
0x900010   | 00 | 00 | 00 | 00 | 00 | 00 | 00 | 30 | a[0] = 0x30
           +---------------------------------------+
0x900018   | 00 | 00 | 00 | 00 | 00 | 00 | 00 | 40 | a[1] = 0x40
           +---------------------------------------+
0x900020   | 00 | 00 | 00 | 00 | 00 | 00 | 00 | 50 | a[2] = 0x50
           +---------------------------------------+
```

Isso quase explica tudo da seq, exceto pelos 16 bytes desconhecidos no começo do bloco: esta é a área onde o Nim armazena suas informações internas sobre a seq.

Esses dados são normalmente ocultos do usuário, mas você pode simplesmente encontrar a implementação desse cabeçalho na biblioteca de sistema do Nim, e ela parece assim:

```nim
type TGenericSeq = object
  len: int      # 1
  reserved: int # 2
```

| # | Descrição |
|---|-----------|
| 1 | O campo `len` é usado pelo Nim para armazenar o comprimento atual da seq — ou seja, quantos elementos há nela |
| 2 | O campo `reserved` é usado para manter registro do tamanho real do armazenamento dentro da seq — por razões de performance o Nim pode reservar um espaço maior com antecedência para evitar redimensionar a seq quando novos itens precisam ser adicionados |

Vamos fazer um pequeno experimento para inspecionar o que está no cabeçalho da nossa seq (código inseguro à frente!):

```nim
type TGenericSeq = object   # 1
  len, reserved: int

var a = @[10, 20, 30]
var b = cast[ptr TGenericSeq](a)   # 2
echo b.repr
```

| # | Explicação |
|---|-----------|
| 1 | O objeto `TGenericSeq` original não é exportado da lib do sistema, então aqui o mesmo objeto é definido |
| 2 | Aqui a variável `a` é convertida (cast) para o tipo `TGenericSeq` |

Quando imprimimos o resultado com `echo b.repr`, a saída parece assim:

```
ptr 0x900000 --> [len = 3, reserved = 3]
```

Eis! Temos nossa seq com um tamanho de 3, e tem espaço reservado para 3 elementos no total. A próxima seção explicará o que acontece quando mais campos são adicionados a uma seq.

#### Crescendo uma Seq

O snippet abaixo começa com a mesma seq, e então adiciona novos elementos. Cada iteração ele imprimirá o cabeçalho da seq:

```nim
type TGenericSeq = object
  len, reserved: int

var a = @[10, 20, 30]

for i in 0..4:
  echo cast[ptr TGenericSeq](a).repr
  a.add i
```

Aqui está a saída, veja se você pode detectar os bits interessantes:

```
ptr 0x900000 --> [len = 3, reserved = 3]  # 1
ptr 0x900070 --> [len = 4, reserved = 6]  # 2
ptr 0x900070 --> [len = 5, reserved = 6]  # 3
ptr 0x900070 --> [len = 6, reserved = 6]
ptr 0x9000d0 --> [len = 7, reserved = 12]  # 4
```

| # | Explicação |
|---|-----------|
| 1 | Esta é a seq original de 3 elementos: ela é armazenada no heap no endereço `0x900000`, tem um comprimento de 3 elementos, e armazenamento reservado para 3 elementos também |
| 2 | Um elemento foi adicionado, e algumas coisas notáveis aconteceram: <br>• o campo `len` foi aumentado para 4, o que faz sentido perfeito pois a seq agora contém 4 elementos <br>• o campo `reserved` aumentou de 3 para 6. Isso é porque o Nim dobra o tamanho do armazenamento ao fazer uma nova alocação — isso é mais eficiente ao adicionar dados repetidamente sem ter que redimensionar a alocação para cada `add()` <br>• note que o endereço da seq em si também mudou! A razão para isso é que a alocação de memória inicial para os dados da seq no heap não era grande o suficiente para caber o novo elemento, então o Nim teve que encontrar um pedaço maior de memória para manter os dados. É provável que o alocador já tivesse reservado a área logo após a seq para outra coisa, então não foi possível crescer essa área. Em vez disso, uma nova alocação em algum outro local no heap foi feita, os dados antigos da seq foram copiados do local antigo para o novo local, e o novo elemento foi adicionado. |
| 3 | Ao adicionar o quarto elemento acima, o Nim redimensionou o armazenamento da seq para manter 6 elementos — isso permite adicionar dois mais elementos sem ter que fazer uma alocação maior. Há agora 6 elementos colocados na seq, com um tamanho total reservado para 6 elementos. |
| 4 | E aqui a mesma coisa acontece uma vez mais: O bloco não é grande o suficiente para caber o sétimo item, então a seq inteira é movida para outro local, e a alocação é escalada para manter 12 elementos. |

---

## Conclusão

Este documento arranhou apenas a superfície de como o Nim lida com memória, há muito mais para contar. Aqui estão alguns assuntos que acho que também merecem um capítulo um dia, mas que não cheguei a escrever ainda:

- Uma discussão mais elaborada sobre coleta de lixo, e os sabores de GC disponíveis no Nim
- Usar Nim sem um coletor de lixo / sistemas embarcados com memória apertada
- O novo runtime Nim!
- Uso de memória em closures/iteradores/async — locais nem sempre vão para a pilha
- FFI: Discussão e exemplos de passar dados entre C e Nim

Este é um documento em progresso, quaisquer comentários são muito apreciados. A fonte pode ser encontrada no github em https://github.com/zevv/nim-memory

---

## Links Relacionados

- [Biblioteca Padrão](../stdlib/README.md) - Módulos e APIs do Nim
- [Manual da Linguagem](../manual/README.md) - Referência completa da linguagem
- [Manual de Destrutores](../manual/destrutores.md) - Atribuições, movimentos e destruição
- [FFI no Manual](../manual/ffi.md) - Interface com C/C++

---

**Fonte Original**: https://zevv.nl/nim-memory/  
**Data da Conversão**: 2025-03-16

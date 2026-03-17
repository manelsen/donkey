# Biblioteca Padrão Nim (Standard Library)

> **Autor**: Andreas Rumpf  
> **Versão**: 2.2.8  
> **Fonte**: https://nim-lang.org/docs/lib.html

## Índice

1. [Introdução](#introdução)
2. [Bibliotecas Puras](#bibliotecas-puras)
   - [Imports Automáticos](#imports-automáticos)
   - [Core](#core)
   - [Algoritmos](#algoritmos)
   - [Coleções](#coleções)
   - [Manipulação de Strings](#manipulação-de-strings)
   - [Manipulação de Tempo](#manipulação-de-tempo)
   - [Serviços Genéricos de Sistema Operacional](#serviços-genéricos-de-sistema-operacional)
   - [Bibliotecas Matemáticas](#bibliotecas-matemáticas)
   - [Protocolos de Internet](#protocolos-de-internet)
   - [Threading](#threading)
   - [Parseres](#parseres)
   - [Docutils](#docutils)
   - [Processamento de XML](#processamento-de-xml)
   - [Geradores](#geradores)
   - [Hashing](#hashing)
   - [Serialização](#serialização)
   - [Miscelânea](#miscelânea)
   - [Módulos para Backend JavaScript](#módulos-para-backend-javascript)
3. [Bibliotecas Impuras](#bibliotecas-impuras)
   - [Expressões Regulares](#expressões-regulares)
   - [Suporte a Banco de Dados](#suporte-a-banco-de-dados)
   - [Serviços Genéricos de Sistema Operacional](#serviços-genéricos-de-sistema-operacional-1)
4. [Wrappers](#wrappers)
   - [Específico do Windows](#específico-do-windows)
   - [Específico do UNIX](#específico-do-unix)
   - [Expressões Regulares](#expressões-regulares-1)
   - [Suporte a Banco de Dados](#suporte-a-banco-de-dados-1)
   - [Programação de Rede](#programação-de-rede)
5. [Nimble](#nimble)

---

## Introdução

A biblioteca do Nim é dividida em **bibliotecas puras**, **bibliotecas impuras** e **wrappers**.

Bibliotecas puras não dependem de qualquer binário externo `*.dll` ou `lib*.so`, enquanto bibliotecas impuras dependem. Um wrapper é uma biblioteca impura que é uma interface de baixo nível para uma biblioteca C.

Leia [este documento](../manual/apis.md) para uma visão geral rápida do design de API.

---

## Nimble

A biblioteca padrão do Nim cobre apenas o básico. Confira [https://nimble.directory/](https://nimble.directory/) para uma lista de pacotes de terceiros.

---

## Bibliotecas Puras

### Imports Automáticos

- **[system](system.md)** - Procedimentos básicos e operadores que todo programa precisa. Também fornece facilidades de E/S para leitura e escrita de arquivos de texto e binários. É importado implicitamente pelo compilador. Não importe diretamente. Depende de "mágica" do compilador para funcionar.

### Core

- **[atomics](atomics.md)** - Tipos e operações para operações atômicas e algoritmos sem bloqueio.
- **[bitops](bitops.md)** - Fornece uma série de métodos de baixo nível para manipulação de bits.
- **[compilesettings](compilesettings.md)** - Consultar o compilador sobre configurações diversas do código.
- **[cpuinfo](cpuinfo.md)** - Procedimentos para determinar o número de CPUs / núcleos.
- **[effecttraits](effecttraits.md)** - Acesso aos efeitos `.raises` inferidos para o sistema de macros do Nim.
- **[endians](endians.md)** - Auxiliadores que lidam com diferentes ordens de bytes.
- **[locks](locks.md)** - Travas e variáveis de condição para Nim.
- **[macrocache](macrocache.md)** - Fornece uma API para macros coletarem informações em tempo de compilação através de módulos.
- **[macros](macros.md)** - Contém a API de AST e documentação do Nim para escrever macros.
- **[rlocks](rlocks.md)** - Travas reentrantes para Nim.
- **[typeinfo](typeinfo.md)** - Fornece acesso (inseguro) às informações de tipo em tempo de execução do Nim.
- **[typetraits](typetraits.md)** - Procedimentos de reflexão em tempo de compilação para trabalhar com tipos.
- **[volatile](volatile.md)** - Código para gerar leituras e armazenamentos voláteis, úteis em programação de sistemas e embarcados.

### Algoritmos

- **[algorithm](algorithm.md)** - Algoritmos genéricos comuns como ordenação ou busca binária.
- **[enumutils](enumutils.md)** - Funcionalidade adicional para o tipo embutido `enum`.
- **[sequtils](sequtils.md)** - Operações para o tipo embutido `seq` que foram inspiradas por linguagens de programação funcional.
- **[setutils](setutils.md)** - Funcionalidade adicional para o tipo embutido `set`.

### Coleções

- **[critbits](critbits.md)** - Uma *crit bit tree* que é um contedor eficiente para um conjunto ordenado de strings, ou um mapeamento ordenado de strings.
- **[deques](deques.md)** - Implementação de uma fila de dupla extremidade. A implementação subjacente usa um `seq`.
- **[heapqueue](heapqueue.md)** - Implementação de uma estrutura de dados de heap binário que pode ser usada como fila de prioridade.
- **[intsets](intsets.md)** - Implementação eficiente de um conjunto de inteiros como um conjunto de bits esparso.
- **[lists](lists.md)** - Suporte a listas ligadas do Nim. Contém listas simples e duplamente ligadas e listas circulares ("rings").
- **[options](options.md)** - O tipo option encapsula um valor opcional.
- **[packedsets](packedsets.md)** - Implementação eficiente de um conjunto de ordinais como um conjunto de bits esparso.
- **[ropes](ropes.md)** - Um tipo de dado *rope*. Ropes podem representar strings muito longas de forma eficiente; em particular, a concatenação é feita em O(1) em vez de O(n).
- **[sets](sets.md)** - Suporte a conjunto hash do Nim.
- **[strtabs](strtabs.md)** - O módulo `strtabs` implementa uma tabela hash eficiente que é um mapeamento de strings para strings. Suporta modos sensível a maiúsculas/minúsculas, insensível a maiúsculas/minúsculas e insensível a estilo.
- **[tables](tables.md)** - Suporte a tabela hash do Nim. Contém tabelas, tabelas ordenadas e tabelas de contagem.

### Manipulação de Strings

- **[cstrutils](cstrutils.md)** - Utilitários para manipulação de `cstring`.
- **[editdistance](editdistance.md)** - Um algoritmo para calcular a distância de edição entre duas strings Unicode.
- **[encodings](encodings.md)** - Converte entre diferentes codificações de caracteres. No UNIX, isso usa a biblioteca `iconv`, no Windows a API do Windows.
- **[formatfloat](formatfloat.md)** - Formatação de floats como strings.
- **[objectdollar](objectdollar.md)** - Um operador genérico `$` para converter objetos para strings.
- **[punycode](punycode.md)** - Implementa uma representação de Unicode com o subconjunto limitado de caracteres ASCII.
- **[strbasics](strbasics.md)** - Algumas operações de string de alta performance.
- **[strformat](strformat.md)** - Interpolação/formatação de string padrão baseada em macros. Inspirado nas f-strings do Python.
  - **Nota**: se você precisa de templates, considere usar [Source Code Filters (SCF) do Nim](filters.html).
- **[strmisc](strmisc.md)** - Operações de manipulação de string incomuns que não se encaixam com as operações comuns usadas em `strutils`.
- **[strscans](strscans.md)** - Uma macro `scanf` para análise conveniente de mini-linguagens.
- **[strutils](strutils.md)** - Operações de manipulação de string comuns como mudar caixa de uma string, dividir uma string em substrings, buscar substrings, substituir substrings.
- **[unicode](unicode.md)** - Suporte para manipulação da codificação Unicode UTF-8.
- **[unidecode](unidecode.md)** - Fornece um único procedimento que faz transliterações de Unicode para ASCII. Baseado no módulo Unidecode do Python.
- **[widestrs](widestrs.md)** - Suporte do Nim para strings largas do C/C++.
- **[wordwrap](wordwrap.md)** - Um algoritmo para quebra de linhas de strings Unicode.

### Manipulação de Tempo

- **[monotimes](monotimes.md)** - O módulo `monotimes` implementa timestamps monotônicos.
- **[times](times.md)** - O módulo `times` contém suporte para trabalhar com tempo.

### Serviços Genéricos de Sistema Operacional

- **[appdirs](appdirs.md)** - Auxiliadores para determinar diretórios especiais usados por aplicativos.
- **[cmdline](cmdline.md)** - Facilidades do sistema para ler parâmetros de linha de comando.
- **[dirs](dirs.md)** - Manipulação de diretórios.
- **[distros](distros.md)** - Básicos para detecção de distribuição de SO ("distro") e do gerenciador de pacotes nativo do SO. Seu propósito principal é produzir saída para pacotes Nimble, mas também contém o enumeração **Distribution** amplamente usada que é útil para escrever código específico de plataforma. Veja [packaging](packaging.md) para dicas sobre distribuir Nim usando pacotes de SO.
- **[dynlib](dynlib.md)** - Acessando símbolos de bibliotecas compartilhadas.
- **[envvars](envvars.md)** - Manipulação de variáveis de ambiente.
- **[exitprocs](exitprocs.md)** - Adicionando hooks à saída do programa.
- **[files](files.md)** - Manipulação de arquivos.
- **[memfiles](memfiles.md)** - Suporte para arquivos mapeados em memória (mmap do Posix) em diferentes sistemas operacionais.
- **[os](os.md)** - Facilidades básicas do sistema operacional como recuperar variáveis de ambiente, ler argumentos de linha de comando, trabalhar com diretórios, executar comandos de shell, etc.
- **[oserrors](oserrors.md)** - Relatório de erros do sistema operacional.
- **[osproc](osproc.md)** - Módulo para comunicação de processos além de `os.execShellCmd`.
- **[paths](paths.md)** - Manipulação de caminhos (paths).
- **[reservedmem](reservedmem.md)** - Utilitários para reservar porções do espaço de endereços de um programa sem consumir memória física.
- **[streams](streams.md)** - Uma interface de stream e duas implementações dela: `FileStream` e `StringStream` que implementam a interface de stream para objetos de arquivo do Nim (`File`) e strings. Outros módulos podem fornecer outras implementações para esta interface de stream padrão.
- **[symlinks](symlinks.md)** - Manipulação de symlinks.
- **[syncio](syncio.md)** - Várias operações de E/S sincronizadas.
- **[terminal](terminal.md)** - Um módulo para controlar a saída do terminal (também chamado de *console*).
- **[tempfiles](tempfiles.md)** - Algumas utilitários para gerar nomes de caminho temporários e criar arquivos e diretórios temporários.

### Bibliotecas Matemáticas

- **[complex](complex.md)** - Números complexos e operações matemáticas relevantes.
- **[fenv](fenv.md)** - Ambiente de ponto flutuante. Manipulação de arredondamento de ponto flutuante e exceções (overflow, divisão por zero, etc.).
- **[lenientops](lenientops.md)** - Operadores binários para expressões mistas de inteiro/float para conveniência.
- **[math](math.md)** - Operações matemáticas como cosseno, raiz quadrada.
- **[random](random.md)** - Gerador de números aleatórios rápido e pequeno.
- **[rationals](rationals.md)** - Números racionais e operações matemáticas relevantes.
- **[stats](stats.md)** - Análise estatística.
- **[sysrand](sysrand.md)** - Gerador de números pseudoaleatórios criptograficamente seguros.

### Protocolos de Internet

- **[async](async.md)** - Exporta `asyncmacro` e `asyncfutures` para backends nativos, e `asyncjs` no backend JS.
- **[asyncdispatch](asyncdispatch.md)** - Um despachante assíncrono para operações de E/S.
- **[asyncfile](asyncfile.md)** - Leitura e escrita de arquivo assíncrona usando `asyncdispatch`.
- **[asyncftpclient](asyncftpclient.md)** - Um cliente FTP assíncrono usando o módulo `asyncnet`.
- **[asynchttpserver](asynchttpserver.md)** - Um servidor HTTP assíncrono usando o módulo `asyncnet`.
- **[asyncmacro](asyncmacro.md)** - Macros `async` e `multisync` para `asyncdispatch`.
- **[asyncnet](asyncnet.md)** - Sockets assíncronos baseados no módulo `asyncdispatch`.
- **[asyncstreams](asyncstreams.md)** - `FutureStream` - um futuro que atua como uma fila.
- **[cgi](cgi.md)** - Auxiliadores para aplicativos CGI.
- **[cookies](cookies.md)** - Procedimentos auxiliares para analisar e gerar cookies.
- **[httpclient](httpclient.md)** - Um cliente HTTP simples com suporte para recuperação síncrona e assíncrona de páginas web.
- **[mimetypes](mimetypes.md)** - Um banco de dados de mimetypes.
- **[nativesockets](nativesockets.md)** - Uma API de sockets de baixo nível.
- **[net](net.md)** - Uma API de sockets de alto nível.
- **[selectors](selectors.md)** - Uma API de seletor com backends específicos para cada SO. Primitivas de SO suportadas: `epoll`, `kqueue`, `poll`, e `select` no Windows.
- **[smtp](smtp.md)** - Um cliente SMTP simples com suporte para operação síncrona e assíncrona.
- **[socketstreams](socketstreams.md)** - Uma implementação da interface de streams para sockets.
- **[uri](uri.md)** - Funções para trabalhar com URIs e URLs.

### Threading

- **[isolation](isolation.md)** - O tipo `Isolated[T]` para construção segura de subgrafos isolados que podem ser passados eficientemente para diferentes canais e threads.
- **[tasks](tasks.md)** - Primitivos básicos para criar programas paralelos.
- **[threadpool](threadpool.md)** - Implementa o [spawn](../manual/experimental.md#parallel-amp-spawn) do Nim.
- **[typedthreads](typedthreads.md)** - Suporte básico de threads do Nim.

### Parseres

- **[htmlparser](htmlparser.md)** - Parser de documentos HTML que cria uma representação de árvore XML.
- **[json](json.md)** - Parser JSON de alta performance.
- **[lexbase](lexbase.md)** - Um módulo de baixo nível que implementa um esquema de buffer extremamente eficiente para lexers e parseres. Isso é usado pelos diversos módulos de análise.
- **[parsecfg](parsecfg.md)** - O módulo `parsecfg` implementa um parser de arquivo de configuração de alta performance. A sintaxe do arquivo de configuração é semelhante ao formato `.ini` do Windows, mas muito mais poderosa, pois não é um parser baseado em linhas. Literais de string, literais de string crua e literais de string com três aspas são suportados como na linguagem de programação Nim.
- **[parsecsv](parsecsv.md)** - O módulo `parsecsv` implementa um parser CSV simples de alta performance.
- **[parsejson](parsejson.md)** - Um parser JSON. É usado e exportado pelo módulo `json`, mas também pode ser usado por si só.
- **[parseopt](parseopt.md)** - O módulo `parseopt` implementa um parser de opções de linha de comando.
- **[parsesql](parsesql.md)** - O módulo `parsesql` implementa um parser SQL simples de alta performance.
- **[parseutils](parseutils.md)** - Auxiliadores para analisar tokens, números, identificadores, etc.
- **[parsexml](parsexml.md)** - O módulo `parsexml` implementa um parser XML/HTML simples de alta performance. A única codificação suportada é UTF-8. O parser foi projetado para ser um pouco corretor de erros, de forma que até mesmo "HTML selvagem" encontrado na web pode ser analisado com ele.
- **[pegs](pegs.md)** - Procedimentos e operadores para manipular PEGs.

### Docutils

- **[highlite](../packages/docutils/highlite.md)** - Destacador de código-fonte para linguagens de programação ou marcação. Atualmente, apenas algumas linguagens são suportadas, outras linguagens podem ser adicionadas. A interface suporta uma linguagem aninhada em outra.
- **[rst](../packages/docutils/rst.md)** - Um parser de reStructuredText. Um subconjunto grande é implementado. Alguns recursos da sintaxe wiki markdown também são suportados.
- **[rstast](../packages/docutils/rstast.md)** - Um AST para o parser de reStructuredText.
- **[rstgen](../packages/docutils/rstgen.md)** - Um gerador de HTML/Latex de reStructuredText.

### Processamento de XML

- **[xmltree](xmltree.md)** - Uma árvore XML simples. Mais eficiente e simples que o DOM. Também contém uma macro para geração de código XML/HTML.
- **[xmlparser](xmlparser.md)** - Parser de documentos XML que cria uma representação de árvore XML.

### Geradores

- **[genasts](genasts.md)** - Geração de AST usando variáveis capturadas para macros.
- **[htmlgen](htmlgen.md)** - Um gerador de código XML e HTML simples. Cada tag HTML comumente usada tem uma macro correspondente que gera uma string com sua representação HTML.

### Hashing

- **[base64](base64.md)** - Um codificador e decodificador Base64.
- **[hashes](hashes.md)** - Computações eficientes de valores hash para diversos tipos Nim.
- **[md5](md5.md)** - O algoritmo de checksum MD5.
- **[oids](oids.md)** - Um OID é um ID global que consiste em um timestamp, um contador único e um valor aleatório. Esta combinação deve bastar para produzir um ID único distribuído globalmente.
- **[sha1](sha1.md)** - O algoritmo de checksum SHA-1.

### Serialização

- **[jsonutils](jsonutils.md)** - (De)serialização acoplável para tipos arbitrários usando JSON.
- **[marshal](marshal.md)** - Contém procedimentos para serialização e deserialização de estruturas de dados arbitrários do Nim.

### Miscelânea

- **[assertions](assertions.md)** - Manipulação de asserções.
- **[browsers](browsers.md)** - Procedimentos para abrir URLs com o navegador padrão do usuário.
- **[colors](colors.md)** - Manipulação de cores.
- **[coro](coro.md)** - Corrotinas experimentais em Nim.
- **[decls](decls.md)** - Açúcar sintático para algumas declarações.
- **[enumerate](enumerate.md)** - Açúcar sintático `enumerate` baseado no sistema de macros do Nim.
- **[importutils](importutils.md)** - Utilitários relacionados a import e resolução de símbolos.
- **[logging](logging.md)** - Um logger simples.
- **[segfaults](segfaults.md)** - Transforma violações de acesso ou falhas de segmentação em uma exceção `NilAccessDefect`.
- **[sugar](sugar.md)** - Açúcar sintático agradável baseado no sistema de macros do Nim.
- **[unittest](unittest.md)** - Implementa um DSL de testes de unidade.
- **[varints](varints.md)** - Decodifica inteiros de comprimento variável que são compatíveis com SQLite.
- **[with](with.md)** - A macro `with` para encadeamento fácil de funções.
- **[wrapnils](wrapnils.md)** - Permite avaliar expressões com segurança contra deferenciações nil.

### Módulos para Backend JavaScript

- **[asyncjs](asyncjs.md)** - Tipos e macros para escrever procedimentos assíncronos em JavaScript.
- **[dom](dom.md)** - Declaração do Document Object Model para o backend JS.
- **[jsbigints](jsbigints.md)** - Inteiros de precisão arbitrária.
- **[jsconsole](jsconsole.md)** - Wrapper para o objeto `console`.
- **[jscore](jscore.md)** - O wrapper das funções core do JavaScript. Para a maioria dos propósitos, você deve usar os módulos stdlib `math`, `json`, e `times` em vez deste módulo.
- **[jsfetch](jsfetch.md)** - Wrapper para `fetch`.
- **[jsffi](jsffi.md)** - Tipos e macros para interação mais fácil com JavaScript.
- **[jsre](jsre.md)** - Expressões Regulares para o alvo JavaScript.

---

## Bibliotecas Impuras

### Expressões Regulares

- **[re](re.md)** - Procedimentos e operadores para manipular expressões regulares. A implementação atual usa PCRE.
- **[nre](nre.md)** - Muitas funções auxiliares para manipular expressões regulares. A implementação atual usa PCRE.

### Suporte a Banco de Dados

- **[db_mysql](db_mysql.md)** - Um wrapper de banco de dados MySQL de alto nível. A mesma interface é implementada para outros bancos de dados também.
- **[db_odbc](db_odbc.md)** - Um wrapper de banco de dados ODBC de alto nível. A mesma interface é implementada para outros bancos de dados também.
- **[db_postgres](db_postgres.md)** - Um wrapper de banco de dados PostgreSQL de alto nível. A mesma interface é implementada para outros bancos de dados também.
- **[db_sqlite](db_sqlite.md)** - Um wrapper de banco de dados SQLite de alto nível. A mesma interface é implementada para outros bancos de dados também.

### Serviços Genéricos de Sistema Operacional

- **[rdstdin](rdstdin.md)** - Código para ler entrada do usuário de stdin.

---

## Wrappers

> O HTML gerado para alguns desses wrappers é tão grande que não está contido na distribuição. Você pode então encontrá-los no site.

### Específico do Windows

- **[winlean](winlean.md)** - Wrapper para um pequeno subconjunto da API Win32.
- **[registry](registry.md)** - Suporte ao registro do Windows.

### Específico do UNIX

- **[posix](posix.md)** - Wrapper para o padrão POSIX.
- **[posix_utils](posix_utils.md)** - Contém auxiliadores para o padrão POSIX ou especializados para Linux e BSDs.

### Expressões Regulares

- **[pcre](pcre.md)** - Wrapper para a biblioteca PCRE.

### Suporte a Banco de Dados

- **[mysql](mysql.md)** - Wrapper para a API do MySQL.
- **[odbcsql](odbcsql.md)** - interface para o driver ODBC.
- **[postgres](postgres.md)** - Wrapper para a API do PostgreSQL.
- **[sqlite3](sqlite3.md)** - Wrapper para a API do SQLite 3.

### Programação de Rede

- **[openssl](openssl.md)** - Wrapper para OpenSSL.

---

## Links Relacionados

- [Manual da Linguagem](../manual/README.md) - Documentação completa da linguagem Nim
- [Guia de Estilo](../style_guide/README.md) - Convenções de código da biblioteca padrão
- [Ferramentas](../tools/README.md) - Ferramentas disponíveis com Nim
- [Tutoriais](../tutorials/README.md) - Tutoriais e exemplos práticos
- [Gerenciamento de Memória](../memory/README.md) - Como Nim gerencia memória

---

**Fonte Original**: https://nim-lang.org/docs/lib.html  
**Versão Nim**: 2.2.8  
**Data da Conversão**: 2025-03-16

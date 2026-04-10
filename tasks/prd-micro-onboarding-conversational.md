# PRD: Micro-Onboarding Conversacional do Usuário

## Objetivo

Substituir a coleta rígida do perfil do usuário por um micro-onboarding conversacional, curto e natural, que descubra:

- quem a pessoa é, se ela quiser dizer
- como gostaria de ser chamada
- como gostaria de ser tratada pelo agente
- opcionalmente idioma e fuso horário

## Motivação

O bootstrap atual fica burocrático demais depois que o agente escolhe o próprio nome. Queremos que a experiência passe a soar como conversa, não formulário.

## Escopo deste corte

- manter o bootstrap da personalidade do agente
- manter a escolha do nome do agente
- trocar o onboarding do usuário por conversa livre curta
- extrair perfil com um bloco estruturado `USER_PROFILE_READY`
- persistir o resultado em `USER.md`

## Fora de escopo neste corte

- editar o perfil do usuário por comandos específicos
- confirmação/edição campo a campo
- painel visual de perfil
- política refinada para campos opcionais

## Critérios de aceite

- após o nome do agente, o bot pergunta de forma aberta sobre o usuário
- o usuário pode responder em texto livre
- o modelo pode fazer uma breve pergunta de seguimento antes de finalizar
- quando houver dados suficientes, o onboarding fecha sem exigir timezone/language
- `USER.md` persiste pelo menos nome/preferred name e, quando houver, idioma/fuso/tratamento/about
- o fluxo continua para conversa normal ao final

## Próximos passos

1. Usar `treatment` e `about` também no prompt de sistema.
2. Permitir revisão posterior do perfil do usuário.
3. Expor o perfil em `/whoami` e `/about`.

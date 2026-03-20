import unittest
import donkey/domain/personality

suite "PersonalityTraits — buildPersonalityPrompt":

  test "nome aparece no prompt quando definido":
    let traits = PersonalityTraits(energy: "reservado", tone: "formal",
                                   length: "conciso", initiative: "reativo")
    let p = buildPersonalityPrompt(traits, "Aldous")
    check p.contains("Aldous")

  test "sem nome omite linha de nome":
    let traits = PersonalityTraits(energy: "neutro", tone: "neutro",
                                   length: "moderado", initiative: "moderado")
    let p = buildPersonalityPrompt(traits, "")
    check not p.contains("Your name")
    check not p.contains("name is")

  test "energia reservada gera instrução de contenção":
    let traits = PersonalityTraits(energy: "reservado", tone: "neutro",
                                   length: "moderado", initiative: "moderado")
    let p = buildPersonalityPrompt(traits, "")
    check p.contains("reservado") or p.contains("reserved") or p.contains("enthusiasm")

  test "iniciativa proativa menciona antecipar":
    let traits = PersonalityTraits(energy: "neutro", tone: "casual",
                                   length: "conciso", initiative: "proativo")
    let p = buildPersonalityPrompt(traits, "")
    check p.contains("proativo") or p.contains("proactive") or p.contains("anticipat")

  test "todas as dimensões estão representadas no prompt":
    let traits = PersonalityTraits(energy: "entusiasmado", tone: "casual",
                                   length: "detalhado", initiative: "proativo")
    let p = buildPersonalityPrompt(traits, "Nova")
    check p.contains("Nova")
    check p.len > 50

suite "parseNameOptions":

  test "extrai cinco nomes de resposta bem formatada":
    let resp = "Aldous\nVance\nSeren\nQuill\nEmeric"
    let names = parseNameOptions(resp)
    check names.len == 5
    check "Aldous" in names
    check "Emeric" in names

  test "ignora linhas em branco e lixo":
    let resp = "\nAldous\n\nVance\n  \nSeren\nQuill\nEmeric\n"
    let names = parseNameOptions(resp)
    check names.len == 5

  test "retorna o que houver se menos de cinco":
    let resp = "Dash\nNova"
    let names = parseNameOptions(resp)
    check names.len == 2

  test "resposta vazia retorna seq vazia":
    check parseNameOptions("").len == 0

suite "parseIdentityReady":

  test "extrai traits de bloco IDENTITY_READY":
    let text = """Ok, entendi quem você quer que eu seja.

IDENTITY_READY:
energy: reservado
tone: casual
length: conciso
initiative: reativo

Quer sugestões de nome?"""
    let r = parseIdentityReady(text)
    check r.isSome
    let t = r.get()
    check t.energy    == "reservado"
    check t.tone      == "casual"
    check t.length    == "conciso"
    check t.initiative == "reativo"

  test "retorna none quando bloco ausente":
    check parseIdentityReady("Resposta normal sem marcador.").isNone

  test "stripIdentityReady remove o bloco do texto visível":
    let text = "Pronto.\n\nIDENTITY_READY:\nenergy: neutro\ntone: formal\nlength: moderado\ninitiative: moderado\n\nVamos ao nome?"
    let visible = stripIdentityReady(text)
    check not visible.contains("IDENTITY_READY")
    check visible.contains("Pronto.")
    check visible.contains("Vamos ao nome?")

suite "guidedDimensionMsg":

  test "dkEnergy retorna botões de energia":
    let (txt, kb) = guidedDimensionMsg(dkEnergy)
    check txt.len > 0
    check kb.len > 0
    check kb[0].len == 3
    let labels = kb[0].mapIt(it[0])
    check labels.anyIt(it.toLowerAscii.contains("reserv"))

  test "todas as dimensões têm exatamente 3 botões":
    for dk in DimensionKind:
      let (_, kb) = guidedDimensionMsg(dk)
      check kb[0].len == 3

  test "callback_data segue padrão personality:dim:valor":
    for dk in DimensionKind:
      let (_, kb) = guidedDimensionMsg(dk)
      for (_, cb) in kb[0]:
        check cb.startsWith("personality:")
        check cb.count(':') == 2

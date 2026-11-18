# Review — `tasks/prd-providers.md` (V4 priority 4)

**Verdict: BLOCK.** The dependency lacks the "adapter compatível" the stories rely on, and
US-001's vision criterion contradicts the Hermes doc it cites.
## Blockers
1. **No compat adapter, no header consumer.** `rg newCompatAdapter` is empty; `openai.nim`
   hardcodes `Content-Type`/`Authorization` and never reads `profile.extraHeaders` (only
   `openrouter.nim` does). NVIDIA's billing and Fireworks' attribution headers have nowhere to
   land; transport US-001/002/006/008/009 create no generic `ProviderPort`. Add a transport
   follow-up (`newCompatAdapter` + headers + caps seam) or drop the "profile only" claim.
2. **NVIDIA vision is backwards.** `providers.md` says Nemotron 3.5 Super VL "supports text
   and image inputs, reasoning, and tool calls". US-001 sets `supportsImages=false` "sem
   evidência de `image_url`", which strips images from a vision model; the golden would
   enshrine it. Set `true`, keep the image, delete the "no evidence → false" rule.
## Required fixes
3. **Fireworks default is not a Hermes fact.** No curated list and no `default_model`:
   `kimi-k2p6` is `fallback_models[0]` plus a docs example; `default_aux_model` is `glm-5p2`.
   Say "Donkey's chosen default from the fallback list".
4. **Fireworks reasoning cannot be disabled.** Hermes maps `enabled=false` to
   `reasoning_effort: "none"`; the PRD emits nothing, so thinking stays on and
   `includeReasoningField=false` is moot. Emit `"none"` or declare the flag ignored.
   `include_reasoning` is a Donkey quirk, not a Hermes field — stop citing it as provider behavior.
5. **OAuth framing stale; V4 deviation unrecorded.** Nous device-code is concrete and needs
   no user secret (public `hermes-cli`); the blocker really is client identity. Correct V4
   §3.2's "nenhum provider-alvo expõe o fluxo". Only `nous` has `oauth_device_code`;
   `_RESYNC_SOURCE` (928-930) is resync, not the single-use lock (~1480), though it lists
   Codex/xAI too. V4 §6 asked for Copilot/Codex OAuth + Bedrock/Vertex/Azure; neither is
   delivered, so the 41-point gap stays and that needs maintainer sign-off, not a commit note.
6. **US-004 routing is inert and contradicts FR-3.** Context `0` and (after fix 2) at most
   one image model means the three never qualify for image/long-context. Unknown
   `supportsTools=true` is a promise, not "conservative"; FR-3 says absence never becomes a
   promise. Split 4a (pure `modelLimits` + `sourceRef`) from 4b (catalog/routing with a
   synthetic provider); forbid iterating `ProviderCatalog.entries` (a `Table`).
7. **Ownership incomplete/contradictory.** US-001..003 touch `smart_routing.nim`
   (`ProviderAvailability`, `isAvailable`) and `session_bootstrap.nim`
   (`detectProviderAvailability`, `availableProviderNames`), yet §4.2 gives `smart_routing.nim`
   only to US-004 and omits `session_bootstrap.nim` — both single-writer files for ferramentas
   (`requestApproxChars`) and multiagente.
8. **"No existing test edited" contradicts the criteria.** One row in
   `tests/domain/providers/t_compat_conformance.nim` is an edit; transport FR-6 intends that
   additive row. Declare the exception ("one new row, nothing changed").
9. **Hidden propagation and gates.** After transport US-009, `doctor`, `setup_wizard`, TUI
   and the `src/donkey.nim` cost list gain three providers for free — state and test it.
   `ProviderCaps` has no vision field; only `maxContextTokens` can flow. `parseOpenAISseLine`
   ignores `delta.reasoning`, and `streamFn != nil` only proves a stream exists: add an SSE
   reasoning case or scope it out, so NVIDIA's `reasoning_content` promise is not request-only.
10. **Missing non-goals:** live `/models` enrichment, models.dev fetch, `qwen-oauth`/
    `minimax-oauth`, any `ProviderCaps` shape change, and a `baseUrlEnv` consumer.
## Verified / keep
- Real providers: endpoints, env, `openai_chat` and quirks (Alibaba `compatible-mode`, NVIDIA
  tool `name` strip, Fireworks rejecting `extra_content`/nested reasoning) check out; no new
  wire protocol — only the missing adapter/header hook. OAuth is correctly a blocker; §6.1
  unlock conditions, gates and TDD/Result/pure-domain rules copy the transport PRD faithfully.
## Story order
0. Transport follow-up: generic compat adapter + header hook + caps seam (blocker 1).
1. US-004a `modelLimits` (pure; parallel to 2-4). 2. US-001 NVIDIA (`supportsImages=true`).
3. US-002 Alibaba. 4. US-003 Fireworks (reasoning). 5. US-004b catalog+routing. 6. US-005 docs.
## Still unverified — keep in §11, do not assert
- `reasoning_content` shape on NVIDIA/Alibaba responses; vision on `qwen3.8-max`.
- Whether `X-BILLING-INVOKE-ORIGIN: Donkey` is accepted outside `build.nvidia.com`.

# Re-review — `tasks/prd-providers.md` (r2, read-only)

**Verdict: PASS WITH FIXES.** BLOCK items are closed: US-001 creates the real `CompatAdapter`
with NVIDIA as the slice; vision, Fireworks default/reasoning and OAuth deferral match evidence;
US-004/005 are split. Five fixes remain.

## Verified (no fix needed)
1. The adapter is genuinely missing: `openai.nim` hardcodes `Authorization`/`Content-Type` and
   never reads `profile.extraHeaders`; only `openrouter.nim:190,216` consumes it. So
   `requestHeaders`/`requestUrl`/`complete` add real behavior. `profileFn: proc(): CompatProfile
   {.gcsafe, nimcall.}` is coherent — `nimcall` cannot capture, so no JsonNode crosses a thread,
   and rebuilding it inside `makeStreamFn` mirrors `openrouter.profileFor()` (`:208-216`).
   `parseResponseFrom` (`openai_pure:228`) and exported `parseOpenAISseLine` (`openai.nim:54`,
   reads only `delta.content`) exist, so deferring `delta.reasoning` to §11 is accurate.
2. NVIDIA `supportsImages=true`, image data URL in the golden and `providers.md:518` check out;
   `16384` is `nvidia/__init__.py:31` as cited.
3. Fireworks: `fallback_models[0]=kimi-k2p6`, `default_aux_model=glm-5p2` and
   `reasoning_effort:"none"` (`fireworks/__init__.py:24`) are attributed correctly; the
   `include_reasoning` contradiction is gone (`includeReasoningField`, `openai_pure.nim:71,208`).
4. OAuth is correctly deferred with the client-identity record (`providers.py:31`,
   `auth_constants.py:60`) and no inert story; ownership and the conformance-row exception hold.

## Remaining fixes
5. **Propagation is false for `setup_wizard`.** It still has `const Providers` (13 ids,
   `setup_wizard.nim:116-130`) that `setupProviderIds` reads, so a new descriptor never appears.
   `routeCostProviderIds` (`src/donkey.nim:432`) is unexported, so the surface test cannot assert
   the cost list. Drop `setup_wizard` from the "sem lista própria" claim (a transport-US-009
   residue: escalate to its owner or stop per "pare e escale") and prove cost by `rg` (like US-006).
6. **US-005 call sites unspecified.** State where `appendCapabilitySelections` runs (image branch
   `hasImage`; tools branch `hasTools`; long context `minContextWindow`) and that NVIDIA qualifies
   through `mcImage` derived from `modelLimits`. Otherwise the synthetic `contextWindow=200_000`
   test proves only the helper: the real long-context branch (`smart_routing.nim:573`) never reads
   `contextWindow`. Don't reuse `LongContextChars` (60_000 **chars**, `:19`) as a token threshold.
7. **Conformance row under-specified** (tautology risk): list expected
   `toolResultName`/`toolChoice`/`emptyContent`/`streamOptions`/`imageWithToolCalls` for the three,
   or say "inherits OpenAI defaults except `toolResultName=false` (nvidia)". "Uma linha aditiva"
   is a multi-line row plus an import.
8. **SSE claim untested.** §10 promises "SSE de conteúdo coberto" but stories only check
   `streamFn != nil`. Add a case feeding a `data:` line through `makeStreamFn` asserting the token,
   or delete the metric.
9. **Small drifts:** `supportsImages` lives in the profile and in `modelLimits` — assert equality
   (or derive one from the other); pin Fireworks' `HTTP-Referer` value (unnamed today), so the
   header/golden test is deterministic.

Live `X-BILLING-INVOKE-ORIGIN` acceptance and `reasoning_content` shape correctly stay in §11.

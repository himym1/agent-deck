# Agent Deck Model Thinking Audit

Date: 2026-06-17

## Scope

This document updates the model thinking-level guidance after checking official provider docs and the non-secret shape of `~/.pi/agent/models.json`.

Secrets were not read or printed. The inspected local fields were limited to provider/model IDs, `reasoning`, and `thinkingLevelMap`.

## Important Distinction

Agent Deck displays Pi thinking levels such as `off`, `low`, `medium`, `high`, and `xhigh`.

Provider APIs do not all use the same vocabulary. A Pi level can map to a different provider value, for example `xhigh -> max`. Do not assume the visible Agent Deck label is also the provider API value.

Agent Deck should prefer `~/.pi/agent/models.json` over the bundled `pi-ai` registry when resolving exact thinking levels. Otherwise provider/model IDs that exist in both places, such as `opencode/glm-5`, can show built-in levels instead of the user-configured map.

## Official Facts Checked

- Anthropic Claude effort docs: `effort` controls token/thinking depth; Claude Opus 4.8 and 4.7 support `low`, `medium`, `high`, `xhigh`, and `max`; Claude Opus 4.6 and Sonnet 4.6 support `low`, `medium`, `high`, and `max` in the cited guidance, with adaptive thinking recommended.
- DeepSeek thinking-mode docs: thinking effort accepts `high` and `max`; compatibility maps `low` and `medium` to `high`, and `xhigh` to `max`.
- Z.ai GLM core-parameter docs: `thinking` is supported by `GLM-4.5+`, but `reasoning_effort` is supported only by `GLM-5.2+`; allowed `reasoning_effort` values include `max`, `xhigh`, `high`, `medium`, `low`, `minimal`, and `none`, with compatibility mappings.

## Recommended Maps

| Model | Local map currently seen | Official/API status | Recommended `thinkingLevelMap` |
|---|---|---|---|
| `claude-opus-4-8` | `low`, `medium`, `high`, `xhigh` | Official effort levels include `low`, `medium`, `high`, `xhigh`, `max`. Adaptive thinking is the supported thinking mode. | Keep `low -> low`, `medium -> medium`, `high -> high`, `xhigh -> xhigh`. If you want max effort, Agent Deck has no separate `max` label, so choose whether to map `xhigh -> max` instead. |
| `claude-opus-4-7` | `low`, `medium`, `high`, `xhigh` | Same as Opus 4.8: official effort levels include `low`, `medium`, `high`, `xhigh`, `max`. | Keep current map, or intentionally map `xhigh -> max` if highest UI level should mean maximum effort. |
| `claude-opus-4-6` | `low`, `medium`, `high`, `xhigh` | Official guidance lists `low`, `medium`, `high`, `max`; `xhigh` is not documented for this model. | Change top-level mapping to `xhigh -> max`, or remove `xhigh` from the visible levels if the adapter cannot translate it. |
| `claude-sonnet-4-6` | `low`, `medium`, `high`, `xhigh` | Official guidance lists `low`, `medium`, `high`, `max`; `xhigh` is not documented for this model. | Change top-level mapping to `xhigh -> max`, or remove `xhigh` from the visible levels if the adapter cannot translate it. |
| `deepseek-v4-pro` / `deepseek-v4-flash` | `off -> none`, `high -> high`, `xhigh -> max` | Correct. Official effort values are `high` and `max`; `low/medium` are only compatibility aliases to `high`; `xhigh` is a compatibility alias to `max`. | Keep `off -> none`, `high -> high`, `xhigh -> max`; keep `minimal`, `low`, and `medium` as `null` to avoid redundant UI choices. |
| `glm-5.2` | `off -> none`, `high -> high`, `xhigh -> max` | Correct and conservative. Official `reasoning_effort` exists for `GLM-5.2+`; `none/minimal` skip thinking, `low/medium` map to `high`, and `xhigh` maps to `max`. | Keep `off -> none`, `high -> high`, `xhigh -> max`; keep `minimal`, `low`, and `medium` as `null` unless you intentionally want compatibility aliases visible. |
| `glm-5` / `glm-5.1` | `off -> none`, `high -> high`, `xhigh -> max` | Not officially confirmed as `reasoning_effort` models by the checked Z.ai docs. The docs only confirm `reasoning_effort` for `GLM-5.2+`. | Do not mark this as officially verified. Keep the conservative map only if the OpenCode/provider adapter confirms it accepts these values. |

## Direct Corrections From Previous Version

1. The earlier Claude summary was too broad. Claude must be split by version.
2. `claude-opus-4-6` and `claude-sonnet-4-6` should not use literal `xhigh` unless the adapter translates it. Prefer `xhigh -> max`.
3. DeepSeek V4 was correct as `off/high/xhigh(max)`.
4. GLM-5.2 was correct as `off/high/xhigh(max)` and intentionally hides redundant aliases.
5. GLM-5 and GLM-5.1 should be labeled provider-adapter-dependent, not officially verified.

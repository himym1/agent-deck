# File Locations Reference

This page lists the important paths Agent Deck scans or writes.

`PROJECT` means the selected project root.

## Pi and app data

| Purpose | Path |
|---|---|
| Pi global config | `~/.pi/agent/` |
| Pi global settings | `~/.pi/agent/settings.json` |
| Pi project settings | `PROJECT/.pi/settings.json` |
| Pi global env | `~/.pi/agent/.env` |
| Pi project env | `PROJECT/.pi/.env` |
| Agent Deck app data | `~/Library/Application Support/Agent Deck/` |
| Native subagent artifacts | `~/Library/Application Support/Agent Deck/Subagent Runs/<run-id>/` |

## Agents

| Scope | Path |
|---|---|
| App-bundled native builtins | app bundle `bundled-agents/` |
| Global catalog | `~/.pi/agent/agents/*.md` |
| Legacy global catalog | `~/.agents/*.md` |
| Library/catalog | `~/.pi/agent/agent-library/agents/*.md` |
| Project catalog | `PROJECT/.pi/agents/*.md` |
| Legacy project catalog | `PROJECT/.agents/*.md` |
| Assignment state | Agent Deck app settings/project preferences |
| Builtin overrides | `settings.json -> subagents.agentOverrides` |

## Skills

| Scope | Path |
|---|---|
| Global active | `~/.pi/agent/skills/<skill>/SKILL.md` or root `.md` |
| Legacy global | recursive `~/.agents/skills/**/SKILL.md`; root `.md` files are ignored |
| Project active | `PROJECT/.pi/skills/<skill>/SKILL.md` or root `.md` |
| Legacy project | recursive `PROJECT/.agents/skills/**/SKILL.md` from cwd/ancestors; root `.md` files are ignored |
| Package/settings | package `pi.skills` entries, including direct `SKILL.md` roots and simple globs like `./cs-*`, or conventional package `skills/` folders; plus `settings.json -> skills` |

## Prompt templates

| Scope | Path |
|---|---|
| Global catalog | `~/.pi/agent/prompts/*.md` |
| Library/catalog | `~/.pi/agent/prompt-library/*.md` |
| Project catalog | `PROJECT/.pi/prompts/*.md` |
| Package/settings catalog | package `pi.prompts` entries, including simple globs, or conventional package prompt folders; plus `settings.json -> prompts` |
| Assignment state | Agent Deck app settings/project preferences; parent launch uses explicit `--prompt-template` arguments |

## Extensions and packages

| Purpose | Path / setting |
|---|---|
| Global auto extensions | `~/.pi/agent/extensions/*.ts`, `~/.pi/agent/extensions/*.js`, `~/.pi/agent/extensions/*/index.ts`, `~/.pi/agent/extensions/*/index.js` |
| Project auto extensions | `PROJECT/.pi/extensions/*.ts`, `PROJECT/.pi/extensions/*.js`, `PROJECT/.pi/extensions/*/index.ts`, `PROJECT/.pi/extensions/*/index.js` |
| Settings extensions | `settings.json -> extensions` |
| Packages | `settings.json -> packages`; package directories resolve from Pi-managed npm/git package stores, project package stores, and common Node global locations |
| Native bridge extensions | `~/Library/Application Support/Agent Deck/Native Subagent Extensions/managed-subagent-bridge.ts` and `contact-supervisor-bridge.ts` |

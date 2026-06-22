# Chains Retirement Plan

## Decision

The unreleased user-facing Chains concept should be retired in favor of Loops.

Loops cover the useful parts of chains while adding iteration, checks, stop conditions, artifacts, and visible write policies.

## Scope of retirement

Remove or update:

- product docs that list Chains as a managed resource,
- scanner claims that chains are discovered,
- persistence references to ChainPersistence if any still exist,
- UI references to Chains if any exist,
- tests that assert user-facing chain behavior.

Do not remove unrelated internal sequencing concepts if they are used by native subagent orchestration and not exposed as Chains.

## Inventory command

Use a focused search before editing:

```bash
rg -n "Chain|chain|chains|\.chain\.md|ChainPersistence|ChainRecord" .
```

## Current known references

At the time this plan was written, chain references were visible in:

- architecture docs listing chain scanning/persistence,
- testing docs mentioning chain/parallel status updates,
- PiScanner exclusions for `.chain.md` files.

## `.chain.md` handling

Open decision: old `.chain.md` files can be handled in one of three ways:

1. ignore silently,
2. show a diagnostic warning for one release,
3. offer migration to loop definitions.

Recommendation: show a diagnostic warning for one release if users could plausibly have local unreleased chain files. Otherwise remove the special case and document that Chains never shipped.

## Migration path

If migration is needed, map:

- chain name → loop name,
- chain steps → Agent Pipeline structure,
- chain description → loop description,
- chain commands/checks → loop check policy where possible.

Do not over-invest in migration unless real user data exists.

# AGENTS

## Decision quality rules

- Prefer primary sources over commentary. Source hierarchy: Apple docs and API docs first, Apple release notes and Apple forums second, official project docs third, blogs and forums last.
- Separate sourced facts from inferred conclusions. Do not present an inference as if a source proved it.
- Cite the exact claim being relied on when making platform or permission decisions.
- If sources are mixed, outdated, or contradictory, say so explicitly in the working notes and keep the implementation conservative.
- Distinguish direct observations from the repo or verified app behavior from higher-level abstractions built on top of them.
- When recommending a change, name the concrete defect being solved. “There is another valid pattern” is not, by itself, a defect.

## Reasoning discipline

- Bind recommendations to the concrete local shape first. Before proposing a change, restate the current architecture, UI surface, or behavior as shown in the code or verified in the app.
- Do not infer a problem from the mere existence of an alternative. Another valid pattern is neutral unless the current choice conflicts with requirements, primary-source guidance, observed behavior, or causes a concrete usability cost.
- Preserve the default prior that the current visible product shape may already be correct. Require positive evidence before recommending a structural change.
- For every nontrivial recommendation, identify the evidence that would falsify it. If that evidence is already present, drop the recommendation instead of softening it.
- When local artifacts or verified behavior contradict an earlier claim, recompute from those artifacts instead of defending continuity with the earlier claim.

## Platform behavior and permissions

- Treat macOS privacy, security, sandbox, input, and Accessibility behavior as high-risk areas.
- Do not change onboarding, readiness gates, permission copy, or permission requirements based only on secondary web research.
- Preserve existing user-visible permission flows unless the new behavior is supported by strong primary-source evidence or verified locally.
- When confidence is moderate rather than high, prefer backend-only changes that keep the current UX intact.

## Validation standard

- Do not write or mark an ADR as accepted until the core platform assumptions behind it are either backed by strong primary sources or verified in the app.
- For OS-behavior edge cases, use the narrowest decisive validation possible rather than broad speculative refactors.
- Treat real observed app behavior as higher priority than blog posts, forum answers, or generalized prior knowledge.
- Treat local code structure and verified app behavior as falsification evidence for speculative recommendations.
- If a recommendation is invalidated by the observed implementation, remove it immediately rather than reframing it as a weaker suggestion.

## Change scope discipline

- Do not bundle architecture changes with product-flow rewrites unless the user asked for both.
- When replacing an internal backend, keep the existing fallback behavior and onboarding semantics by default.
- If a technical decision would force a product behavior change, stop and call that out explicitly before changing the UX.
- Do not critique or redesign an existing user-visible surface unless you can first explain why leaving the current shape alone would be wrong, risky, or materially costly.

## ADR rules

- ADRs must record validated decisions, not freeze an early theory.
- If implementation or real-world testing disproves an accepted ADR, update or replace the ADR immediately before treating the new behavior as settled.

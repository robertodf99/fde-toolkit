# Superpowers selection

Triage in SKILL.md takes precedence over Superpowers descriptions. Repo skills
replace equivalent practices when they are the adopted standard.
The table applies to canonical Herdr dispatch. The coordinator retains control
of phases; workers perform only the assigned role.

| Skill | N0 | N1 | N2 | N3 |
|---|---|---|---|---|
| verification-before-completion | Yes | Yes | Yes | Yes |
| brainstorming | No | No | No | Only open design |
| writing-plans | No | No | No | Only more than one task |
| test-driven-development | Not required | Not required | Features/bugs | Features/bugs |
| systematic-debugging | Not required | Not required | Bugs/failures | Bugs/failures |
| subagent-driven-development | No | No | No | No: extracted practices |
| requesting-code-review | No | No | No: revisor role | No: revisor role |
| executing-plans | Never | Never | Never | Never |
| finishing-a-development-branch | Does not authorise merge, publication or closure | Same | Same | Same |

With Herdr, DO NOT invoke subagent-driven-development or requesting-code-review:
their native dispatches would duplicate roles. The reviewer is always this
methodology's `revisor` role.

## Extracted practices

- Diagnosis: reproduce the symptom, gather evidence, form a hypothesis and test
  the cause before fixing it. An unexpected failure during validation requires
  diagnosis; do not chain speculative patches.
- TDD: for features/bugs from N2, observe a behaviour test fail for the expected
  reason, implement the minimum and retest. Types and builds do not prove the
  effect. Do not add tests that merely repeat the implementation.
- Brainstorming: at N3 with open design, explore constraints and alternatives,
  define criteria and present a reviewable design. Do not reopen an approved design.
- Writing-plans: at N3 with several tasks, order dependencies, scope and validation
  per criterion in an artifact. The coordinator writes an N1/N2 brief.
- Execution (extracted from subagent-driven-development): give the sole implementer
  a self-contained brief with scope, criteria, interfaces, worktree and validation;
  keep their session and review their evidence before advancing.
  Tasks order the work, rather than creating additional implementers.
- Review (extracted from requesting-code-review): give this methodology's reviewer
  the base, final SHA, criteria, stable diff and evidence with clean context.
  The report explains consequences and evidence.
- Verification: run the relevant checks and read results before claiming success.
  Report every omitted check with its reason and effect on confidence.

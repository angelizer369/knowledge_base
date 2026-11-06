# AI Rules

Mandatory behavior rules for AI assistants working in this repository.

## Scope and precedence

- Read these rules alongside [`AGENTS.md`](../AGENTS.md), deeper agent instructions and the relevant repository runbooks.
- Preserve repository-specific execution, approval, privacy and safety requirements. This general baseline does not replace those controls or grant runtime, credential, publication or deployment authority.

## Working agreement

- Own the routine steps already authorized by the operator's request. Do not repeat permission prompts for unchanged intent; ask for genuine unresolved decisions, exceptional risks or unsatisfied mandatory approvals.
- Respect narrower instructions such as review-only, source-only or do-not-deploy. Keep changes minimal, task-focused and consistent with existing style; reuse existing helpers rather than adding unnecessary dependencies, wrappers or infrastructure.
- Preserve unrelated working-tree changes, Git history and retained evidence. Never silently expand the task, rewrite history or clean up another task's files.

## Execution and validation

- Use the repository's approved runtimes, wrappers, targets and validation paths. A container shell or filesystem bind mount is not host command access; do not invent a local or remote fallback.
- Do not download, install or execute tools, packages, binaries or images from unapproved sources. If a required workflow or access path is unavailable, state the blocker instead of bypassing it.
- Run the narrowest relevant checks first and widen only for affected consumers or mandatory final gates. Prose-only changes outside sealed executable inputs normally need diff/link checks, not application reruns.
- Reuse reliable unchanged-input evidence without implying a fresh run or current live acceptance. Avoid redundant connectivity or authentication probes when the repository already documents a working path and no new failure contradicts it.
- Report actual checks, outcomes, skipped checks and remaining gaps. Do not claim a build, test, deployment, migration, publication or rollback occurred unless it did.

## Security and operational safety

- Never put secrets, credentials, tokens, private keys, personal data or unredacted sensitive payloads in code, documentation, logs, examples or commits. Use sanitized evidence and protected references.
- Preserve existing authentication, authorization, tenant/data boundaries, fail-closed behavior and approval requirements for live actions, trading, billing, destructive changes, publication and deployment.
- Prefer bounded read-only inspection, plans and reversible changes before approved mutations. An uncertain mutation requires reconciliation, not replay; preserve required rollback, evidence and scoped cleanup.

## Instruction-document hygiene

- Keep `AGENTS.md` and other always-loaded instruction documents focused on durable policy, essential repository orientation and concise workflow entrypoints. They are not task journals, release logs or operational status ledgers.
- Put dated rollout summaries, per-run IDs/hashes/test counts, incident timelines and narrative handoffs in the existing topic/task/checkpoint record, not another always-loaded instruction file. Link to one canonical current record instead of duplicating it; do not create a new record for routine work that does not need one. Respect existing private/ignored evidence locations and confidentiality rules.
- Durable operator decisions, execution/access boundaries, approval requirements and non-replay rules remain binding instructions even when originally dated. Never classify a safety rule as disposable history merely because it contains a date.
- When moving transient context, retain a brief visible pointer to each active blocker, uncertainty hold or stop condition in the applicable entrypoint/rule until resolved. Preserve full approval scopes, expiry, exact-byte constraints, consumed claims, failed outcomes and retained evidence in the canonical record; moving text grants no authority, resets no attempt count and permits no replay.
- Before handing off instruction changes, review every addition: it must be durable policy, necessary orientation or a concise active-hold pointer. Update the existing canonical rule rather than appending parallel rules; consolidate superseded duplication only after checking that no binding constraint is lost and required historical evidence remains retained. Verify affected links and instruction indexes.
- This hygiene rule does not authorize broad cleanup, evidence deletion, edits to historical worktree/vendor snapshots or weaker safety/validation gates. It is a review requirement, not a hard size limit or permission to hide unresolved risks.

## No-progress circuit breaker

- Before costly review, builds, validation or deployment, define observable completion criteria and check prerequisites with bounded, authorized read-only preflight: access, current state, required approvals and an approved validation path. Do not start a workflow with a known unmet prerequisite.
- Diagnose before retrying: record the failed step, concrete evidence, likely cause, relevant change and why the next attempt should behave differently. A new UUID, tag, agent, session or reworded prompt is not a fix.
- If the same blocker occurs twice without meaningful progress, stop that execution path. Do not make a third unchanged attempt or reset the count through another agent, workflow or session. Resume only after diagnosis identifies a relevant change and all required gates are satisfied. Stricter single-attempt or fail-closed rules stop execution earlier; this limit never authorizes a second attempt.
- Use narrowly scoped, authorized read-only checks to diagnose a stopped path. If recovery is outside the request or cannot proceed safely, report the exact blocker, evidence and next action or genuine decision needed. Perform already-authorized routine steps without repeated permission prompts; retain all repository-specific approval requirements.
- For blocked or multi-session work, keep a short, sanitized checkpoint in the existing task/incident record: completion criteria, completed work and evidence references, current blocker and attempt count, consumed or expired approvals, and the exact next step. Resume from that checkpoint after verifying current state instead of restarting failed paths; never include secrets.
- Stop when the completion criteria and mandatory acceptance checks are met. Do not repeat unchanged checks or add wrappers, approval layers or unrelated work merely to keep moving.
- All existing safety gates remain intact. Never weaken isolation, bypass review, re-date an approval, reuse a consumed claim or widen approved scope to escape a loop. Preserve required fail-closed actions, rollback, reconciliation, evidence and scoped cleanup when stopping.

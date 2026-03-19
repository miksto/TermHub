# CLAUDE.md

## CRITICAL: Teams, not sub-agents

This project uses **Teams** (via `TeamCreate`) — NOT standalone sub-agents. Every agent in this project MUST be part of a team. The distinction matters:

- **Team agents** share a task list, can message each other via `SendMessage`, and persist for the duration of the work. They coordinate as peers under the coordinator.
- **Standalone sub-agents** (Agent tool without `team_name`) are isolated, cannot communicate with other agents, and return a single result. **Do NOT use this pattern.**

**Rules:**
1. ALWAYS call `TeamCreate` before spawning any agent
2. EVERY `Agent` call MUST include both `team_name` and `name` parameters
3. An `Agent` call without `team_name` is a bug — never do this
4. All agents must be on the SAME team (same `team_name` value)

## Team Startup

When the user asks to start the team (e.g., "start the team", "execute the plan"), the main Claude agent must:

1. Find the most recent plan file in `.claude/plans/` and read its contents
2. Call TeamCreate to create the team (this sets up shared task list + messaging)
3. Spawn the coordinator agent with the Agent tool, passing the full plan content in the prompt along with instructions to decompose and execute it. Use BOTH `team_name` and `name` parameters.
4. The coordinator then spawns the remaining team members as needed, all using the same `team_name`

The main Claude agent does NOT act as the coordinator — it only bootstraps the team and hands off control.

**Generic agent spawning pattern:** When spawning any agent into the team, always use `TeamCreate` first (once), then `TaskCreate` to define work, then `Agent` with both `team_name` and `name` parameters.

## Communication Protocol

All team members must report back to the coordinator (via SendMessage to "coordinator") whenever:
- A task is completed
- They need help resolving an issue or are blocked
- A merge conflict is encountered

The coordinator is the central point of communication and decision-making. The coordinator communicates with the user directly using `AskUserQuestion` when clarification is needed.

**Review requests** must include:
- The commit SHA(s) covering the work
- A brief summary of what was changed and why
- The relevant spec/requirements for the task (as provided by the coordinator)

**Rejections** must include:
- What specifically failed the review
- Concrete instructions on what needs to change
- Reference to the spec or standard being violated

**Escalations:** If an implementer disagrees with a rejection, they may escalate to the coordinator. The coordinator has final authority to resolve disputes.

## Git Discipline

Every completed logical step — no matter how small — must be committed to the git repo immediately. Commits must:
- Contain only the changes related to that specific step — no unrelated changes bundled in
- Be made before moving on to the next task or step
- Have a clear, descriptive commit message

The coordinator is responsible for enforcing this. All team members are expected to follow it as standard practice.

**Commit proof requirement:** When requesting any review, the implementer MUST include the commit SHA(s) covering the work. Reviewers should verify the commit exists. If an implementer requests a review without a commit hash, the reviewer must flag this to the coordinator and the implementer must commit and re-request with the hash before the review proceeds.

**Merge conflicts:** When parallel implementers create conflicts, the implementer whose commit comes second is responsible for resolving the conflict. If they cannot resolve it, they escalate to the coordinator who may reassign or re-scope.

## Task Workflow

The standard lifecycle for a task is:

1. **Coordinator** breaks down the plan into tasks and assigns them to implementers, including the relevant plan context for each task
2. **Implementer** implements the assigned task and commits changes
3. **Implementer** verifies all tests still pass. If tests fail due to the implementer's changes, fix them before proceeding. If tests fail due to unrelated causes, escalate to the coordinator before proceeding.
4. **Implementer** requests review in parallel from the requirements-analyst AND the designer (if UI-impacting files were touched), including the commit SHA(s) and task context
5. **All reviews run concurrently.** The coordinator triggers the test-engineer and reviewer at the same time as the implementer triggers the requirements-analyst and designer.
6. **Coordinator** marks the task as done once all applicable reviews pass

**Review routing:**

| Reviewer | Triggered by | Reviews what |
|---|---|---|
| Requirements Analyst | Implementer (via SendMessage) | Spec compliance, edge cases, error handling |
| Designer | Implementer (via SendMessage) | UI/UX impact (only when UI-impacting files are touched) |
| Test Engineer | Coordinator (via SendMessage) | Test quality and coverage |
| Reviewer | Coordinator (via SendMessage) | Architecture, security, code quality |

On rejection at any step, work is sent back to the implementer with clear feedback. The implementer fixes, commits, and re-submits for review with the new commit SHA.

**Rejection loop limit:** If a task is rejected 3 times at the same review step, it is escalated to the coordinator. The coordinator must investigate, provide a decision, and either re-scope the task, provide specific guidance, or reassign it.

## Task Granularity

When decomposing work, the coordinator should aim for tasks that are:
- **Independently testable** — the task produces a result that can be verified in isolation
- **Independently reviewable** — a reviewer can assess the task without needing to see unfinished sibling tasks
- **Small enough** for a single implementer to complete and get through the review cycle without excessive back-and-forth
- **Large enough** to be meaningful — avoid micro-tasks that create coordination overhead (e.g., "rename one variable" is too small unless it's a targeted fix)

Rule of thumb: if a task touches more than 3-4 files or introduces more than one concept, consider splitting it.

## Team Members

### Coordinator (name: "coordinator")

**Core principle:** The coordinator manages, it never implements. It does not edit files, write code, write tests, or produce any artifact directly. Its only outputs are task assignments, decisions, and messages to team members.

**On startup:**
1. The coordinator receives a plan (from the planning agent) as its input — this plan is the spec and source of truth
2. Read and fully understand the plan in its entirety
3. If anything in the plan is ambiguous or underspecified, use `AskUserQuestion` to ask the user up to 4 clarifying questions before proceeding — do not guess at requirements
4. The coordinator does NOT modify the plan's approach or scope. If it identifies issues with the plan (e.g., missing steps, contradictions, infeasible items), it must escalate to the user via `AskUserQuestion` before deviating
5. Decompose the plan into discrete, well-scoped tasks (see Task Granularity)
6. Identify dependencies between tasks and determine which can run in parallel
7. Spawn implementers (up to 5, named "implementer-1" through "implementer-5") and assign tasks
8. When assigning a task, always include the relevant plan context AND the full plan so that reviewers downstream have it

**During execution:**
- Track progress of all active tasks and their review status
- When a reviewer rejects work, ensure the feedback reaches the implementer and the fix is re-submitted
- When an implementer is blocked, investigate the blocker and either reassign, re-scope, or provide guidance
- Enforce git discipline: if any team member flags uncommitted work, instruct the implementer to commit immediately
- Monitor for idle agents — if an implementer finishes a task, assign the next one promptly
- Monitor for merge conflicts between parallel implementers and coordinate resolution
- Trigger the reviewer and test-engineer proactively — send them work as soon as implementation is committed, in parallel with the implementer-triggered reviews
- **Dispute resolution:** The coordinator has final authority. If an implementer and reviewer cannot agree after escalation, the coordinator makes the call and both parties follow it.
- **Holistic reviews:** Trigger a holistic codebase review from the reviewer at natural midpoints (e.g., after roughly half the tasks are done) and again before declaring the job complete

**Quality gates:**
- A task is only done when it has passed ALL applicable reviews: requirements-analyst, designer (if UI-impacting), test-engineer, and reviewer
- If any review surfaces issues, the task goes back to the implementer — it is NOT done
- The coordinator must not mark a task complete just because the implementation exists; reviews must pass
- After 3 rejections at the same step, the coordinator must intervene directly

**Completion:**
- The job is finished only when every task from the decomposition is marked done and all reviews have passed
- Before declaring completion, the coordinator must verify: every requirement from the original plan is addressed, all tests pass, and there are no open review items
- Report the final status to the user with a summary of what was implemented

### Implementer (name: "implementer-1" through "implementer-5")
- A role template — the coordinator spawns as many as needed (up to 5), named "implementer-1", "implementer-2", etc.
- Receives tasks from the coordinator, including the relevant plan context
- Implements the assigned work
- After implementation, verifies that all tests still pass. If tests fail from own changes, fix before proceeding. If tests fail from unrelated causes, escalate to the coordinator.
- MUST commit all changes before requesting any review — include the commit SHA(s) in every review request
- Requests reviews in parallel from the requirements-analyst and the designer (if UI-impacting files were touched), including task context and commit SHA(s)
- If merge conflicts arise with other implementers' work, the implementer whose commit comes second resolves the conflict — escalate to coordinator if unable
- Follows git discipline: commits each logical step before moving on
- If a rejection is received, fix the issue, commit, and re-submit with the new SHA. If you disagree with the rejection, escalate to the coordinator rather than ignoring it.

### Requirements Analyst (name: "requirements-analyst")
- Acts as a critic and requirements gatekeeper
- Receives the full plan from the coordinator at startup for cross-cutting context
- Reviews solution proposals from implementers before they are considered done
- Evaluates against: original plan compliance, edge cases, error handling, input validation, and user-facing behavior
- Can check whether a task's implementation conflicts with or undermines other tasks in the plan
- If a review request arrives without a commit SHA, flag it to the coordinator and request the implementer to commit first
- Rejects incomplete work and sends it back to the implementer with clear, actionable feedback

### Test Engineer (name: "test-engineer")
- Reviews tests written by implementers for quality, coverage, and best practices
- Does NOT write tests — instead identifies gaps and requests the implementer to write missing tests
- Developers must not take shortcuts to make tests pass — tests must reflect real quality and best practices
- If an implementer writes low-quality tests or cuts corners, the test engineer sends it back with specific instructions on what to fix
- This is a belt-and-suspenders role: implementers are expected to write good tests by default, but the test engineer enforces it
- Activated by the coordinator when tasks are ready for test review — does not self-activate

### Reviewer (name: "reviewer")
- Monitors the overall state of the codebase: architecture, security, and code quality
- Does NOT evaluate feature completeness (that is the coordinator's and requirements analyst's responsibility)
- Informs the coordinator about issues, risks, and technical debt
- Suggests improvements and flags anything that deviates from best practices
- Activated by the coordinator when tasks are ready for code review — does not self-activate
- Performs holistic codebase reviews when triggered by the coordinator at midpoints and before completion

### Designer (name: "designer")
- Uses the `frontend-design` skill to ensure UI and UX is polished
- Reviews changes that touch UI-impacting files (components, styles, templates, layouts, and any files that affect rendering or user interaction)
- Pays attention to small but important usability details that often get overlooked
- Reviews interfaces for visual consistency, accessibility, and user experience quality
- Activated by implementer review requests — reviews concurrently with the requirements-analyst

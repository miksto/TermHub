# CLAUDE.md

## Agent Configuration

When spawning collaborative agents, follow these steps in order:

1. Call TeamCreate first to create the team (this sets up shared task list + messaging)
2. Create tasks with TaskCreate to define the work
3. Spawn agents with the Agent tool using BOTH team_name and name parameters

## Communication Protocol

All team members must report back to the coordinator (via SendMessage to "coordinator") whenever:
- A task is completed
- They need help resolving an issue or are blocked
- A merge conflict is encountered

The coordinator is the central point of communication and decision-making.

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

1. **Coordinator** breaks down the spec into tasks and assigns them to implementers, including the relevant spec/requirements context for each task
2. **Implementer** implements the assigned task and commits changes
3. **Implementer** verifies all tests still pass
4. **Implementer** requests review in parallel from both the requirements-analyst AND the designer, including the commit SHA(s) and task context
5. **Requirements-analyst** and **designer** review concurrently and report results
6. **Test engineer** validates test quality and coverage — requests the implementer to write any missing tests
7. **Reviewer** checks code quality, architecture, and security
8. **Coordinator** marks the task as done once all reviews pass

Steps 5-7 may run in parallel where possible — the coordinator should trigger the test engineer and reviewer at the same time as the requirements-analyst and designer when appropriate.

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
1. Read and fully understand the spec/requirements provided by the user
2. If anything is ambiguous or underspecified, ask the user up to 4 clarifying questions before proceeding — do not guess at requirements
3. Decompose the work into discrete, well-scoped tasks (see Task Granularity)
4. Identify dependencies between tasks and determine which can run in parallel
5. Spawn implementers (up to 5, named "implementer-1" through "implementer-5") and assign tasks
6. When assigning a task, always include the relevant spec/requirements context so that reviewers downstream have it

**During execution:**
- Track progress of all active tasks and their review status
- When a reviewer rejects work, ensure the feedback reaches the implementer and the fix is re-submitted
- When an implementer is blocked, investigate the blocker and either reassign, re-scope, or provide guidance
- Enforce git discipline: if any team member flags uncommitted work, instruct the implementer to commit immediately
- Monitor for idle agents — if an implementer finishes a task, assign the next one promptly
- Monitor for merge conflicts between parallel implementers and coordinate resolution
- Trigger the reviewer and test-engineer proactively — do not wait for them to self-activate; send them work when implementation + initial reviews are underway
- **Dispute resolution:** The coordinator has final authority. If an implementer and reviewer cannot agree after escalation, the coordinator makes the call and both parties follow it.

**Quality gates:**
- A task is only done when it has passed ALL reviews: requirements-analyst, designer, test-engineer, and reviewer
- If any review surfaces issues, the task goes back to the implementer — it is NOT done
- The coordinator must not mark a task complete just because the implementation exists; reviews must pass
- After 3 rejections at the same step, the coordinator must intervene directly

**Completion:**
- The job is finished only when every task from the decomposition is marked done and all reviews have passed
- Before declaring completion, the coordinator must verify: every requirement from the original spec is addressed, all tests pass, and there are no open review items
- Report the final status to the user with a summary of what was implemented

### Implementer (name: "implementer-1" through "implementer-5")
- A role template — the coordinator spawns as many as needed (up to 5), named "implementer-1", "implementer-2", etc.
- Receives tasks from the coordinator, including the relevant spec/requirements context
- Implements the assigned work
- After implementation, verifies that all tests still pass
- MUST commit all changes before requesting any review — include the commit SHA(s) in every review request
- Requests reviews in parallel from both the requirements-analyst AND the designer, including task context and commit SHA(s)
- If merge conflicts arise with other implementers' work, the implementer whose commit comes second resolves the conflict — escalate to coordinator if unable
- Follows git discipline: commits each logical step before moving on
- If a rejection is received, fix the issue, commit, and re-submit with the new SHA. If you disagree with the rejection, escalate to the coordinator rather than ignoring it.

### Requirements Analyst (name: "requirements-analyst")
- Acts as a critic and requirements gatekeeper
- Reviews solution proposals from implementers before they are considered done
- Evaluates against: original spec compliance, edge cases, error handling, input validation, and user-facing behavior (using the task context provided in the review request)
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
- Additionally, the coordinator should trigger a holistic codebase review from the reviewer at major milestones (e.g., after all tasks are complete, before declaring the job done)

### Designer (name: "designer")
- Uses the `frontend-design` skill to ensure UI and UX is polished
- Reviews ALL changes — not just explicitly UI-related ones — to catch indirect UI/UX impacts
- Pays attention to small but important usability details that often get overlooked
- Reviews interfaces for visual consistency, accessibility, and user experience quality
- Activated by implementer review requests — reviews concurrently with the requirements-analyst

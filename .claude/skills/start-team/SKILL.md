---
name: start-team
description: Start a collaborative agent team to execute a plan. Creates a team with coordinator, implementers, reviewers, test engineer, designer, and requirements analyst. Use when the user says "start the team", "execute the plan", "run the plan", "kick off", "begin implementation", "let's build this", "start working on this", "spin up the team", "let's go", "ok implement this", "make it happen", "get started on the plan", or any similar request to begin collaborative implementation work — even if the user doesn't explicitly say "team".
disable-model-invocation: false
user-invocable: true
---

## Teams, not sub-agents

This skill uses **Teams** (via `TeamCreate`). Every team member must be part of the same team so they can communicate via `SendMessage`.

**Rules for spawning team members:**
1. Call `TeamCreate` before spawning any team member
2. Every team member `Agent` call must include both `team_name` and `name` parameters
3. All team members must be on the same team (same `team_name` value)
4. The main Claude agent spawns the coordinator, review roles, and implementers. It analyzes the plan to determine how many implementers are needed (up to 5).

**Sub-agents:** Team members may freely spawn standalone sub-agents (Agent tool without `team_name`) for helper tasks like research, code exploration, or one-off analysis. These sub-agents are isolated — they cannot message team members and are discarded when done. This is fine and expected.

## Team Startup

The main Claude agent bootstraps the team by reading the plan and spawning the coordinator, all review roles, and implementers.

1. Find the most recent plan file in `.claude/plans/` and read its contents (or use a path if provided as an argument: `$ARGUMENTS`)
2. Read the plan content
3. Call `TeamCreate` to create the team
4. Read the prompt file for each role from `prompts/` (paths relative to this skill's directory: `${CLAUDE_SKILL_DIR}/prompts/`)
5. Spawn the following agents using the `Agent` tool with both `team_name` and `name` parameters. For each agent's `prompt`, use the contents of its prompt file and append the full plan content at the end.

### Agents for the main agent to spawn

| Agent | Name | Prompt file |
|---|---|---|
| Coordinator | `coordinator` | `prompts/coordinator.md` |
| Requirements Analyst | `requirements-analyst` | `prompts/requirements-analyst.md` |
| Test Engineer | `test-engineer` | `prompts/test-engineer.md` |
| Reviewer | `reviewer` | `prompts/reviewer.md` |
| Designer | `designer` | `prompts/designer.md` |
| Implementers (up to 5) | `implementer-1`, `implementer-2`, etc. | `prompts/implementer.md` |

**Spawning implementers:** Before spawning agents, analyze the plan to determine how many implementers are needed (up to 5) based on the number of parallelizable tasks. Spawn each implementer with the implementer prompt file contents and the full plan appended.

**For the coordinator prompt**, also append: the `team_name` value and the list of implementer names that were spawned (e.g., "implementer-1", "implementer-2", "implementer-3") so the coordinator knows which implementers are available.

After spawning all agents, the main agent hands off control. The coordinator will decompose the plan into tasks and assign them to the available implementers.

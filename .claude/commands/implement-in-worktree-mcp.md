Create a new git worktree and open it in a new TermHub session with Claude ready to implement a plan. Uses MCP tools instead of the termhub:// URL scheme.

Arguments: `$ARGUMENTS` should be the branch name for the new worktree (e.g. `/implement-in-worktree-mcp my-feature`).

Steps:

1. Get the current repo root by running `git rev-parse --show-toplevel`.
2. Use the plan file from the current conversation (the one you wrote during planning). If no plan was created in this conversation, ask the user which plan file to use.
3. Only use a sandbox if the user explicitly mentioned one in `$ARGUMENTS` or in the conversation. Do not prompt for sandbox selection. If a sandbox name is provided, pass it as `sandboxName` in step 5.
4. If `$ARGUMENTS` is empty, ask the user for a branch name.
5. Call `mcp__termhub__create_worktree` with:
   - `folderPath`: the repo root from step 1
   - `branch`: `$ARGUMENTS`
   - `newBranch`: `$ARGUMENTS` (to create a fresh branch)
   - `sandboxName`: the selected sandbox name (omit if none)
6. If a plan file exists, call `mcp__termhub__send_keys` with:
   - `sessionId`: the `sessionId` returned from step 5
   - `text`: `claude "Implement the plan in <absolute-path-to-plan-file>"`

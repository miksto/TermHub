Create a new git worktree and open it in a new TermHub session with Claude ready to implement a plan.

Arguments: `$ARGUMENTS` should be the branch name for the new worktree (e.g. `/implement-in-worktree my-feature`).

Steps:

1. Get the current repo root by running `git rev-parse --show-toplevel`.
2. Use the plan file from the current conversation (the one you wrote during planning). If no plan was created in this conversation, ask the user which plan file to use.
3. URL-encode the repo path and plan path (replace spaces with `%20`, etc.).
4. Run the following command, substituting the values:

```
open "termhub://new-worktree?repo=<repo-path>&branch=$ARGUMENTS&plan=<plan-path>"
```

If no plan file is found, omit the `plan` parameter.
If `$ARGUMENTS` is empty, ask the user for a branch name.

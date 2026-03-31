---
description: "Resolve GitHub PR review comments by implementing requested changes."
argument-hint: "<PR number or URL>"
---

You are resolving GitHub PR review comments.

## Input
$ARGUMENTS

## Process

1. Spawn the `pr-comment-resolver` agent with the PR reference:
   "Resolve review comments on PR $ARGUMENTS"

2. The agent will:
   - Fetch all review comments via `gh api`
   - Categorize each: must-fix, question, suggestion, approval
   - Implement must-fix changes
   - Answer questions (with code comments or PR replies)
   - Evaluate suggestions and implement if clearly better
   - Run tests after each change
   - Report what was resolved, deferred, or needs discussion

3. After the agent completes:
   - Review the resolution report
   - Verify all tests pass
   - Update ops/CHANGELOG.md with the changes
   - If significant changes were made, consider running `/review` on the changed files

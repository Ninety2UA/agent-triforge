# Step 2: diagnose (if confirmed)

Name the root cause with evidence before changing any code:

1. **Classify the error** — syntax, logic, state, integration, environment, performance.
2. **Track assumptions** — create an assumption ledger and verify each one.
3. **Narrow the search** — use bisection, not linear scanning.
4. **Root cause analysis** — ask "why" up to 5 times to find the actual root cause.
5. **Check for contradiction** — if two findings conflict, flag it; do not silently pick one.

Test one hypothesis at a time. After two failed fixes, stop and re-check the assumption behind them; after a third on the same error, stop and give the user an escalation report: the error signature, what was tried, and a suggested next step.

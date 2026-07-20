# PXL Transaction Workspace Rollout Playbook

**Status:** Operational validation pointer; not a UI authority
**Current UI authority:** `docs/PXL/12. UI and UX/PXL_TRANSACTION_WORKSPACE_STANDARD.md`
**Content variation authority:** `docs/PXL/12. UI and UX/PXL_TRANSACTION_WORKSPACE_PATTERNS.md`
**Executable inventory:** `src/lib/transactionWorkspaceCoverage.ts`

This file retains only the rollout procedure. It must not define layout, visual tokens, component geometry, tab order, or transaction content.

1. Add the implemented route to the executable inventory and classify it A–E.
2. Preserve the domain page's posting, tax, inventory, lifecycle, permissions, RLS, and draft-state logic.
3. Compose `TransactionWorkspace`; use `LegacyTransactionWorkspace` only as a temporary single-mount compatibility boundary.
4. Supply source-backed cards, impacts, relations, actions, and truthful unavailable states according to the patterns document.
5. Run the structural test, authenticated route sweep, screenshot comparisons, zoom/viewport/theme checks, lint, typecheck, build, secret checks, and documentation checks.
6. Update `AI/AI_STATE.md` and the executable inventory only when verified coverage changes.

Current commands:

```bash
npm run test:transaction-workspace
npm run test:transaction-workspace:routes
npm run test:transaction-workspace:screenshots
npm run lint
npx tsc -b --pretty false
npm run build
npm run docs:check
```

Accounting, tax, inventory, and security validation remains transaction-domain work; a green visual sweep does not qualify business completeness.

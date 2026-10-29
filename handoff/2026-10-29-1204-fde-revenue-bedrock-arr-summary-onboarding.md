# ARR Summary onboarding

- Created: 2026-10-29 12:04 local, from XFINJIMBLAPTOP
- Repo: https://starlightagilebi.visualstudio.com/AgBI/_git/FDE_Revenue_Bedrock (local path C:\Files\Dev\msft\FDE_Revenue_Bedrock)
- Branch: jimb/main at 5f1dd14f, 8 commits unpushed (no push approval yet). PR branch jimb/AB-467246/refactor/arr-fact-arrsummary at 5fa89528, pushed.
- Uncommitted: .mcp.json (machine-local Playwright and WorkIQ MCP settings; copy by hand if needed, never commit)

## Goal

Onboard ARR_FACT_ARRSummary to Bedrock as nb_silver_arr_fact_arrsummary (User Story 467246, parent Feature 446278). The ARR cube's ARR Summary table (20 partitions) reads it.

## Done

- Story 467246 created and linked to parent 446278.
- PR branch jimb/AB-467246/refactor/arr-fact-arrsummary cut from origin/main 223d3589. Commit 5fa89528 (pushed) changes:
  - 01: ARR Summary moves to backlog; ARR Budget stays excluded as "Not to be onboarded".
  - 02: ARR Summary analysis row added; ARR Budget graded high only so triage can run.
  - 03: reopen and decision notes.
  - support/cube-lineage.csv: FACT_ARRSummary row.
- jimb/main rebased onto origin/main. 5fa89528 cherry-picked as 48f01324.
- 8cb60044 adds platform/src/data-platform/engine/processing/silver/notebooks/nb_silver_arr_fact_arrsummary.Notebook:
  - env_10_xl.
  - Reads stay on the source abidata paths.
  - Header lists the 15 certified producers.
  - validate_notebook_contract.py --as-is passes.
  - 01 row is ready_for_validation.
- 5f1dd14f (27 Oct 16:30) merged origin/jimb/main back in. It changed no files, but the history now has both the old and the rebased copies of the 3 personal commits.

## Next steps

1. Decide how to push jimb/main: a plain git push keeps the merge commit; git reset --hard 8cb60044 then git push --force-with-lease origin jimb/main gives clean history.
2. Sync FDE_Bedrock_Dev_jimb to the pushed SHA, then run notebook validation (onboard-solution-notebook, validate-notebook stage) for nb_silver_arr_fact_arrsummary.
3. After parity passes: connect stage, e2e, approval, certify, Gold contract line 82 update.
4. Cherry-pick 8cb60044 (plus later validated commits) onto the PR branch and open the PR.

## Open decisions

- jimb/main push method (step 1).
- Validation prerequisites:
  - The Fabric identity needs read access to abidata@fdedatalakeprod01; the source used the mssalesfdlprod linked service.
  - env_10_xl must set spark.driver.cores and spark.executor.instances.
- Output is Delta instead of Parquet; the delete-before-write cell is kept.
- Parity risks: FACT_ARR has a second writer (ARR_FACT_ARR_Azure); FiscalQuarter labels depend on the data; DIM_TPAccount and BRIDGE joins can count measures twice.
- 03 line 81 still says SnapshotDateFix is held at backlog; 01 has it excluded.

## Resume commands

```powershell
cd C:\Files\Dev\msft\FDE_Revenue_Bedrock
git fetch origin
git switch jimb/main
git status -sb
git log --oneline -3
```
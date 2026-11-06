# ARR Summary isolated validation

- Created: 2026-11-05 16:26 local, from XFINJIMBLAPTOP
- Repo: https://starlightagilebi.visualstudio.com/AgBI/_git/FDE_Revenue_Bedrock (local path C:\Files\Dev\msft\FDE_Revenue_Bedrock)
- Branch: jimb/main at 779d5077, pushed
- Uncommitted: none tracked. Gitignored evidence stays on the laptop only:
  `docs/learnings/solutions/arr/working/workspace-readiness.json` and
  `docs/learnings/solutions/arr/working/notebook-validation/arrsummary/` (staging session + run.json)

## Goal

Onboard ARR Summary (`nb_silver_arr_fact_arrsummary`, ADO story 467246) for ARR cube support:
isolated notebook validation with source-output parity, then connection switch, e2e, approval, certification.

## Done

- Fabric workspace `FDE_Bedrock_Dev_jimb` (849e1def-450c-495a-a2d4-a0d82510180d) synced to 779d5077.
  0 incoming, 0 conflicts. 9 accepted workspace changes kept on purpose: wh_conf, pl_pipeline_main,
  pl_process_batch, pl_recover_tick, shared_alm, env_4_medium, env_10_large, env_10_xl, env_25_large.
- Unblocked the sync:
  - Notebook 0795e3db was renamed to Gold and back to `nb_silver_mwdetail_bridge_specialproductsgroup`
    to clear a "reserved name" rename collision.
  - Two personal-only commits on jimb/main: 08d358fd drops `pl_notify_tick_summary` (Teams
    connection 532a651e returns 403 for jimb); 779d5077 drops the `launch_tick_notification` step from
    the Git copy of `pl_pipeline_main`. Drop both once the Teams connection is shared. Never cherry-pick.
- Retired `nb_gold_mwdetail_fact_target` is removed from the workspace (definition saved in session files).
- Readiness passed (`vl_storage_paths` active = dev, env_10_xl published).
- User approved the recursive delete + rewrite of dev `lh_silver/Tables/arr/fact_arrsummary`
  (Claude Sonnet 5 review required explicit approval; given).
- Staged target, status `staged`. Run submitted 16:21 local with env_10_xl,
  job instance 247f9a55-e2ac-46f1-b753-5bc848c483bb, running since 16:23 local.

## Next steps

1. Check the run in Fabric Monitor (job 247f9a55...). Abort threshold: 40 min running, i.e. 17:03 local.
   If still running then, cancel and diagnose. The laptop's local runner/heartbeat stops if the laptop sleeps;
   the Fabric job keeps running.
2. On success, run the parity comparison per ARR 03 (`docs/learnings/solutions/arr/03-solution-details.md`):
   comparison Environment env_10_large, declared method and thresholds. Source output is Parquet, dev is Delta.
3. End the staging session: `stage_notebook_validation.py accept` on pass, `rollback` otherwise
   (alias jimb, target nb_silver_arr_fact_arrsummary, same session dir). The session dir lives on the laptop;
   finish it there, or re-stage from scratch on the Dev Box.
4. Consolidate with `consolidate_onboarding.py complete-notebook-validation` to move 01 to `notebook_validated`.
5. Then connect stage, e2e, human approval, certification.

## Open decisions

- Orchestration is not safe to run: kept wh_conf lacks `catalog.process.isolated_spark`, and kept pipelines
  differ from Git. Reconcile before any pipeline run. Any warehouse write needs independent review.
- pl_recover_tick shows a workspace change that was not investigated.
- Fabric Git update operation ID from 15:22 was lost; the later UI update superseded it.

## Resume commands

```powershell
cd C:\Files\Dev\msft\FDE_Revenue_Bedrock
git fetch origin; git switch jimb/main; git pull
git rev-parse --short HEAD   # expect 779d5077
```

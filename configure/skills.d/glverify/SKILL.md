---
name: glverify
description: Check GitLab pipeline health via the uber-tools tool, pull failed-job logs, and summarize root cause and next steps
---

## What I do

The uber-tools script lives at `${HOME}/.config/uber-tools/uber-tools.sh`. Always call it by its full path (do not rely on the `ut` alias, which may not be loaded in non-interactive shells). Use:

```
UT="${HOME}/.config/uber-tools/uber-tools.sh"
"${UT}" gitlab pipeline status
"${UT}" gitlab pipeline failedlogs
```

1. Confirm you are inside a Git repository that uber-tools can probe:
   - Run `git rev-parse --show-toplevel` to locate the repo root.
   - uber-tools talks to a GitLab-hosted repo, so the current repo must live on a GitLab server the uber-tools credentials cover. If you are not in the right folder, ask the user which repo/commit to check and let them run you there before proceeding.
2. Get the pipeline status by running `"${UT}" gitlab pipeline status` from the repo root.
3. Interpret the status output (see below).
4. If the status is `failed`, pull the logs with `"${UT}" gitlab pipeline failedlogs`.
5. Summarize the result for the user: current health, any failing job(s), the root cause, and concrete next steps.

## Output format notes

### `ut gitlab pipeline status`

The output starts with credential/probe chatter (`Loading credentials...`, `Credentials loaded successfully`, `Probing <path> on <host> ...`, `API probe OK`), then:

```
Latest pipelines for <sha> (<project/path>):

ID      IID   STATUS     REF      UPDATED
-------------------------------------------------------------------
55955  21    success   main   2026-09-17T20:17:57.989Z
        sha: 953984136f25d6f032e46df463db52d807fccdc1
        url: https://gitlab.<host>/<project/path>/-/pipelines/55955
<...more rows...>
```

- The pipeline table columns are `ID  IID  STATUS  REF  UPDATED`: the **3rd column is the status** and the 4th is the branch/ref.
- Each row is followed by `sha:` and `url:` lines (the `sha:` belongs to the previous row). The `url:` links to the pipeline.
- The latest pipeline is the top row — that is the one that matters.
- Status values: `success`, `failed`, `running`, `pending`, `canceled`. A healthy pipeline shows `success`.

### `ut gitlab pipeline failedlogs`

When nothing failed:

```
No failed jobs found for commit <sha> on <project/path>
```

When jobs failed, it prints a `Pipeline <id> — jobs: <n>` banner, then one section per failed job:

```
Pipeline 55933 — jobs: 2

------------------------------------------------------------
[build/build: [ARM64, arm64]] failed (id=152869, status=failed)
------------------------------------------------------------
<full job log follows; the failing command and error are near the tail>
...
error  Installation failed
...
ERROR: failed to solve: ... did not complete successfully: exit code: 1
```

- The banner line names the pipeline id and the count of failed jobs.
- Each failed job is introduced by a `[<job-name>: <ref>] failed (id=<job-id>, status=failed)` marker under a dashed separator.
- The root cause lives near the tail of each job's log: the failing command, an `ERROR:` / `error` line, and the `exit code: N`. For example in a Docker build: the `RUN ...` step plus `ERROR: failed to solve: ... exit code: 1`; for npm: `npm error ... No matching version found for <pkg>@<ver>`.

## Interpretation and summary

- Report the latest pipeline: project/path, sha, ref, status, and its `url:`.
- If `success` → say the pipeline is green; nothing else to do (unless the user wants diff/newer info).
- If `running`/`pending` → report it is still in progress and suggest re-checking later.
- If `canceled` → report as canceled (not a failure).
- If `failed` → run `"${UT}" gitlab pipeline failedlogs`, then for each failed job give:
  - the failing job name,
  - the root cause extracted from the `ERROR:` / `error` lines (e.g. npm `ETARGET` / no matching version, a failing `docker build` step, missing/expired credentials),
  - concrete next steps (pin a version, fix version drift, check registry/credentials/token, or retry) — and flag anything that is likely a transient failure.

## Notes

- The uber-tools script is installed by `configure/uber-tools.sh` at `${HOME}/.config/uber-tools/uber-tools.sh`; call it by full path as shown in "What I do". Do not rely on the `ut` alias — it may not exist in non-interactive/open-code shells.
- Only run pipelines and fetch logs; never modify, retry, or cancel pipelines unless the user explicitly asks.

## When to use me

Use this when the user wants to check whether a GitLab pipeline is healthy, verify a pipeline after a push, or debug a failing pipeline and understand why it failed.

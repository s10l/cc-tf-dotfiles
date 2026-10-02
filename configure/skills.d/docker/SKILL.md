---
name: docker
description: Guide for using Docker in this environment - building images, running or inspecting containers, compose, and registry operations. Read this before any docker command, because only the Docker CLI is installed here: there is no local daemon, and the daemon is reached exclusively through two docker contexts, "sandbox-arm64" and "sandbox-amd64", each of which can only build and run its own architecture.
---

## What I do

Two sandboxes exist, split by architecture:

| Architecture | Docker context |
| --- | --- |
| `arm64` | `sandbox-arm64` |
| `amd64` | `sandbox-amd64` |

Each sandbox runs containers and builds images for **its own architecture only**. There is no emulation between them, so picking the wrong one produces `exec format error` or a build that fails at `RUN`.

1. Work out which architecture the task needs, and pick the context from the table above:

   - An explicit `--platform linux/arm64` / `--platform linux/amd64`, a multi-arch build step, or the user's words ("the arm64 image") settle it.
   - Otherwise look at the repo: the CI job matrix in `.gitlab-ci.yml` or `.github/workflows/`, a `Makefile` target, a `docker-bake.hcl` or `compose.yaml` `platform:` field, or the image tags the user names.
   - If it is still ambiguous, **ask the user** which architecture to target — one question, offering `arm64` and `amd64`. Do not guess and do not pick by looking at what the containers happen to be.

2. If the task needs **both** architectures, do the work once per context: run it on `sandbox-amd64`, then switch and run it again on `sandbox-arm64`. Do not try to produce a multi-arch image from one sandbox.

3. Find out which context is active:

   ```
   docker context show
   ```

   This prints a single word: the active context name.

4. If it is not the target context, activate it:

   ```
   docker context use sandbox-arm64
   docker context use sandbox-amd64
   ```

   `docker context show` and `docker context use sandbox-arm64` / `docker context use sandbox-amd64` are pre-approved. Run them without asking for permission, every time the target changes. Nobody else uses docker on this machine, so switching the context cannot disturb anyone.

5. Confirm the daemon really is the architecture you are about to build for:

   ```
   docker info --format '{{.Architecture}}'
   ```

   It must print `aarch64` on `sandbox-arm64` and `x86_64` on `sandbox-amd64`. If it prints anything else, or the command fails, go back to step 1 and 3 — a mismatch here is what causes `exec format error`, so never skip it.

6. If the target context does not exist, **stop**. Do not run the docker work, and do not fall back to another context. Report:

   ```
   Failed to initialize: unable to resolve docker endpoint: context "sandbox-arm64": context not found
   ```

   and tell the user that only the docker CLI is installed here, so `sandbox-arm64` and `sandbox-amd64` have to exist before any daemon-backed command can run. Ask them which endpoint the missing context should point at; do not guess an endpoint and do not create the context yourself.

7. Only once the active context is the target one and step 5 confirms the architecture, do the actual docker work.

## When to use me

Use this whenever you are about to run any docker command — `docker build`, `docker buildx`, `docker run`, `docker ps`, `docker exec`, `docker logs`, `docker compose`, `docker pull`, or anything else. Reach for it before the first command, not after one fails.

## Rules

- There is **no local docker daemon** on this machine. `/var/run/docker.sock` does not exist, so the `default` context always fails with `dial unix /var/run/docker.sock: connect: no such file or directory`.
- Only `sandbox-arm64` and `sandbox-amd64` are valid targets. Never run `docker context use` with any other name — not `default`, not `desktop-linux`, and not any other named context that happens to exist here (such as a personal `lab` context). Never set `DOCKER_HOST` yourself.
- Never run or build the other architecture on the active sandbox: no `--platform` that contradicts the context, and do not lean on QEMU/binfmt emulation. `sandbox-amd64` does `amd64`, `sandbox-arm64` does `arm64` — pick the matching one.
- Re-check the active context with `docker context show` after anything that could have changed it (a new shell, another agent or tool running docker). Never assume it is still the one you set.
- Read-only inspection does not need permission: `docker ps`, `docker images`, `docker logs`, `docker inspect`, `docker info`, `docker system df`.
- Destructive or local-state-changing commands need the user to ask for them first: `docker system prune`, `docker container prune`, `docker image prune`, `docker builder prune`, `docker buildx prune`, `docker rm`, `docker rmi`, `docker volume rm`, `docker network rm`, and any `--force` on those. Note that images, containers and volumes are per sandbox — a prune on one sandbox does not touch the other.
- Never `docker push`, delete an image from a registry, or run `docker login` unless the user explicitly asks. Credentials are handled elsewhere; never read, print or pass secret values.
- The daemon is **remote**. Anything that happens on a filesystem path, a published port, or a named volume happens on the remote host, not on the local machine. See below before writing a `-v` mount or a `-p` flag.

## Remote daemon gotchas

Both sandbox daemons are on other hosts. The local machine has the CLI and nothing else.

- **Bind mounts resolve on the remote host.** `docker run -v "$PWD:/app" img` mounts the *remote* host's `$PWD`, which usually does not exist — docker then silently creates an empty directory, so the container sees nothing. To get local files into a container, either build an image with them (`docker build`, the build context is uploaded from the local machine and works) or copy them after starting with `docker cp <path> <container>:<path>`.
- **Published ports listen on the remote host.** `-p 8080:80` does not make anything reachable at `localhost:8080`. It is reachable at the remote host's address.
- **The two sandboxes share nothing.** Images, containers and named volumes are per sandbox, so a container started on `sandbox-amd64` does not exist on `sandbox-arm64` and neither can `docker exec` into the other. Plan per-architecture work as two independent runs.
- **`docker exec` and `docker logs` work normally** against the remote containers.
- **`docker build` uploads the build context from the local machine.** A `.dockerignore` still applies locally, so keep it tight rather than trying to exclude files at the daemon.
- **Resource limits and paths that exist locally are meaningless to the daemon.** A volume path that only exists on the local filesystem is the single most common failure — see the bind mount note above.

## Output format notes

### `docker context show`

Prints one word and nothing else:

```
sandbox-arm64
```

That word is the only thing to compare against, and it must be the one you picked in step 1. If it is anything else, the daemon commands that follow would go to the wrong architecture — activate the right context first.

### `docker context ls`

```
NAME              DESCRIPTION                     DOCKER ENDPOINT                   ERROR
default           Current DOCKER_HOST based ...   unix:///var/run/docker.sock
sandbox-amd64 *                                   ssh://root@amd64.example.com
sandbox-arm64                                    ssh://root@arm64.example.com
```

- Columns are `NAME  DESCRIPTION  DOCKER ENDPOINT  ERROR`; the **1st column is the context name** and the 2nd is its endpoint.
- A `*` next to the name marks the active context.
- The **2nd column is the endpoint** — this is what tells you whether a context points at a local socket or a remote daemon.
- A non-empty `ERROR` column means the context cannot be reached.
- `default` and any other context appearing here are not targets for this work; ignore them.

### `docker info --format '{{.Architecture}}'`

```
aarch64
```

- Prints one Go architecture word and nothing else: **`aarch64` on `sandbox-arm64`, `x86_64` on `sandbox-amd64`**.
- This is the check that must pass before building or running. It is the authority on which architecture the daemon is, as opposed to the context name, which is only a label.

### Arch vocabulary mismatch

The same architecture has different names in different places. Translate before comparing:

| Concept | In `--platform` / CI / tags | In `docker info`, `docker version`, `uname -m` |
| --- | --- | --- |
| amd64 | `linux/amd64`, `x86_64` | `x86_64` |
| arm64 | `linux/arm64`, `aarch64` | `aarch64` |

- `--platform linux/amd64` and `x86_64` are the same architecture; `linux/arm64` and `aarch64` are the same architecture. Do not treat `arm64` and `aarch64` as two different targets.
- `docker manifest inspect` and registry manifests describe the *manifest* platform as `linux/arm64`; the `Architecture` field of a `docker info`/`docker version` `Server` block is `aarch64`/`x86_64`.

### `docker ps`

```
CONTAINER ID   IMAGE          COMMAND                  CREATED         STATUS          PORTS          NAMES
```

- The **1st column is the container ID**, the 6th is `STATUS` and the 8th is the name. `docker logs` and `docker exec` take either the ID or the name.
- `PORTS` shows where the port is published **on the remote host** — read it as the remote address, not as a local one.

### `docker buildx ls`

```
NAME/NODE       DRIVER/ENDPOINT   STATUS    BUILDKIT   PLATFORMS
default *       docker
```

- The **last column is `PLATFORMS`** — the architectures that builder can produce. If it lists only `linux/amd64`, that builder cannot build the arm64 image; use the other sandbox instead of passing `--platform` to it.
- `PLATFORMS` showing `linux/arm64*` means the build will fall back to QEMU emulation — which is exactly the slow, fragile path to avoid here.

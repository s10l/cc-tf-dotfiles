---
name: docker
description: Guide for using Docker in this environment - building images, running or inspecting containers, compose, and registry operations. Read this before any docker command, because only the Docker CLI is installed here: there is no local daemon, and the daemon is reached exclusively through the docker context named "sandbox".
---

## What I do

1. Find out which docker context is active:

   ```
   docker context show
   ```

   This prints a single word: the active context name.

2. If it is not `sandbox`, activate it:

   ```
   docker context use sandbox
   ```

   These two commands — `docker context show` and `docker context use sandbox` — are pre-approved. Run them without asking for permission. Nobody else uses docker on this machine, so switching the context cannot disturb anyone.

3. If `sandbox` does not exist, **stop**. Do not run the docker work, and do not fall back to another context. Report:

   ```
   Failed to initialize: unable to resolve docker endpoint: context "sandbox": context not found
   ```

   and tell the user that only the docker CLI is installed here, so the `sandbox` context has to exist before any daemon-backed command can run. Ask them which endpoint `sandbox` should point at; do not guess an endpoint and do not create the context yourself.

4. Only once `docker context show` prints `sandbox`, do the actual docker work.

## When to use me

Use this whenever you are about to run any docker command — `docker build`, `docker run`, `docker ps`, `docker exec`, `docker logs`, `docker compose`, `docker buildx`, `docker pull`, or anything else. Reach for it before the first command, not after one fails.

## Rules

- There is **no local docker daemon** on this machine. `/var/run/docker.sock` does not exist, so the `default` context always fails with `dial unix /var/run/docker.sock: connect: no such file or directory`.
- Never fall back to `default`, to another named context, or by setting `DOCKER_HOST` yourself. If `sandbox` is missing, stop and report it.
- Never run `docker context use` with any name other than `sandbox`.
- Read-only inspection does not need permission: `docker ps`, `docker images`, `docker logs`, `docker inspect`, `docker info`, `docker system df`.
- Destructive or local-state-changing commands need the user to ask for them first: `docker system prune`, `docker container prune`, `docker image prune`, `docker builder prune`, `docker buildx prune`, `docker rm`, `docker rmi`, `docker volume rm`, `docker network rm`, and any `--force` on those.
- Never `docker push`, delete an image from a registry, or run `docker login` unless the user explicitly asks. Credentials are handled elsewhere; never read, print or pass secret values.
- The daemon is **remote**. Anything that happens on a filesystem path, a published port, or a named volume happens on the remote host, not on the local machine. See below before writing a `-v` mount or a `-p` flag.

## Remote daemon gotchas

The daemon behind the `sandbox` context is on another host. The local machine has the CLI and nothing else.

- **Bind mounts resolve on the remote host.** `docker run -v "$PWD:/app" img` mounts the *remote* host's `$PWD`, which usually does not exist — docker then silently creates an empty directory, so the container sees nothing. To get local files into a container, either build an image with them (`docker build`, the build context is uploaded from the local machine and works) or copy them after starting with `docker cp <path> <container>:<path>`.
- **Published ports listen on the remote host.** `-p 8080:80` does not make anything reachable at `localhost:8080`. It is reachable at the remote host's address.
- **Images, containers and named volumes live on the remote daemon** and persist there. They are not affected by anything local, and they are shared with whatever else uses that same daemon.
- **`docker exec` and `docker logs` work normally** against the remote containers.
- **`docker build` uploads the build context from the local machine.** A `.dockerignore` still applies locally, so keep it tight rather than trying to exclude files at the daemon.
- **Resource limits and paths that exist locally are meaningless to the daemon.** A volume path that only exists on the local filesystem is the single most common failure — see the bind mount note above.

## Output format notes

### `docker context show`

Prints one word and nothing else:

```
sandbox
```

That word is the only thing to compare against. If it is anything other than `sandbox`, the daemon commands that follow would go to the wrong place — activate `sandbox` first.

### `docker context ls`

```
NAME      DESCRIPTION                               DOCKER ENDPOINT                   ERROR
default   Current DOCKER_HOST based configuration   unix:///var/run/docker.sock       
lab *                                               ssh://root@lab.stefanbickel.com   
```

- Columns are `NAME  DESCRIPTION  DOCKER ENDPOINT  ERROR`; the **1st column is the context name** and the 2nd is its endpoint.
- A `*` next to the name marks the active context.
- The **2nd column is the endpoint** — this is what tells you whether a context points at a local socket or a remote daemon.
- A non-empty `ERROR` column means the context cannot be reached.

### `docker info`

```
Client:
 Version:  29.5.3
 Context:  sandbox
 ...
Server:
 Containers: 8
 ...
```

- The `Context:` line under `Client:` is the authoritative answer to which context the client will use. Check it instead of assuming.
- The `Server:` block only appears if the daemon answered. If it is missing, or the command ends with `failed to connect to the docker API`, the context is not usable — go back to step 3.
- With a remote daemon the `Server Version` is the remote host's daemon version, which need not match `Client Version`.

### `docker ps`

```
CONTAINER ID   IMAGE          COMMAND                  CREATED         STATUS          PORTS          NAMES
```

- The **1st column is the container ID**, the 6th is `STATUS` and the 8th is the name. `docker logs` and `docker exec` take either the ID or the name.
- `PORTS` shows where the port is published **on the remote host** — read it as the remote address, not as a local one.
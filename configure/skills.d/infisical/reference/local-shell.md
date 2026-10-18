# Local shell: the `infisical.sh` wrapper

The dotfiles repo ships a bash wrapper at `<repo>/bin/infisical/infisical.sh`
(documented in `<repo>/bin/infisical/infisical.md`). `./bootstrap.sh` puts that
directory on `PATH`, so in a login shell the command is simply `infisical.sh`.

Requirements: `bash`, `curl`, `jq`.

## Reading a secret

```
infisical.sh secret get [flags] <secret-name>
```

| Flag | Description |
| --- | --- |
| `-p <id>` | Project ID (overrides the config value) |
| `-e <slug>` | Environment slug (overrides the config value) |
| `-s <path>` | Secret folder path (overrides the config value, default `/`) |
| `-v, --verbose` | Print the curl command used, to stderr |

```bash
value=$(infisical.sh secret get GLPAT)
infisical.sh secret get -s /other GLPAT
infisical.sh secret get -p <id> -e prod GLPAT
```

### Output contract

- The **value** goes to stdout, **nothing else** - so command substitution
  captures exactly the value.
- All diagnostics go to stderr; **every** failure exits `1` and leaves stdout
  empty, so the result of command substitution can be tested directly:

  ```bash
  if ! value=$(infisical.sh secret get GLPAT); then
    echo "could not retrieve GLPAT" >&2
    exit 1
  fi
  ```

- One deliberate exception: a secret that exists with an **empty** value is
  treated as success - it prints nothing and exits `0`, with a `note:` line on
  stderr. Guard against this before using the value as a credential (see
  `fetch_secret` below).

### Configuration

The wrapper sources its own dotenv-style config file, which provides
`INFISICAL_URL`, the project, the environment, the default path, the
Universal Auth machine-identity pair, and the P12 client certificate file. The
config location is overridable with `INFISICAL_CONFIG_FILE`. When the config
or any required value is missing, the wrapper prints an actionable error to
stderr and exits `1` - follow that message; the wrapper is the authority on
its own configuration.

## `fetch_secret` for dotfiles modules

Inside the dotfiles repo, `lib/common.sh` provides, for configure modules:

```
fetch_secret <secret-name> <secret-path> <tag>
```

It calls the wrapper, prints the value on stdout, and additionally **fails
when the value comes back empty** - the raw wrapper treats an empty value as
success, which is what would let an empty token be written out as
`https://oauth2:@host`.

## How it works

1. Sources the config file (all `INFISICAL_*` values come from it).
2. Logs in via Universal Auth - `POST {INFISICAL_URL}/api/v1/auth/universal-auth/login`
   with the machine-identity client id/secret - and takes the `accessToken`.
   The request carries the P12 client certificate
   (`curl --cert-type P12 --cert ...`).
3. Reads the secret:

   ```
   GET {INFISICAL_URL}/api/v4/secrets/{name}
       ?projectId=<id>&environment=<slug>&secretPath=<path>&viewSecretValue=true
   Authorization: Bearer {accessToken}
   ```

   also with the client certificate.
4. Extracts and prints `.secret.secretValue`.

Non-200 responses are reported with the HTTP status and the response body; a
404 additionally names the secret and the environment/path it was looked up
in.

# infisical.sh

A lightweight Bash script to fetch a single secret value from a self-hosted
[Infisical](https://infisical.com) instance using a service token.

## Requirements

- `bash`
- `curl`
- `jq`

## Setup

Set these environment variables:

| Variable | Required | Description |
|----------|----------|-------------|
| `INFISICAL_TOKEN` | yes | Full Infisical service token (prefixed with `st.`) |
| `INFISICAL_URL` | yes | Infisical host URL, e.g. `https://infisical.example.com` |
| `INFISICAL_PROJECT_ID` | no | Project (workspace) ID |
| `INFISICAL_ENV_SLUG` | no | Environment slug, e.g. `dev`, `prod` |
| `INFISICAL_SECRET_PATH` | no | Secret folder path, defaults to `/` |

```bash
export INFISICAL_TOKEN="st.xxx.yyy.zzz"
export INFISICAL_URL="https://infisical.example.com"
export INFISICAL_PROJECT_ID="abc123"
export INFISICAL_ENV_SLUG="dev"
```

## Usage

```
infisical.sh secret get [flags] <secret-name>
```

### Flags

| Flag | Description |
|------|-------------|
| `-p <id>` | Project ID (overrides `INFISICAL_PROJECT_ID`) |
| `-e <slug>` | Environment slug (overrides `INFISICAL_ENV_SLUG`) |
| `-s <path>` | Secret path (overrides `INFISICAL_SECRET_PATH`, default `/`) |

### Examples

```bash
# Everything from env vars
./infisical.sh secret get <name-of-the-secret>

# Override just the path, keep env for project/env
./infisical.sh secret get -s /other <name-of-the-secret>

# Override project and environment
./infisical.sh secret get -p xyz456 -e prod <name-of-the-secret>
```

The secret value is printed to stdout. Use it directly in pipelines or scripts:

```bash
./infisical.sh secret get <name-of-the-secret>
./infisical.sh secret get <name-of-the-secret> > /tmp/<name-of-the-secret>
```

## How it works

1. Strips the key portion from the service token (everything after the last
   `.`) and uses the remaining access token in the `Authorization` header.
2. Calls the Infisical V4 API:

   ```
   GET /api/v4/secrets/{secretName}
     ?projectId=<id>&environment=<slug>&secretPath=<path>&viewSecretValue=true
   ```

3. Extracts and prints `secretValue` from the JSON response.

## Errors

- Missing args or required env vars print usage / an error and exit non-zero.
- Network failures report the `curl` exit code.
- API errors (non-200) report the HTTP status, the full request URL, and the
  response body — useful for diagnosing 401/403/404 (often a token scope,
  environment slug, or path mismatch).

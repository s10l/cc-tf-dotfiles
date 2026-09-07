# infisical.sh

A lightweight Bash script to fetch a single secret value from a self-hosted
[Infisical](https://infisical.com) instance using a service token.

## Requirements

- `bash`
- `curl`
- `jq`

## Config file

The script reads its configuration from a dotenv-style file at
`$HOME/.config/infisical/.env`. The path can be overridden with the
`INFISICAL_CONFIG_FILE` environment variable.

The file is sourced as shell code, so each variable is a plain
`KEY="value"` assignment:

```
INFISICAL_TOKEN="st.xx.yy.zz"
INFISICAL_URL="https://infisical.example.com"
INFISICAL_PROJECT_ID="abc123"
INFISICAL_ENV_SLUG="dev"
INFISICAL_SECRET_PATH="/"
INFISICAL_CLIENT_CERT_FILE="/home/user/.config/infisical/client.p12"
```

| Variable | Required | Description |
|----------|----------|-------------|
| `INFISICAL_TOKEN` | yes | Full Infisical service token (prefixed with `st.`) |
| `INFISICAL_URL` | yes | Infisical host URL, e.g. `https://infisical.example.com` |
| `INFISICAL_PROJECT_ID` | yes* | Project (workspace) ID |
| `INFISICAL_ENV_SLUG` | yes* | Environment slug, e.g. `dev`, `prod` |
| `INFISICAL_SECRET_PATH` | no | Secret folder path, defaults to `/` |
| `INFISICAL_CLIENT_CERT_FILE` | no | Path to a TLS client certificate (PKCS#12/PFX, cert + key bundled) used for mTLS; if set, it is passed to curl as `--cert-type P12 --cert` |

*`INFISICAL_PROJECT_ID` and `INFISICAL_ENV_SLUG` can be supplied via the
`-p` and `-e` flags instead.

Keep the file readable only by your user (`chmod 600`) since it contains
the service token.

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
| `-v, --verbose` | Print the curl command to stderr before running it |

### Examples

```bash
# Everything from the config file
./infisical.sh secret get GLPAT

# Override just the path
./infisical.sh secret get -s /other GLPAT

# Override project and environment
./infisical.sh secret get -p xyz456 -e prod GLPAT

# Print the curl command used
./infisical.sh secret get --verbose GLPAT
```

The secret value is printed to stdout. Use it directly in pipelines or scripts:

```bash
./infisical.sh secret get GLPAT
./infisical.sh secret get GLPAT > /tmp/glpat
```

## How it works

1. Sources the config file and reads `INFISICAL_*` values from it.
2. Strips the key portion from the service token (everything after the last
   `.`) and uses the remaining access token in the `Authorization` header.
3. Calls the Infisical V4 API:

   ```
   GET /api/v4/secrets/{secretName}
     ?projectId=<id>&environment=<slug>&secretPath=<path>&viewSecretValue=true
   ```

4. Extracts and prints `secretValue` from the JSON response.

If `INFISICAL_CLIENT_CERT_FILE` is set, the request is made with that
certificate as the TLS client certificate (`curl --cert-type P12 --cert`).
The file must be a PKCS#12 (`.pfx`/`.p12`) container holding both the client
certificate and its key.

## Errors

- If the config file is missing, or required variables are not set in it, the
  script prints an error and exits non-zero.
- Network failures report the `curl` exit code.
- API errors (non-200) report the HTTP status, the full request URL, and the
  response body — useful for diagnosing 401/403/404 (often a token scope,
  environment slug, or path mismatch)

# Pipeline: the `infisical.sh` in the gl-gi-docker-deploy golden image

The GitLab runner image `s10l/gl-gi-docker-deploy` (tag `latest`, or pin a
`YYYY.MM.DD` tag for a reproducible job) ships a transport wrapper at
**`/usr/local/bin/infisical.sh`**.

Why a wrapper and not the Infisical CLI also in the image: this Infisical
instance sits behind mandatory mTLS and the CLI cannot present a client
certificate - against such an instance it fails in the TLS handshake, long
before authentication. Do not reach for `infisical export` here; use
`infisical.sh`.

## Environment

All six required for every verb; the script fails naming the first missing
one. Pass them as (masked, protected) CI/CD variables:

| Variable | Description |
| --- | --- |
| `INFISICAL_URL` | Base URL of the instance |
| `INFISICAL_CLIENT_ID` | Universal Auth machine identity client id |
| `INFISICAL_CLIENT_SECRET` | Universal Auth machine identity client secret |
| `INFISICAL_PROJECT_ID` | Project holding the secrets |
| `INFISICAL_ENV_SLUG` | Environment slug |
| `INFISICAL_CLIENT_CERT_PFX_B64` | Base64 of the P12 client certificate |
| `INFISICAL_TOKEN_FILE` | *(optional)* where the cached access token is stored; the wrapper picks a default |

## Verbs

| Verb | Behaviour |
| --- | --- |
| `login` | Authenticates, reusing a cached token while its `exp` claim is valid. Prints `token: reusing` or `token: acquired`. |
| `pull-secret <path> <name> [--output-file FILE]` | Writes the value to stdout, or to `FILE`, which is created mode `0600` (atomically - never written in place). Values stored base64-encoded are handed back decoded. |
| `push-secret <path> <name> [--input-file FILE]` | Reads the value from stdin, or from `FILE`, which wins if both are given. Compares first: prints `<name>: unchanged` instead of rewriting an identical value; otherwise creates or updates. Refuses an empty value. |
| `rm-secret <path> <name>` | Deletes a secret. **Refuses any path outside `/ci-selftest/`**, so it cannot reach real certificates. |
| `secret-version <path> <name>` | Prints the stored version, for diagnostics. |

```bash
# pull into a file, then inspect what came back without printing it
infisical.sh pull-secret /ci-secrets/example fullchain --output-file fullchain.pem
openssl x509 -in fullchain.pem -noout -subject -dates

# push from stdin or from a file
printf '%s' "$KEY" | infisical.sh push-secret /ci-secrets/example privkey
infisical.sh push-secret /ci-secrets/example privkey --input-file privkey.pem
```

## Behaviour guarantees

- **Every verb authenticates on its own** - `ensure_token` runs per verb,
  reusing the cached token while its JWT `exp` claim is more than 60 s in the
  future. An explicit `login` in a pipeline is documentation, not a
  dependency.
- **A 401 triggers a re-login and one retry**, because a long job can outlive
  its token.
- **Secrets never travel through argv.** The bearer token, the client secret
  and secret values are passed to curl through files.
- **Nothing prints a token, a secret value or a response body.** Output is
  limited to the path, the name, the HTTP status and the outcome; all failure
  text goes to stderr with a non-zero exit.
- **Multiline unwrap is conservative.** Infisical stores multiline values
  base64-encoded; the wrapper unwraps a value only when it decodes to a PEM
  block - anything else could be a base64-looking secret of its own.
- **`push-secret` is create-or-update**: a 404 on the pre-read means create
  (which answers `200`, not `201`); an existing value means update.
- **`rm-secret` is guarded on the path, not the environment**: the configured
  environment is the one holding the real certificates, so only the
  self-test prefix is removable.

## Endpoints used

All requests carry the P12 client certificate.

```
POST {INFISICAL_URL}/api/v1/auth/universal-auth/login      # Universal Auth
GET  {INFISICAL_URL}/api/v4/secrets/<name>
     ?projectId=<id>&environment=<slug>&secretPath=<path>&viewSecretValue=true
POST {INFISICAL_URL}/api/v4/secrets/<name>                 # create
PATCH {INFISICAL_URL}/api/v4/secrets/<name>                # update
DELETE {INFISICAL_URL}/api/v4/secrets/<name>?projectId=<id>&environment=<slug>&secretPath=<path>
```

Requirements: `curl`, `jq`, `base64`.

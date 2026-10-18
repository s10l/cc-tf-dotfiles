# Code in the app: the v4 API

For a program that must fetch a secret itself (Go or any other language).
Copy the requests below instead of a snippet from memory.

## 1. Authenticate with Universal Auth (machine identity) once per run

```
POST {INFISICAL_URL}/api/v1/auth/universal-auth/login
Content-Type: application/json

{"clientId": "...", "clientSecret": "..."}
```

Take `accessToken` from the response. It is short-lived: fetch it per run
rather than caching it on disk.

## 2. Read the secret from the **v4** endpoint

```
GET {INFISICAL_URL}/api/v4/secrets/{name}
    ?projectId={project}&environment={env}&secretPath={path}&viewSecretValue=true
Authorization: Bearer {accessToken}
```

- `projectId` is the ID (a UUID here), not the slug.
- `environment` is the environment slug (`dev`, `prod`), not the folder.
- `secretPath` is the folder, `/` for the root.
- Send `viewSecretValue=true`.
- The value is nested: `{"secret": {"secretKey": ..., "secretValue": ...}}`.

## 3. Send the mTLS client certificate on **every** request, login included

```
curl --cert-type P12 --cert <p12-bundle> ...
```

This instance enforces mTLS, so a request without it dies in the TLS
handshake rather than with an HTTP status. The server certificate is
publicly trusted - no CA file is needed.

## 4. Treat any non-2xx as a failure and report the body

A 404 is a real answer (name/environment/path mismatch); a 400 is a real bug
in the request. An empty value must never be returned as success.

## Version rules

- **v4 for reads.** `GET /api/v4/secrets/<name>` is the current endpoint. Do
  not use `/api/v3/secrets/raw/...`, and never `/api/v2/secrets/...`.
- **v3 needs `workspaceId`, not `projectId`.** `/api/v3/secrets/raw/<name>`
  still answers, but only with `workspaceId=<id>` (or `projectSlug`);
  sending `projectId` is rejected with `400 "You must provide projectSlug or
  workspaceId"`. New code has no reason to use v3.
- **The v2 route is gone.** `GET /api/v2/secrets/<name>` is a 404 - it is not
  a fallback.

## PKCS#12 needs a PBES2-capable decoder

Bundles from here are PBES2 / PBKDF2-HMAC-SHA256 + AES-256-CBC with a SHA-256
MAC. The frozen `golang.org/x/crypto/pkcs12` understands only legacy
(SHA-1/3DES) bundles and fails with `unknown ... algorithm` /
`pkcs12: unknown digest algorithm`.

- In Go use `software.sslmate.com/src/go-pkcs12` (`pkcs12.DecodeChain`, which
  also returns the intermediates to send).
- In other languages use a PBES2-capable library, or `openssl`/`curl`, which
  handle it.
- Only if a consumer cannot be changed, re-export as legacy first - decrypt,
  then export, because `-legacy` alone cannot read a modern input:
  `openssl pkcs12 -in modern.p12 -nodes` -> PEM, then
  `openssl pkcs12 -export -legacy -in cert.pem -inkey key.pem`.

Where the certificate bundle comes from in a given language or deployment is
deployment configuration; the code only needs a decoded cert/key chain and
the mTLS requirement above.

## Known failure signatures

| Symptom | Cause | Fix |
| --- | --- | --- |
| `400 {"message":"You must provide projectSlug or workspaceId"}` | v3 read sent `projectId` | use v4, or send `workspaceId` to v3 |
| `404 {"message":"Secret with name '<x>' not found","error":"NotFound"}` | name, environment or path mismatch - or genuinely absent | compare `environment` and `secretPath` with the UI |
| `404` on `/api/v2/secrets/<name>` | route was removed | use v4 |
| `curl: (56) ... tlsv13 alert certificate required` | request carried no client certificate | add `--cert-type P12 --cert <bundle>` to every call, login included |
| `pkcs12: unknown digest algorithm` / `unknown ... algorithm` loading a `.p12` | PBES2 bundle read by a legacy-only decoder | decode with `software.sslmate.com/src/go-pkcs12`, or re-export with `openssl ... -legacy` |
| HTTP 200 with an empty value and no error | response read without checking, usually after a swallowed 400 | assert non-2xx **and** a non-empty `.secret.secretValue` |

## Output format notes

- Login: read `accessToken` from the response - it is the only field needed.
- Read: the value is at `.secret.secretValue`, one level down. `.secret` is
  absent when nothing matched, so "no secret object" is a not-found, not an
  empty secret.
- Infisical errors are JSON:
  `{"reqId": "...", "statusCode": N, "message": "...", "error": "..."}`.
  `message` is the human-readable part; quote it in diagnostics and leave the
  value out.

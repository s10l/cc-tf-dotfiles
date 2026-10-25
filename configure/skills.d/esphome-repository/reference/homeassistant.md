# Home Assistant side (optional)

Only for repos whose firmware talks to Home Assistant. Without HA, omit this
folder, `deploy-ha.sh`, `check-package-isolation.sh`, the `homeassistant`
target and the `ha-isolation` CI job.

## Layout

```
homeassistant/
  README.md
  packages.d/
    <pkg>.yaml          package root: MAPPING of domain keys
    <pkg>.d/
      ports.yaml        input_text ports (the only foreign ids)
      helpers.yaml      package-owned input_number/input_select
      template.yaml     mirrors/derived values
      automation.yaml   control loop
      CONTRACT.md       port table
  wiring.d/
    wiring.<pkg>.live.yaml
    wiring.<pkg>.bench.yaml
```

## The port mechanism

A **port** is an `input_text` that stores the id of an external entity the
package reads from or writes to. Templates read:

```jinja
{{ states(states('input_text.<pkg>_src_<port>')) | default('unknown', true) }}
```

HA tracks the second `states()` dynamically, so re-pointing a port in the
wiring overlay re-wires live with no automation edit and no restart.

Rules (condensed):

| Rule | Meaning |
|---|---|
| R1 | No foreign entity id inside `<pkg>.d/`; external access goes through a port. |
| R2 | Everything the package creates carries `<pkg>_` (names, `unique_id`, automation alias/id). |
| R3 | Ports default to unbound. Unbound => mirror `unknown` => consumers hold the last value; health entities name the failing port. |
| R4 | Writes into foreign entities are set-if-different (documented exceptions only). |
| R5 | Package roots are mappings; part files bound with `domain: !include` are BARE content (list, no domain key). |
| R6 | Ship a `CONTRACT.md` port table; review it before deploying. |
| R7 | `check-package-isolation.sh` enforces R1/R5 mechanically. |
| R8 | All HA deliverables live under `homeassistant/`, mirroring the live layout. |

`check-package-isolation.sh`:

- scans `*.yaml` under `packages.d/<pkg>.d/` (comments stripped; `CONTRACT.md`
  is not scanned),
- allows entity ids whose name starts with `<pkg>_`,
- allows service-call names (`number.set_value`, ...),
- rejects list roots and double-nested part files,
- rejects `text_sensor` (unsupported by the HA 2026 template integration).

Run it before deploying and in CI:

```sh
./check-package-isolation.sh homeassistant/packages.d
```

## Wiring

Exactly one variant per package is enabled at a time:

- `wiring.<pkg>.live.yaml` binds ports to real entity ids,
- `wiring.<pkg>.bench.yaml` binds them to local stand-ins for offline work.

Both are plain automations that set the ports on HA start. Never enable both:
the package would read from two sources.

## Deploy

`make homeassistant` runs `deploy-ha.sh`:

1. probes the target (`configuration.yaml` must exist),
2. copies `packages.d/` additively,
3. enables each package root in `configuration.yaml` (uncomment/normalize/
   insert; diff shown; timestamped host backup),
4. copies **one** wiring variant,
5. enables each deployed wiring file,
6. prints the validate/reload handoff.

Target formats:

```sh
make homeassistant                          # uses HA_TARGET from makefile.conf
./deploy-ha.sh user@host:/path/to/config    # ssh/scp, key auth
./deploy-ha.sh /absolute/local/config       # local path
HA_ASSUME=yes HA_WIRING=live ./deploy-ha.sh # agent/non-interactive
```

Validate and reload are **not** shell steps: run them through the Home
Assistant MCP/agent (validate config, then reload core config) or the UI.
A first-time package install needs a full HA start - `reload_core_config`
does not set up never-loaded packages (helpers stay missing, automations land
`unavailable`).

After reload, verify the ports: unbound ports mean mirrors are `unknown` and
the control loop holds its last value.

## Safety

- No secret is ever in an HA package, wiring file or `CONTRACT.md`.
- Do not delete the old package/include while rolling out a new one; comment
  the include out and prune in a separate, explicit step.
- Set-if-different for every write into a foreign entity; one documented
  heartbeat exception at most.

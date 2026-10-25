# homeassistant/ - HA-side deliverables

Home Assistant packages for @@PROJECT@@. The firmware in `../esphome/` is a
renderer of ready-to-use values; interpretation and control live here.

## What lives here

```
homeassistant/
  README.md                    # this file
  packages.d/
    @@PKG@@.yaml               # package root (mapping of domain keys)
    @@PKG@@.d/
      ports.yaml               # input_text bindings to external entity ids
      helpers.yaml             # package-owned input_number/input_select
      template.yaml            # mirrors and derived values
      automation.yaml          # control loop
      CONTRACT.md              # port table (review artifact)
  wiring.d/
    wiring.@@PKG@@.live.yaml   # real bindings
    wiring.@@PKG@@.bench.yaml  # offline dummy bindings (never with live)
```

## Isolation rules

| Rule | Meaning |
|---|---|
| R1 | No foreign entity id inside `@@PKG@@.d/`. External reads/writes go through an `input_text` **port** holding the source/target entity id. |
| R2 | Everything the package creates carries its prefix (`@@PKG@@_`): entity names, `unique_id`s, automation aliases/ids. |
| R3 | Ports default to **unbound**. Unbound/unavailable port => mirror `unknown` => consumers hold the last value; health entities name the failing port. |
| R4 | Every write into a foreign entity is set-if-different. |
| R5 | Package roots are mappings of domain keys; part files are BARE content. |
| R6 | Each package ships a `CONTRACT.md` port table - review it before deploying. |
| R7 | `../check-package-isolation.sh` greps each package for foreign ids and fails on a hit (comments stripped; `CONTRACT.md` is documentation and not scanned). |
| R8 | All HA deliverables live under `homeassistant/`, mirroring the live layout. |

## Deploy

`make homeassistant` (repo root) runs the copy-in interactively: deploys the
packages, deploys **one** wiring variant, patches `configuration.yaml`
(diff + timestamped host backup), and stops at the validate/reload handoff.

By hand:

1. Copy `homeassistant/packages.d/*` into the HA config's `packages.d/`.
2. Copy **one** wiring file into the HA config's `wiring.d/` (live for the
   real installation, bench for offline testing - never both).
3. Add to `configuration.yaml`:

```yaml
homeassistant:
  packages:
    @@PKG@@: !include packages.d/@@PKG@@.yaml
    wiring_@@PKG@@: !include wiring.d/wiring.@@PKG@@.live.yaml   # or bench
```

4. **Check configuration** must pass **before** reload. A first-time package
   install needs a full HA start: `reload_core_config` reloads automations
   from disk but does not set up never-loaded packages (helpers stay missing,
   automations land `unavailable`).
5. Reload core config, then verify the ports (unbound => mirrors unknown =>
   the control loop holds).

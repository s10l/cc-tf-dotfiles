# @@PKG@@ contract

Review this table before deploying the package. Every port listed here is
bound by one file in `homeassistant/wiring.d/`; only the wiring overlay may
name foreign entity ids.

## Ports

| Port | Direction | Bound entity | Meaning |
|---|---|---|---|
| `<pkg>_src_example` | read  | `<entity id>` | example value mirrored into `sensor.<pkg>_example_mirror` |
| `<pkg>_out_example` | write | `<entity id>` | example intent written back |

## Entities created

| Entity | Type | Notes |
|---|---|---|
| `sensor.<pkg>_example_mirror` | sensor | mirrors the port; `unknown` when unbound |

## Unbound behaviour

An empty or unavailable port makes the mirror `unknown`; consumers must hold
the last good value instead of writing a fallback. Health/availability
entities name the failing port.

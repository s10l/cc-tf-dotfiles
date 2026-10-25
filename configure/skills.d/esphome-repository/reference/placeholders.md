# Template placeholders

All templates live in `reference/templates/` and use `@@TOKEN@@` markers.
Substitute every one; the finished repo must contain no `@@`.

| Token | Meaning | Example |
|---|---|---|
| `@@PROJECT@@` | repo/project slug | `my-device` |
| `@@DEVICE@@` | one device slug (entry/package/CI examples) | `kitchen-sensor` |
| `@@DEVICES@@` | space-separated device list for the Makefile | `kitchen-sensor garage-sensor` |
| `@@DEVICES_CSV@@` | comma-separated device list for the CI matrix | `kitchen-sensor, garage-sensor` |
| `@@BOARD@@` | human-readable hardware description | `ESP32-S3 DevKitC, 8 MB flash` |
| `@@PKG@@` | HA package name / entity prefix | `kitchen` (entities `kitchen_*`) |
| `@@DUMMY_API_KEY@@` | base64 dummy key, 32 bytes, readable ASCII | `RVNQSE9NRS1EVU1NWS1LRVktMDAwMDAwMDAwMDAwMDA=` |
| `@@SCREENSHOT_PAGE@@` | LVGL page shown before a screenshot | `main_page` |
| `@@SCREENSHOT_BOOST_PAGE@@` | second page, or empty to disable | `boost_config_page` |
| `@@HA_TARGET@@` | HA config dir for `make homeassistant` | `user@ha-host:/config` |

The dummy key is the base64 of `ESPHOME-DUMMY-KEY-00000000000000` (32 bytes).
Keep it; `check-secrets.sh` and `secrets.yaml` must use the same value.
`makefile.conf` also inherits `@@HA_TARGET@@`.

## Rendering

```sh
SKILL_DIR="${HOME}/.config/opencode/skills/esphome-repository"
target=/absolute/path/to/new-repo
mkdir -p "$target"
cp -R "${SKILL_DIR}/reference/templates/." "$target/"
cd "$target"
sed -i \
  -e 's|@@PROJECT@@|my-device|g' \
  -e 's|@@DEVICE@@|kitchen-sensor|g' \
  -e 's|@@DEVICES@@|kitchen-sensor garage-sensor|g' \
  -e 's|@@DEVICES_CSV@@|kitchen-sensor, garage-sensor|g' \
  -e 's|@@BOARD@@|ESP32-S3 DevKitC, 8 MB flash|g' \
  -e 's|@@PKG@@|kitchen|g' \
  -e 's|@@DUMMY_API_KEY@@|RVNQSE9NRS1EVU1NWS1LRVktMDAwMDAwMDAwMDAwMDA=|g' \
  -e 's|@@SCREENSHOT_PAGE@@|main_page|g' \
  -e 's|@@SCREENSHOT_BOOST_PAGE@@||g' \
  -e 's|@@HA_TARGET@@|user@ha-host:/config|g' \
  $(grep -rl '@@' .)
```

Then rename the generic files:

- `esphome/device.yaml` -> `esphome/<device>.yaml`
- `esphome/device.package.yaml` -> `esphome/<device>.package.yaml`
- `esphome/screenshot.yaml` -> `esphome/<project>-screenshot.yaml`
- `homeassistant/packages.d/pkg.yaml` -> `homeassistant/packages.d/<pkg>.yaml`
- `homeassistant/packages.d/pkg.d/` -> `homeassistant/packages.d/<pkg>.d/`
- `homeassistant/wiring.d/wiring.pkg.{live,bench}.yaml` ->
  `homeassistant/wiring.d/wiring.<pkg>.{live,bench}.yaml`

For a second device, copy the entry/package pair, change the name and add both
lists (`DEVICES`, `DEVICES_CSV`); then duplicate the `build-`/`install-` CI
blocks with the matching `release-<device>` branch.

## Optional removals

| Absent feature | Delete |
|---|---|
| display/LVGL | `esphome/screenshot.yaml`, `screenshot*` targets, `SCREENSHOT_*` vars, screenshot line in MR template |
| Home Assistant | `homeassistant/`, `deploy-ha.sh`, `check-package-isolation.sh`, `homeassistant` target, `ha-isolation` CI job |
| `make homeassistant` | `HA_TARGET` lines in `makefile.conf`/Makefile |

## Verification after rendering

```sh
grep -rn '@@' .                         # must print nothing
./check-secrets.sh esphome/secrets.yaml # must pass
make help                               # devices and settings correct
make -n build <device>                  # shows the remote command
tar -tzf build/<device>.esphomebundle.tar.gz   # after a bundle build
sh -n check-secrets.sh prepare-secrets.sh check-package-isolation.sh deploy-ha.sh
```

Scan for personal data at the same time: no names, emails, IP addresses,
secret-manager project UUIDs, device serials or real entity ids. The only
infrastructure literals a generated repo should contain are
`gitlab.stefanbickel.com` and `esphome-builder.lab.stefanbickel.com` (plus the
runner image name in `.gitlab-ci.yml`).

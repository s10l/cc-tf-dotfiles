## What changed

<!-- Describe what this MR changes and why. Required. -->

## Screenshot

<!-- Attach build/screenshot.png from `make screenshot` when the change
     affects a display. Required for UI changes; write "n/a - no display" for
     firmware-only changes. -->

## Checklist

- [ ] Description above explains what changed and why
- [ ] Screenshot attached when the change affects the display
- [ ] MR pipeline is green. `validate`/`build` run when the MR touches
      `esphome/**`, `esphome.sh`, `secret_refs.yaml` or `check-secrets.sh`;
      they are skipped for `chore` / firmware-neutral MRs (`chore-guard` fails
      if a `chore` MR still changes `esphome/`). A release MR builds **only
      its own device**.
- [ ] `secret_refs.yaml` covers every `!secret` used by this change

<!--
Merging this MR into a release-* branch triggers a real OTA install on the
live device. Never push directly to release-*.
-->

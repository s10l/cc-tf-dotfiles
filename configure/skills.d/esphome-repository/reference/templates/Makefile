# ESPHome @@PROJECT@@ Makefile
#
# All firmware work (validate, compile, install, screenshot) runs remotely
# through ./esphome.sh, the CLI of the secure-esphome-builder service.
# Behaviour is controlled by makefile.conf (bundle mode, screenshot delay,
# cache) and secret_refs.yaml (where each !secret is stored).
#
# Devices are listed in DEVICES below. Every name needs esphome/<name>.yaml
# whose `esphome: name:` is exactly <name>; that chain decides which device a
# bundle is built for (see AGENTS.md, "Bundle filename contract").
#
# `make prepare-secrets` is HUMAN-ONLY: it is the one target that reads real
# secret values. Never run it from an AI agent/LLM (see the target itself).

CONF_FILE        ?= makefile.conf
SECRET_REFS_FILE ?= secret_refs.yaml
ESPHOME_DIR      ?= esphome
BUILD_DIR        ?= build

# Hand-filled source file for `make prepare-secrets` (HUMAN-ONLY). Defaults to
# the committed placeholder file, which must be filled in with real values
# first; afterwards it is rewritten with dummies again.
SECRETS_SRC ?= $(ESPHOME_DIR)/secrets.yaml

# Source configuration (USE_BUNDLE, SCREENSHOT_DELAY, ACCEPT_REMOTE_DRIFT,
# HA_TARGET, INFISICAL_*). Values there win over the fallbacks below.
-include $(CONF_FILE)

USE_BUNDLE          ?= 1
SCREENSHOT_DELAY    ?= 5
ACCEPT_REMOTE_DRIFT ?= 1

export ESPHOME_ACCEPT_REMOTE_DRIFT := $(ACCEPT_REMOTE_DRIFT)

# Remote builder CLI. The committed copy is pre-paired with the builder;
# this URL is only used when the file is missing.
ESPHOME_SH     ?= ./esphome.sh
ESPHOME_SH_URL ?= https://esphome-builder.lab.stefanbickel.com/esphome.sh

# Live Home Assistant config dir for `make homeassistant`
# (user@host:/path via ssh/scp, or an absolute local path).
HA_TARGET ?= @@HA_TARGET@@

# Space-separated device list. Single-device repos still list one entry, so
# `make validate` works without a device argument.
DEVICES ?= @@DEVICES@@

# Infisical coordinates used to build the reference URIs written to
# $(SECRET_REFS_FILE) by `make prepare-secrets` (HUMAN-ONLY). Seeded into
# $(CONF_FILE) on first use; PROJECT is the project UUID or slug and may be
# left empty until then.
INFISICAL_PROJECT     ?=
INFISICAL_ENV         ?= dev
INFISICAL_SECRET_PATH ?= devices

# OPTIONAL: LVGL/display screenshot config. Leave empty when the firmware has
# no display; the screenshot targets then fail with a clear message instead of
# being built. The file name must match its `esphome: name:` stem.
SCREENSHOT_CONFIG       ?= $(ESPHOME_DIR)/@@PROJECT@@-screenshot.yaml
SCREENSHOT_PAGE        ?= @@SCREENSHOT_PAGE@@
SCREENSHOT_OUTPUT      ?= $(BUILD_DIR)/screenshot.png
# OPTIONAL: a second page for MRs that change one specific screen.
SCREENSHOT_BOOST_PAGE  ?= @@SCREENSHOT_BOOST_PAGE@@
SCREENSHOT_BOOST_OUTPUT ?= $(BUILD_DIR)/screenshot-boost.png

space       := $(subst ,, )
DEVICE_LIST := $(strip $(DEVICES))

# Phony targets. Per-device targets are generated from DEVICE_LIST.
.PHONY: help configure validate build install screenshot screenshot-boost \
        check-secrets clean homeassistant prepare-secrets FORCE \
        $(addprefix validate-,$(DEVICE_LIST)) \
        $(addprefix build-,$(DEVICE_LIST)) \
        $(addprefix install-,$(DEVICE_LIST))

.DEFAULT_GOAL := help

# Prevent make from treating the device argument as a target
%:
	@:

# --secret KEY=REFERENCE pairs from secret_refs.yaml. Every non-empty
# "name: reference" line is passed; comments and surrounding quotes are
# stripped. References must not contain spaces.
SECRET_ARGS = $(shell if [ -f $(SECRET_REFS_FILE) ]; then awk '/^[A-Za-z0-9_]+:/ { k=$$0; sub(/:.*/, "", k); v=substr($$0, index($$0, ":")+1); sub(/^[ \t]+/, "", v); sub(/[ \t]+\043.*$$/, "", v); sub(/[ \t]+$$/, "", v); gsub(/^["\047]|["\047]$$/, "", v); if (v != "") printf "--secret %s=%s ", k, v }' $(SECRET_REFS_FILE); fi)

# esphome.sh input for a config file, honouring the global bundle flag.
esphome_input   = $(if $(strip $(1)),$(if $(filter 1,$(USE_BUNDLE)),--bundle $(BUILD_DIR)/$(notdir $(basename $(1))).esphomebundle.tar.gz,$(1)))
esphome_dep     = $(if $(strip $(1)),$(if $(filter 1,$(USE_BUNDLE)),$(BUILD_DIR)/$(notdir $(basename $(1))).esphomebundle.tar.gz))
esphome_display = $(if $(strip $(1)),$(if $(filter 1,$(USE_BUNDLE)),$(notdir $(basename $(1))).esphomebundle.tar.gz,$(1)))

help:
	@echo "ESPHome @@PROJECT@@ Makefile (remote builder via esphome.sh)"
	@echo ""
	@echo "Usage:"
	@echo "  make configure [USE_BUNDLE=0|1]  - Seed makefile.conf + secret_refs.yaml"
	@echo "  make validate <device>           - Validate the firmware configuration"
	@echo "  make build <device>              - Compile firmware to $(BUILD_DIR)/firmware_<device>.bin"
	@echo "  make install <device>            - Compile and OTA-upload (touches the live device)"
	@echo "  make screenshot                  - Render the UI screenshot ($(SCREENSHOT_PAGE))"
	@echo "  make screenshot-boost            - Render the second page ($(if $(SCREENSHOT_BOOST_PAGE),$(SCREENSHOT_BOOST_PAGE),unset))"
	@echo "  make check-secrets               - Assert secrets.yaml holds dummies only"
	@echo "  make homeassistant               - Copy homeassistant/ to HA_TARGET (interactive)"
	@echo "  make clean                       - Remove build artifacts"
	@echo ""
	@echo "HUMAN-ONLY (never run this from an AI agent/LLM):"
	@echo "  make prepare-secrets <device>    - Export a hand-filled $(SECRETS_SRC) to"
	@echo "                                     secrets.tmp.json + Infisical reference URIs"
	@echo ""
	@echo "Devices: $(subst $(space),  ,$(DEVICE_LIST))"
	@echo "A single-device repo may omit the device argument."
	@echo ""
	@echo "Bundle mode (global flag in $(CONF_FILE)):"
	@echo "  USE_BUNDLE=1  pack one device into <device>.esphomebundle.tar.gz and send it"
	@echo "  USE_BUNDLE=0  send the plain $(ESPHOME_DIR)/<device>.yaml (needs a git remote_base)"
	@echo ""
	@echo "Secrets: $(SECRET_REFS_FILE) maps each !secret name to its storage reference."
	@echo "Values live in the secret manager and are resolved server-side by the builder."
	@echo ""
	@echo "Current configuration:"
	@echo "  USE_BUNDLE=$(USE_BUNDLE)"
	@echo "  SCREENSHOT_DELAY=$(SCREENSHOT_DELAY)"
	@echo "  ACCEPT_REMOTE_DRIFT=$(ACCEPT_REMOTE_DRIFT)"
	@echo "  HA_TARGET=$(HA_TARGET)"
	@echo "  DEVICES=$(DEVICE_LIST)"

# Seed/update the config files. Idempotent: existing lines are never
# overwritten and never added twice; new !secret names are appended with an
# empty reference for the user to fill in.
configure:
	@if [ ! -f $(CONF_FILE) ]; then \
		echo "# Global settings for the Makefile (make configure seeds this file;" > $(CONF_FILE); \
		echo "# edit values by hand afterwards, existing lines are never overwritten)." >> $(CONF_FILE); \
		echo "" >> $(CONF_FILE); \
	fi
	@grep -q '^USE_BUNDLE' $(CONF_FILE) 2>/dev/null || \
		echo "USE_BUNDLE ?= $(USE_BUNDLE)" >> $(CONF_FILE)
	@grep -q '^SCREENSHOT_DELAY' $(CONF_FILE) 2>/dev/null || \
		echo "SCREENSHOT_DELAY ?= $(SCREENSHOT_DELAY) # in seconds" >> $(CONF_FILE)
	@grep -q '^ACCEPT_REMOTE_DRIFT' $(CONF_FILE) 2>/dev/null || \
		echo "ACCEPT_REMOTE_DRIFT ?= $(ACCEPT_REMOTE_DRIFT)" >> $(CONF_FILE)
	@grep -q '^HA_TARGET' $(CONF_FILE) 2>/dev/null || \
		{ echo "# live HA config dir (make homeassistant): user@host:/path or local path" >> $(CONF_FILE); \
		  echo "HA_TARGET ?= $(HA_TARGET)" >> $(CONF_FILE); }
	@grep -q '^INFISICAL_PROJECT' $(CONF_FILE) 2>/dev/null || \
		{ echo "# Infisical coordinates for $(SECRET_REFS_FILE) (make prepare-secrets;" >> $(CONF_FILE); \
		  echo "# HUMAN-ONLY). PROJECT is the project UUID or slug, ENV the environment," >> $(CONF_FILE); \
		  echo "# SECRET_PATH the parent folder the device secrets live under." >> $(CONF_FILE); \
		  echo "INFISICAL_PROJECT ?=" >> $(CONF_FILE); \
		  echo "INFISICAL_ENV ?= $(INFISICAL_ENV)" >> $(CONF_FILE); \
		  echo "INFISICAL_SECRET_PATH ?= $(INFISICAL_SECRET_PATH)" >> $(CONF_FILE); }
	@if [ ! -f $(SECRET_REFS_FILE) ]; then \
		echo "# One entry per !secret found under $(ESPHOME_DIR)/: name -> reference URI" > $(SECRET_REFS_FILE); \
		echo "# pointing to where the secret is stored (e.g. infisical://<project>/<env>/<path>)." >> $(SECRET_REFS_FILE); \
		echo "# NOT the secret itself. make configure appends missing names with an empty" >> $(SECRET_REFS_FILE); \
		echo "# value; fill them in by hand, or let make prepare-secrets (HUMAN-ONLY)" >> $(SECRET_REFS_FILE); \
		echo "# generate them from a hand-filled secrets.yaml. One flat name: reference" >> $(SECRET_REFS_FILE); \
		echo "# per line, no spaces in the reference." >> $(SECRET_REFS_FILE); \
		echo "" >> $(SECRET_REFS_FILE); \
	fi
	@find $(ESPHOME_DIR) -type f -name '*.yaml' -exec grep -hoE '!secret [A-Za-z0-9_]+' {} + 2>/dev/null | awk '{print $$2}' | sort -u | \
		while read -r s; do \
			grep -q "^$$s:" $(SECRET_REFS_FILE) 2>/dev/null || echo "$$s: " >> $(SECRET_REFS_FILE); \
		done
	@echo "Configured: USE_BUNDLE=$(USE_BUNDLE) ($(CONF_FILE)), secret keys in $(SECRET_REFS_FILE)"

# ---------------------------------------------------------------------------
# HUMAN-ONLY secret bootstrap - NOT FOR AI AGENTS / LLMs.
#
# This target reads a hand-filled $(SECRETS_SRC) that still holds REAL secret
# values, then:
#   - writes secrets.tmp.json, pretty printed as
#       { "device-name": { "secret_name": "secret_value" } }
#     for an Infisical import (secret names unchanged, no device prefix - the
#     device node already scopes them),
#   - rewrites $(SECRET_REFS_FILE) with
#       secret_name: infisical://<project>/<env>/<path>/<device-name>/secret_name
#   - replaces every value in $(ESPHOME_DIR)/secrets.yaml with a schema-valid dummy,
#   - seeds INFISICAL_* into $(CONF_FILE) when they are not configured yet.
#
# Why an agent must never run it: secrets.tmp.json holds the real values (it is
# gitignored, but present on disk until the human imports and deletes it) and
# only a human can complete the import. Agents work from $(SECRET_REFS_FILE)
# (references only) and must never read, print or handle a value. If a task
# seems to require real secrets, stop and ask the user to run this target
# themselves.
#
# Syntax:
#   make prepare-secrets <device>
#   make prepare-secrets <device> INFISICAL_PROJECT=<project-uuid>
#   make prepare-secrets <device> SECRETS_SRC=/path/to/hand-filled-secrets.yaml
# ---------------------------------------------------------------------------
prepare-secrets:
	@test -f ./prepare-secrets.sh || { echo "prepare-secrets: ./prepare-secrets.sh is missing"; exit 1; }
	@dev="$(word 2,$(MAKECMDGOALS))"; \
	if [ -z "$$dev" ] && [ "$(words $(DEVICE_LIST))" = "1" ]; then dev="$(DEVICE_LIST)"; fi; \
	case " $(DEVICE_LIST) " in \
		*" $$dev "*) \
			CONF_FILE="$(CONF_FILE)" \
			SECRET_REFS_FILE="$(SECRET_REFS_FILE)" \
			ESPHOME_DIR="$(ESPHOME_DIR)" \
			SECRETS_SRC="$(SECRETS_SRC)" \
			INFISICAL_PROJECT="$(INFISICAL_PROJECT)" \
			INFISICAL_ENV="$(INFISICAL_ENV)" \
			INFISICAL_SECRET_PATH="$(INFISICAL_SECRET_PATH)" \
			sh ./prepare-secrets.sh "$$dev" ;; \
		*) echo "Usage: make prepare-secrets <$(subst $(space),|,$(DEVICE_LIST))>"; exit 1 ;; \
	esac

# Download the remote builder CLI on first use
$(ESPHOME_SH):
	curl -fsSL $(ESPHOME_SH_URL) -o $(ESPHOME_SH)
	chmod +x $(ESPHOME_SH)

# Pack ONE device into <device>.esphomebundle.tar.gz. The archive is named
# after its device YAML and must carry exactly that YAML (and its package
# file) at the archive root - the sibling devices' entry YAMLs are excluded so
# a bundle can never resolve to another device's firmware. The entry's
# `esphome: name:` must equal the config stem: with no OTA host in
# common/ota.yaml, the name is what the builder OTA-addresses.
# secrets.yaml stays out; the builder resolves the reference URIs instead.
# check-secrets runs first (order-only) so a committed real value can never
# reach a bundle or a build.
$(BUILD_DIR)/%.esphomebundle.tar.gz: FORCE | check-secrets
	@stem=$*; \
	entry=$(ESPHOME_DIR)/$$stem.yaml; \
	test -f "$$entry" || { echo "no entry YAML for $$stem: $$entry"; exit 1; }; \
	grep -qE "^[[:space:]]*name:[[:space:]]*\"?$$stem\"?[[:space:]]*$$" "$$entry" || { echo "$$entry does not declare esphome name '$$stem'"; exit 1; }; \
	echo "creating $(notdir $@)..."; \
	mkdir -p $(BUILD_DIR); \
	files=$$(cd $(ESPHOME_DIR) && ls -A | awk -v c="$$stem" '/^[A-Za-z0-9_.-]+\.ya?ml$$/ && $$0 != c".yaml" && $$0 != c".package.yaml" { next } { print }'); \
	tar -czf $@ --exclude='.esphome' --exclude='.pio*' --exclude='secrets.yaml' -C "$(CURDIR)/$(ESPHOME_DIR)" $$files; \
	tar -tzf $@ | grep -qxF "$$stem.yaml" || { echo "bundle $(notdir $@) lost its entry $$stem.yaml at the archive root"; exit 1; }; \
	tar -tzf $@; \
	echo "$(notdir $@) created"

FORCE: ;

# Proof that $(ESPHOME_DIR)/secrets.yaml still holds dummy placeholders only.
# Every remote-facing target depends on it, so a real value can be neither
# bundled nor used by accident.
check-secrets:
	@./check-secrets.sh $(ESPHOME_DIR)/secrets.yaml

# ---------------------------------------------------------------------------
# Per-device targets. The static pattern rules below expand them from
# DEVICE_LIST; do not hardcode device names in this file.
# ---------------------------------------------------------------------------
$(addprefix validate-,$(DEVICE_LIST)): validate-%: check-secrets $(ESPHOME_SH) $(call esphome_dep,$(ESPHOME_DIR)/%.yaml)
	@echo "validating $(call esphome_display,$(ESPHOME_DIR)/$*.yaml)..."
	$(ESPHOME_SH) validate $(call esphome_input,$(ESPHOME_DIR)/$*.yaml) $(SECRET_ARGS)

$(addprefix build-,$(DEVICE_LIST)): build-%: check-secrets $(ESPHOME_SH) $(call esphome_dep,$(ESPHOME_DIR)/%.yaml)
	@mkdir -p $(BUILD_DIR)
	@echo "compiling $(call esphome_display,$(ESPHOME_DIR)/$*.yaml)..."
	$(ESPHOME_SH) compile $(call esphome_input,$(ESPHOME_DIR)/$*.yaml) $(SECRET_ARGS) -o $(BUILD_DIR)/firmware_$*.bin

$(addprefix install-,$(DEVICE_LIST)): install-%: check-secrets $(ESPHOME_SH) $(call esphome_dep,$(ESPHOME_DIR)/%.yaml)
	@echo "installing $(call esphome_display,$(ESPHOME_DIR)/$*.yaml)... (device $*)"
	$(ESPHOME_SH) install $(call esphome_input,$(ESPHOME_DIR)/$*.yaml) $(SECRET_ARGS)

# ---------------------------------------------------------------------------
# Screenshot targets (OPTIONAL - remove this section if the firmware has no
# display/LVGL). They render through the builder, so no local ESPHome is
# needed.
# ---------------------------------------------------------------------------
screenshot: check-secrets $(ESPHOME_SH) $(call esphome_dep,$(SCREENSHOT_CONFIG))
	@test -n "$(SCREENSHOT_CONFIG)" || { echo "screenshot: no SCREENSHOT_CONFIG set (no display/LVGL in this repo)"; exit 1; }
	@mkdir -p $(BUILD_DIR)
	@echo "rendering $(call esphome_display,$(SCREENSHOT_CONFIG))..."
	$(ESPHOME_SH) screenshot $(call esphome_input,$(SCREENSHOT_CONFIG)) $(SECRET_ARGS) \
		--delay $(SCREENSHOT_DELAY) \
		$(if $(SCREENSHOT_PAGE),--page $(SCREENSHOT_PAGE),) \
		-o $(SCREENSHOT_OUTPUT)

screenshot-boost: check-secrets $(ESPHOME_SH) $(call esphome_dep,$(SCREENSHOT_CONFIG))
	@test -n "$(SCREENSHOT_CONFIG)" || { echo "screenshot-boost: no SCREENSHOT_CONFIG set"; exit 1; }
	@test -n "$(SCREENSHOT_BOOST_PAGE)" || { echo "screenshot-boost: no SCREENSHOT_BOOST_PAGE set"; exit 1; }
	@mkdir -p $(BUILD_DIR)
	@echo "rendering $(call esphome_display,$(SCREENSHOT_CONFIG)) (page $(SCREENSHOT_BOOST_PAGE))..."
	$(ESPHOME_SH) screenshot $(call esphome_input,$(SCREENSHOT_CONFIG)) $(SECRET_ARGS) \
		--delay $(SCREENSHOT_DELAY) \
		--page $(SCREENSHOT_BOOST_PAGE) \
		-o $(SCREENSHOT_BOOST_OUTPUT)

# ---------------------------------------------------------------------------
# Home Assistant deployment (OPTIONAL - remove if this repo has no
# homeassistant/ directory).
# ---------------------------------------------------------------------------
homeassistant:
	@test -f deploy-ha.sh || { echo "homeassistant: no deploy-ha.sh in this repo"; exit 1; }
	@./deploy-ha.sh "$(HA_TARGET)"

# Clean build artifacts
clean:
	rm -rf $(BUILD_DIR) .esphome .pio*

# ---------------------------------------------------------------------------
# Device aliases: `make validate <device>` behaves like
# `make validate-<device>`. With exactly one device the argument may be
# omitted. MAKECMDGOALS carries every goal ("validate alpha"), so the device
# is the second word; the case whitelist stops typos from silently doing
# nothing (the catch-all rule above would otherwise accept them).
# ---------------------------------------------------------------------------
validate:
	@dev="$(word 2,$(MAKECMDGOALS))"; \
	if [ -z "$$dev" ] && [ "$(words $(DEVICE_LIST))" = "1" ]; then dev="$(DEVICE_LIST)"; fi; \
	case " $(DEVICE_LIST) " in \
		*" $$dev "*) $(MAKE) validate-$$dev ;; \
		*) echo "Usage: make validate <$(subst $(space),|,$(DEVICE_LIST))>"; exit 1 ;; \
	esac

build:
	@dev="$(word 2,$(MAKECMDGOALS))"; \
	if [ -z "$$dev" ] && [ "$(words $(DEVICE_LIST))" = "1" ]; then dev="$(DEVICE_LIST)"; fi; \
	case " $(DEVICE_LIST) " in \
		*" $$dev "*) \
			$(MAKE) validate-$$dev >/dev/null 2>&1 || true; \
			$(MAKE) build-$$dev ;; \
		*) echo "Usage: make build <$(subst $(space),|,$(DEVICE_LIST))>"; exit 1 ;; \
	esac

install:
	@dev="$(word 2,$(MAKECMDGOALS))"; \
	if [ -z "$$dev" ] && [ "$(words $(DEVICE_LIST))" = "1" ]; then dev="$(DEVICE_LIST)"; fi; \
	case " $(DEVICE_LIST) " in \
		*" $$dev "*) $(MAKE) install-$$dev ;; \
		*) echo "Usage: make install <$(subst $(space),|,$(DEVICE_LIST))>"; exit 1 ;; \
	esac

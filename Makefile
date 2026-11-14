PREFIX ?= /usr/local
DESTDIR ?=
CARGO ?= cargo
CARGO_TARGET_DIR ?= target
SUDO ?= $(if $(filter 0,$(shell id -u)),,sudo)

APPLICATION_ID := page.codeberg.wvhulle.Lazaret
RELEASE_BINARY := $(CARGO_TARGET_DIR)/release/lazaret
RELEASE_ADMIN_SERVICE_BINARY := $(CARGO_TARGET_DIR)/release/lazaret-clamav-admin
ADMIN_BUS_NAME := $(APPLICATION_ID).ClamavAdmin
SYSCONFDIR ?= /etc
COMPILE_SCHEMAS ?= yes
CLAMD_CONFIG ?= /etc/clamav/clamd.conf
CLAMD_UNIT ?= clamav-daemon.service
CLAMONACC_UNIT ?= clamav-clamonacc.service
CLAMD_LAYOUT_SUBSTITUTIONS := -e 's|@CLAMD_CONFIG@|$(CLAMD_CONFIG)|' -e 's|@CLAMD_UNIT@|$(CLAMD_UNIT)|' -e 's|@CLAMONACC_UNIT@|$(CLAMONACC_UNIT)|'
INSTALL_ROOT := $(DESTDIR)$(PREFIX)
SHARE_DIRECTORY := $(INSTALL_ROOT)/share
ADMIN_SERVICE_DIRECTORY := $(PREFIX)/libexec/lazaret
CONFIG_ROOT := $(DESTDIR)$(SYSCONFDIR)
SYSTEM_UNIT_DIRECTORY := $(INSTALL_ROOT)/lib/systemd/system
USER_UNIT_DIRECTORY := $(INSTALL_ROOT)/lib/systemd/user
SCHEMA_DIRECTORY := $(SHARE_DIRECTORY)/glib-2.0/schemas
LAZARET_SHARE_DIRECTORY := $(SHARE_DIRECTORY)/lazaret
DROP_IN_ROOT := $(CONFIG_ROOT)/systemd/system
ICON_DIRECTORY := $(SHARE_DIRECTORY)/icons/hicolor

INSTALLED_BINARY := $(INSTALL_ROOT)/bin/lazaret
INSTALLED_ADMIN_SERVICE_BINARY := $(DESTDIR)$(ADMIN_SERVICE_DIRECTORY)/lazaret-clamav-admin
INSTALLED_DATA_FILES := \
	$(SHARE_DIRECTORY)/metainfo/$(APPLICATION_ID).metainfo.xml \
	$(SHARE_DIRECTORY)/applications/$(APPLICATION_ID).desktop \
	$(ICON_DIRECTORY)/scalable/apps/$(APPLICATION_ID).svg \
	$(ICON_DIRECTORY)/symbolic/apps/$(APPLICATION_ID)-symbolic.svg \
	$(ICON_DIRECTORY)/symbolic/apps/$(APPLICATION_ID)-attention-symbolic.svg \
	$(SCHEMA_DIRECTORY)/$(APPLICATION_ID).gschema.xml \
	$(USER_UNIT_DIRECTORY)/lazaret.service
INSTALLED_ADMIN_SERVICE_FILES := \
	$(INSTALLED_ADMIN_SERVICE_BINARY) \
	$(SHARE_DIRECTORY)/polkit-1/actions/$(APPLICATION_ID).policy \
	$(SHARE_DIRECTORY)/dbus-1/system.d/$(ADMIN_BUS_NAME).conf \
	$(SHARE_DIRECTORY)/dbus-1/system-services/$(ADMIN_BUS_NAME).service \
	$(SYSTEM_UNIT_DIRECTORY)/lazaret-clamav-admin.service \
	$(SYSTEM_UNIT_DIRECTORY)/lazaret-settings-merge.service \
	$(SYSTEM_UNIT_DIRECTORY)/lazaret-reduction-expiry.service \
	$(SYSTEM_UNIT_DIRECTORY)/lazaret-reduction-expiry.timer \
	$(LAZARET_SHARE_DIRECTORY)/clamav-daemon-live-tuning.conf \
	$(LAZARET_SHARE_DIRECTORY)/clamav-clamonacc-live-tuning.conf
INSTALLED_DROP_INS := \
	$(DROP_IN_ROOT)/$(CLAMD_UNIT).d/lazaret.conf \
	$(DROP_IN_ROOT)/$(CLAMONACC_UNIT).d/lazaret.conf

ON_LIVE_SYSTEMD := [ -z "$(DESTDIR)" ] && [ -d /run/systemd/system ]
RELOAD_SYSTEMD_AND_DBUS := if $(ON_LIVE_SYSTEMD); then systemctl daemon-reload; systemctl reload dbus.service || true; fi

APT_PACKAGES := rustup build-essential pkg-config libgtk-4-dev libadwaita-1-dev libsystemd-dev libglib2.0-dev libglib2.0-bin clamav clamav-daemon clamdscan clamav-freshclam
DNF_PACKAGES := rustup gcc make pkgconf-pkg-config gtk4-devel libadwaita-devel systemd-devel glib2-devel clamav clamd clamav-update
PACMAN_PACKAGES := rustup base-devel gtk4 libadwaita systemd-libs glib2 clamav

.PHONY: deps build install uninstall install-live-tuning install-binary install-data install-metainfo install-clamav-admin install-user-service install-desktop-entry install-icons install-settings-schema

deps:
	@. /etc/os-release; \
	case " $$ID $$ID_LIKE " in \
	  *" debian "*|*" ubuntu "*) $(SUDO) apt-get update && $(SUDO) env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ca-certificates $(APT_PACKAGES) ;; \
	  *" fedora "*) $(SUDO) dnf install -y --setopt=install_weak_deps=False $(DNF_PACKAGES) ;; \
	  *" arch "*) $(SUDO) pacman -Syu --needed --noconfirm $(PACMAN_PACKAGES) ;; \
	  *) echo "No package list for '$$ID'; install the requirements in docs/install/from-source.md yourself." >&2; exit 1 ;; \
	esac
	@command -v $(CARGO) >/dev/null || echo "cargo is not on PATH yet: run 'rustup-init -y --default-toolchain none' and open a new shell."

build:
	LAZARET_CLAMD_CONFIG='$(CLAMD_CONFIG)' LAZARET_CLAMD_UNIT='$(CLAMD_UNIT)' LAZARET_CLAMONACC_UNIT='$(CLAMONACC_UNIT)' $(CARGO) build --release --locked --target-dir '$(CARGO_TARGET_DIR)' --package lazaret --package lazaret-clamav-admin

install: install-binary install-data install-clamav-admin
	$(RELOAD_SYSTEMD_AND_DBUS)
	if $(ON_LIVE_SYSTEMD); then systemctl enable --now lazaret-reduction-expiry.timer; fi

install-binary:
	install -Dm755 $(RELEASE_BINARY) $(INSTALLED_BINARY)

install-data: install-desktop-entry install-metainfo install-icons install-settings-schema install-user-service

install-metainfo:
	install -Dm644 data/desktop_integration/$(APPLICATION_ID).metainfo.xml.in $(SHARE_DIRECTORY)/metainfo/$(APPLICATION_ID).metainfo.xml

install-clamav-admin:
	install -Dm755 $(RELEASE_ADMIN_SERVICE_BINARY) $(INSTALLED_ADMIN_SERVICE_BINARY)
	install -Dm644 clamav_admin_service/system_files/$(APPLICATION_ID).policy $(SHARE_DIRECTORY)/polkit-1/actions/$(APPLICATION_ID).policy
	install -Dm644 clamav_admin_service/system_files/$(APPLICATION_ID).ClamavAdmin.conf $(SHARE_DIRECTORY)/dbus-1/system.d/$(ADMIN_BUS_NAME).conf
	install -Dm644 clamav_admin_service/system_files/$(APPLICATION_ID).ClamavAdmin.service $(SHARE_DIRECTORY)/dbus-1/system-services/$(ADMIN_BUS_NAME).service
	install -d $(SYSTEM_UNIT_DIRECTORY)
	sed 's|@ADMIN_SERVICE_PATH@|$(ADMIN_SERVICE_DIRECTORY)/lazaret-clamav-admin|' clamav_admin_service/system_files/lazaret-clamav-admin.service.in > $(SYSTEM_UNIT_DIRECTORY)/lazaret-clamav-admin.service
	sed -e 's|@ADMIN_SERVICE_PATH@|$(ADMIN_SERVICE_DIRECTORY)/lazaret-clamav-admin|' $(CLAMD_LAYOUT_SUBSTITUTIONS) clamav_admin_service/system_files/lazaret-settings-merge.service.in > $(SYSTEM_UNIT_DIRECTORY)/lazaret-settings-merge.service
	sed 's|@ADMIN_SERVICE_PATH@|$(ADMIN_SERVICE_DIRECTORY)/lazaret-clamav-admin|' clamav_admin_service/system_files/lazaret-reduction-expiry.service.in > $(SYSTEM_UNIT_DIRECTORY)/lazaret-reduction-expiry.service
	install -Dm644 clamav_admin_service/system_files/lazaret-reduction-expiry.timer $(SYSTEM_UNIT_DIRECTORY)/lazaret-reduction-expiry.timer
	install -d $(LAZARET_SHARE_DIRECTORY)
	sed $(CLAMD_LAYOUT_SUBSTITUTIONS) clamav_admin_service/system_files/clamav-daemon-live-tuning.conf.in > $(LAZARET_SHARE_DIRECTORY)/clamav-daemon-live-tuning.conf
	sed $(CLAMD_LAYOUT_SUBSTITUTIONS) clamav_admin_service/system_files/clamav-clamonacc-live-tuning.conf.in > $(LAZARET_SHARE_DIRECTORY)/clamav-clamonacc-live-tuning.conf
	install -d $(CONFIG_ROOT)/lazaret
	test -e $(CONFIG_ROOT)/lazaret/tunable-settings || install -m644 /dev/null $(CONFIG_ROOT)/lazaret/tunable-settings

install-user-service:
	install -d $(USER_UNIT_DIRECTORY)
	sed 's|@BINARY_PATH@|$(PREFIX)/bin/lazaret|' data/user_units/lazaret.service.in > $(USER_UNIT_DIRECTORY)/lazaret.service

install-desktop-entry:
	install -Dm644 data/desktop_integration/$(APPLICATION_ID).desktop.in $(SHARE_DIRECTORY)/applications/$(APPLICATION_ID).desktop

install-icons:
	install -Dm644 data/desktop_integration/icons/hicolor/scalable/apps/$(APPLICATION_ID).svg $(ICON_DIRECTORY)/scalable/apps/$(APPLICATION_ID).svg
	install -Dm644 data/desktop_integration/icons/hicolor/symbolic/apps/$(APPLICATION_ID)-symbolic.svg $(ICON_DIRECTORY)/symbolic/apps/$(APPLICATION_ID)-symbolic.svg
	install -Dm644 data/desktop_integration/icons/hicolor/symbolic/apps/$(APPLICATION_ID)-attention-symbolic.svg $(ICON_DIRECTORY)/symbolic/apps/$(APPLICATION_ID)-attention-symbolic.svg

install-settings-schema:
	install -Dm644 data/desktop_integration/$(APPLICATION_ID).gschema.xml $(SCHEMA_DIRECTORY)/$(APPLICATION_ID).gschema.xml
	test "$(COMPILE_SCHEMAS)" != yes || glib-compile-schemas $(SCHEMA_DIRECTORY)

install-live-tuning:
	install -Dm644 $(LAZARET_SHARE_DIRECTORY)/clamav-daemon-live-tuning.conf $(DROP_IN_ROOT)/$(CLAMD_UNIT).d/lazaret.conf
	install -Dm644 $(LAZARET_SHARE_DIRECTORY)/clamav-clamonacc-live-tuning.conf $(DROP_IN_ROOT)/$(CLAMONACC_UNIT).d/lazaret.conf
	$(RELOAD_SYSTEMD_AND_DBUS)
	if $(ON_LIVE_SYSTEMD); then systemctl try-restart $(CLAMD_UNIT) $(CLAMONACC_UNIT); fi

uninstall:
	if $(ON_LIVE_SYSTEMD); then systemctl disable --now lazaret-reduction-expiry.timer || true; fi
	rm -f $(INSTALLED_BINARY) $(INSTALLED_DATA_FILES) $(INSTALLED_ADMIN_SERVICE_FILES) $(INSTALLED_DROP_INS)
	rmdir --ignore-fail-on-non-empty $(DESTDIR)$(ADMIN_SERVICE_DIRECTORY) $(LAZARET_SHARE_DIRECTORY) $(dir $(INSTALLED_DROP_INS)) 2>/dev/null || true
	test "$(COMPILE_SCHEMAS)" != yes || ! test -d $(SCHEMA_DIRECTORY) || glib-compile-schemas $(SCHEMA_DIRECTORY)
	$(RELOAD_SYSTEMD_AND_DBUS)
	if $(ON_LIVE_SYSTEMD); then systemctl try-restart $(CLAMD_UNIT) $(CLAMONACC_UNIT); fi

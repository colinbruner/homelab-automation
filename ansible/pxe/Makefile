# PXE ansible operations
#
# Variables (all overridable on the command line):
#   TARGET   — PXE server IP or hostname
#   VERSION  — Talos version to download (reads vars/main.yml by default)
#   ARCHES   — space-separated architectures passed to the download script

TARGET  ?= 192.168.10.4
VERSION ?= $(shell awk '/talos_linux_version/ {print $$2}' vars/main.yml)
ARCHES  ?= amd64 arm64

.PHONY: help install download-talos

help:
	@echo "Usage: make <target> [TARGET=<ip>] [VERSION=<ver>] [ARCHES='amd64 arm64']"
	@echo ""
	@echo "Targets:"
	@echo "  install          Run the full PXE playbook against TARGET"
	@echo "  download-talos   Download Talos images on TARGET via ansible script module"
	@echo ""
	@echo "Current values:"
	@echo "  TARGET  = $(TARGET)"
	@echo "  VERSION = $(VERSION)"
	@echo "  ARCHES  = $(ARCHES)"

install:
	./install.sh "$(TARGET)"

# Copies scripts/download-talos-images.sh to TARGET and executes it there.
# The script is never persisted on the remote — ansible.builtin.script handles
# upload, execution, and cleanup automatically.
#
# Override examples:
#   make download-talos TARGET=192.168.10.4 VERSION=v1.12.4
#   make download-talos ARCHES=amd64
#   make download-talos VERSION=v1.12.4 ARCHES='amd64 arm64'
download-talos:
	ansible -u root -i "$(TARGET)," all \
	    -m ansible.builtin.script \
	    -a "scripts/download-talos-images.sh $(VERSION) $(ARCHES)"

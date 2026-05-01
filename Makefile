VERSION_FILE := Sources/xwt/Version.swift
INSTALL_DIR := $(HOME)/.local/bin

.PHONY: install

install:
	@current=$$(sed -n 's/let xwtVersion = "\(.*\)"/\1/p' $(VERSION_FILE)); \
	next=$$((current + 1)); \
	echo "let xwtVersion = \"$$next\"" > $(VERSION_FILE); \
	echo "📦 Version $$current → $$next"; \
	swift build -c release && \
	mkdir -p $(INSTALL_DIR) && \
	cp .build/release/xwt $(INSTALL_DIR)/xwt && \
	echo "✅ Installed xwt v$$next to $(INSTALL_DIR)/xwt"

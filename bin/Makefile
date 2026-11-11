.PHONY: all build check run install-dependencies

POWERSHELL ?= powershell.exe
BUILD_SCRIPT ?= ../tools/build.ps1

# Keep Visual Studio discovery and native build configuration in build.ps1.
all: build

build:
	$(POWERSHELL) -NoProfile -ExecutionPolicy Bypass -File "$(BUILD_SCRIPT)"

check:
	$(POWERSHELL) -NoProfile -ExecutionPolicy Bypass -File "$(BUILD_SCRIPT)" -Check

run:
	$(POWERSHELL) -NoProfile -ExecutionPolicy Bypass -File "$(BUILD_SCRIPT)" -Run

install-dependencies:
	$(POWERSHELL) -NoProfile -ExecutionPolicy Bypass -File "$(BUILD_SCRIPT)" -InstallDependencies

#!/usr/bin/env bash
# Invoked by the Homebrew cask: builds the app from the staged source
# and places it in /Applications, where Launchpad and Spotlight see it.
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG=release ./Scripts/build-app.sh
rm -rf /Applications/Unison.app
cp -R build/Unison.app /Applications/

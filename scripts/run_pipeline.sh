#!/usr/bin/env bash
# Convenience wrapper around the Makefile pipeline.
set -euo pipefail
cd "$(dirname "$0")/.."
make verify

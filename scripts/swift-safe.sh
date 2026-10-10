#!/usr/bin/env bash
set -euo pipefail

# Some environments inject command-line git config that forces
# safe.bareRepository=explicit, which breaks SwiftPM's bare-repo cache reuse.
while IFS='=' read -r name _; do
  case "$name" in
    GIT_CONFIG_COUNT|GIT_CONFIG_KEY_*|GIT_CONFIG_VALUE_*)
      unset "$name"
      ;;
  esac
done < <(env)

exec swift "$@"

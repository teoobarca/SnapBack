#!/bin/bash
# Exit 0 if Codex CLI appears installed on this machine.
[ -d "${CODEX_HOME:-$HOME/.codex}" ] || command -v codex >/dev/null 2>&1

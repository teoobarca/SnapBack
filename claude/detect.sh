#!/bin/bash
# Exit 0 if Claude Code appears installed on this machine.
[ -d "$HOME/.claude" ] || command -v claude >/dev/null 2>&1

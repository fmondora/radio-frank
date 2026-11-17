#!/bin/zsh
# Compila RadioBar in ~/bin/radiobar e lo riavvia nella barra dei menu.
set -e
cd "${0:A:h}"
swiftc -O -o ~/bin/radiobar main.swift -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker Info.plist
pkill -x radiobar || true
nohup ~/bin/radiobar >/dev/null 2>&1 &
echo "ok: ~/bin/radiobar avviato"

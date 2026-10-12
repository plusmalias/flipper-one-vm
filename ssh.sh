#!/bin/bash
# SSH into the running Flipper One VM (user "user", password "user"; run/vm_key if present).
cd "$(dirname "$0")"
key=(); [ -f run/vm_key ] && key=(-i run/vm_key)
exec ssh "${key[@]}" -p "${SSH_PORT:-2222}" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR user@127.0.0.1 "$@"

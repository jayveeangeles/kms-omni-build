#!/bin/bash

set -e

if ! whoami &> /dev/null; then
  if [ -w /etc/passwd ]; then
    echo "${USER_NAME:-default}:x:$(id -u):0:${USER_NAME:-default} user:/build/kms-omni-build:/sbin/nologin" >> /etc/passwd
  fi
fi

exec "$@"


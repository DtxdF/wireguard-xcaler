#!/bin/sh

LOCKFILE="/tmp/.wg.littlejet.lock"

lockf -ks "${LOCKFILE}" /scripts/run.sh "$@"

exit $?

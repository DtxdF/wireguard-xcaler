#!/bin/sh

BASEDIR=`dirname -- "$0"` || exit $?
BASEDIR=`realpath -- "${BASEDIR}"` || exit $?

# Defaults.
DEFAULT_DESTDIR="${DESTDIR}"
DEFAULT_JAIL="wg-xcaler"
DEFAULT_PREFIX="${PREFIX:-/usr/local}"

# See sysexits(3).
EX_OK=0
EX_USAGE=64
EX_DATAERR=65
EX_NOINPUT=66
EX_NOUSER=67
EX_NOHOST=68
EX_UNAVAILABLE=69
EX_SOFTWARE=70
EX_OSERR=71
EX_OSFILE=72
EX_CANTCREAT=73
EX_IOERR=74
EX_TEMPFAIL=75
EX_PROTOCOL=76
EX_NOPERM=77
EX_CONFIG=78

main()
{
    local _o

    local destdir="${DEFAULT_DESTDIR}"
    local jail="${DEFAULT_JAIL}"
    local prefix="${DEFAULT_PREFIX}"

    while getopts ":d:j:p:" _o; do
        case "${_o}" in
            d)
                DESTDIR="${OPTARG}"
                ;;
            j)
                jail="${OPTARG}"
                ;;
            p)
                prefix="${OPTARG}"
                ;;
            *)
                usage
                exit ${EX_USAGE}
                ;;
        esac
    done

    local script
    for script in "wg-xcaler" "wg-xcaler-jail" "wg-xcaler-ssh"; do
        echo "Installing '${script}' -> '${destdir}${prefix}/bin/${script}' ..."

        if ! install -m 555 "${BASEDIR}/${script}" "${destdir}${prefix}/bin/${script}"; then
            echo "Error installing '${script}'!"
            exit ${EX_SOFTWARE}
        fi
    done

    echo "WireGuard-xcaler jail is '${jail}'"

    if ! sed -i '' -Ee "s|%%JAIL%%|${jail}|g" "${destdir}${prefix}/bin/wg-xcaler"; then
        echo "Error configuring the 'wg-xcaler' script!"
        exit ${EX_IOERR}
    fi

    exit ${EX_OK}
}

usage()
{
    echo "usage: install.sh [-d <destdir>] [-j <jail>] [-p <prefix>]"
}

main "$@"

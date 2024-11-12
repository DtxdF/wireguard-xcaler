#!/bin/sh

EX_OK=0
EX_USAGE=64
EX_NOINPUT=66
EX_CANTCREAT=73

WG_ETC="/usr/local/etc/wireguard"
WG_PEERS="${WG_ETC}/peers"
WG_NETWORK_FILE="${WG_ETC}/.network"
WG_MTU_FILE="${WG_ETC}/.mtu"
WG_PERSISTENTKEEPALIVE_FILE="${WG_ETC}/.persistentkeepalive"
WG_IFACE="wg0"

. /scripts/lib.subr

umask 077

main()
{
    local cmd
    cmd="$1"

    if [ -z "${cmd}" ]; then
        usage
        exit ${EX_USAGE}
    fi

    shift

    case "${cmd}" in
        add|check|del|get-addr|get-network-addr|init|show) ${cmd} "$@" ;;
        *) usage; exit ${EX_USAGE} ;;
    esac
}

add()
{
    if [ $# -lt 1 ]; then
        usage
        exit ${EX_USAGE}
    fi

    local ident
    ident="$1"

    local ident_hash
    ident_hash=`mksum "${ident}"`

    local peerdir
    peerdir="${WG_PEERS}/${ident_hash}"

    if [ -f "${peerdir}/.done" ]; then
        err "${ident} (${ident_hash}): peer already added."
        exit ${EX_CANTCREAT}
    fi

    if [ -d "${peerdir}" ]; then
        rm -rf -- "${peerdir}" || exit $?
    fi

    mkdir -p -- "${peerdir}" || exit $?

    local network
    network=`get-network-addr` || exit $?

    local network_address
    network_address=`printf "%s" "${network}" | cut -d/ -f1 -s`

    local network_cidr
    network_cidr=`printf "%s" "${network}" | cut -d/ -f2 -s`

    local peerid
    peerid=`count_files "${WG_PEERS}"` || exit $?

    local errlevel

    local peerinfo
    peerinfo=`/netsum/netsum -a "${network_address}" -N "${peerid}" -n "${network_cidr}" 2>&1`

    errlevel=$?

    if [ ${errlevel} -ne 0 ]; then
        err "${peerinfo}"
        exit ${errlevel}
    fi

    local peer_address
    peer_address=`echo -e "${peerinfo}" | grep ADDRESS= | cut -d= -f2`

    printf "%s" "${peer_address}" > "${peerdir}/.address" || exit $?

    genkeys "${peerdir}"
    genpsk "${peerdir}"

    local server_publickey
    server_publickey=`getpubkey "${WG_ETC}"` || exit $?

    local client_publickey
    client_publickey=`getpubkey "${peerdir}"` || exit $?

    local client_privatekey
    client_privatekey=`getprivkey "${peerdir}"` || exit $?

    local psk
    psk=`getpsk "${peerdir}"` || exit $?

    endpoint=`head -1 -- "${WG_ETC}/.endpoint"` || exit $?

    cat << EOF > "${peerdir}/wg.conf" || exit $?
[Interface]
PrivateKey = ${client_privatekey}
Address = ${peer_address}/32
ListenPort = 51820
EOF

    if [ -f "${WG_MTU_FILE}" ]; then
        local mtu
        mtu=`head -1 -- "${WG_MTU_FILE}"` || exit $?

        echo "MTU = ${mtu}" >> "${peerdir}/wg.conf" || exit $?
    fi

    cat << EOF >> "${peerdir}/wg.conf" || exit $?
[Peer]
PresharedKey = ${psk}
PublicKey = ${server_publickey}
AllowedIPs = ${network}
Endpoint = ${endpoint}
EOF

    if [ -f "${WG_PERSISTENTKEEPALIVE_FILE}" ]; then
        local persistentkeepalive
        persistentkeepalive=`head -1 -- "${WG_PERSISTENTKEEPALIVE_FILE}"` || exit $?

        echo "PersistentKeepalive = ${persistentkeepalive}" >> "${peerdir}/wg.conf" || exit $?
    fi

    wg set "${WG_IFACE}" peer "${client_publickey}" preshared-key "${peerdir}/.psk" allowed-ips "${peer_address}/32"
    route_add "${peer_address}"

    touch -- "${peerdir}/.done" || exit $?

    return ${EX_OK}
}

route_add()
{
    route -q -n add -inet "$1/32" -interface "${WG_IFACE}"
}

check()
{
    if [ $# -lt 1 ]; then
        usage
        exit ${EX_USAGE}
    fi

    local ident
    ident="$1"

    local ident_hash
    ident_hash=`mksum "${ident}"`

    if [ -f "${WG_PEERS}/${ident_hash}/.done" ]; then
        return ${EX_OK}
    else
        return ${EX_NOINPUT}
    fi
}

del()
{
    if [ $# -lt 1 ]; then
        usage
        exit ${EX_USAGE}
    fi

    local ident
    ident="$1"

    local ident_hash
    ident_hash=`mksum "${ident}"`

    _check_ident "${ident_hash}"

    local peerdir
    peerdir="${WG_PEERS}/${ident_hash}"

    local client_publickey
    client_publickey=`getpubkey "${peerdir}"` || exit $?

    local peer_address
    peer_address=`head -1 -- "${peerdir}/.address"` || exit $?

    wg set wg0 peer "${client_publickey}" remove
    route_del "${peer_address}"

    rm -rf -- "${peerdir}" || exit $?

    return ${EX_OK}
}

route_del()
{
    route -q -n add -inet "$1/32" -interface "${WG_IFACE}"
}

get-addr()
{
    if [ $# -lt 1 ]; then
        usage
        exit ${EX_USAGE}
    fi

    local ident
    ident="$1"

    local ident_hash
    ident_hash=`mksum "${ident}"`

    _check_ident "${ident_hash}"

    local peerdir
    peerdir="${WG_PEERS}/${ident_hash}"

    if [ -f "${peerdir}/.address" ]; then
        head -1 -- "${peerdir}/.address" && echo

        exit $?
    fi

    return ${EX_OK}
}

get-network-addr()
{
    if [ -f "${WG_NETWORK_FILE}" ]; then
        head -1 -- "${WG_NETWORK_FILE}" && echo

        exit $?
    fi

    return ${EX_OK}
}

init()
{
    if [ ! -d "${WG_PEERS}" ]; then
        return 0
    fi

    ls -1 -- "${WG_PEERS}" | while IFS= read -r ident_hash; do
        peerdir="${WG_PEERS}/${ident_hash}"

        client_publickey=`getpubkey "${peerdir}"` || exit $?

        peer_address=`head -1 -- "${peerdir}/.address"` || exit $?

        wg set "${WG_IFACE}" peer "${client_publickey}" preshared-key "${peerdir}/.psk" allowed-ips "${peer_address}/32"
        route_add "${peer_address}"
    done

    exit $?
}

show()
{
    if [ $# -lt 1 ]; then
        usage
        exit ${EX_USAGE}
    fi

    local ident
    ident="$1"

    local ident_hash
    ident_hash=`mksum "${ident}"`

    _check_ident "${ident_hash}"

    local peerdir
    peerdir="${WG_PEERS}/${ident_hash}"

    if [ -f "${peerdir}/wg.conf" ]; then
        cat -- "${peerdir}/wg.conf" || exit $?
    fi

    return ${EX_OK}
}

_check_ident()
{
    local ident_hash
    ident_hash="$1"

    if [ ! -f "${WG_PEERS}/${ident_hash}/.done" ]; then
        err "${ident_hash}: peer cannot be found."
        exit 1
    fi
}

usage()
{
    cat << EOF
usage: run.sh add <ident>
       run.sh check <ident>
       run.sh del <ident>
       run.sh get-addr <ident>
       run.sh get-network-addr
       run.sh init
       run.sh show <ident>
EOF
}

main "$@"

#!/bin/sh

# Environment:
# - WG_ENDPOINT
# - WG_PERSISTENTKEEPALIVE (optional)
# - WG_NETWORK (172.16.0.0/12)
# - WG_PORT (51820)
# - WG_MTU (optional)

umask 077

. /scripts/lib.subr

WG_ETC="/usr/local/etc/wireguard"
WG_CONF="${WG_ETC}/wg0.conf"
WG_ENDPOINT_FILE="${WG_ETC}/.endpoint"
WG_MTU_FILE="${WG_ETC}/.mtu"
WG_PORT_FILE="${WG_ETC}/.port"
WG_PERSISTENTKEEPALIVE_FILE="${WG_ETC}/.persistentkeepalive"
WG_NETWORK_FILE="${WG_ETC}/.network"

if [ -n "${WG_PORT}" ] && ! chk_number "${WG_PORT}"; then
    err "${WG_PORT}: invalid port."
    exit 1
fi

if [ -n "${WG_NETWORK}" ]; then
    WG_NETADDR=`echo "${WG_NETWORK}" | cut -s -d/ -f1`
    if [ -z "${WG_NETADDR}" ]; then
        err "Network address must be defined!"
        exit 1
    fi

    if ! chk_basic_ip4 "${WG_NETADDR}"; then
        err "${WG_NETADDR}: invalid IPv4 address."
        exit 1
    fi

    WG_CIDR=`echo "${WG_NETWORK}" | cut -s -d/ -f2`
    if [ -z "${WG_CIDR}" ]; then
        err "CIDR must be defined!"
        exit 1
    fi

    if ! chk_number "${WG_CIDR}" || [ "${WG_CIDR}" -lt 0 -o "${WG_CIDR}" -gt 30 ]; then
        err "${WG_CIDR}: invalid CIDR."
        exit 1
    fi

    NETINFO=`/netsum/netsum -a "${WG_NETADDR}" -N 0 -n "${WG_CIDR}" 2>&1`

    errlevel=$?

    if [ ${errlevel} -ne 0 ]; then
        err "${NETINFO}"
        exit ${errlevel}
    fi

    WG_NETADDR=`echo -e "${NETINFO}" | grep NETWORK= | cut -d= -f2`
    WG_SERVER_ADDRESS=`echo -e "${NETINFO}" | grep ADDRESS= | cut -d= -f2`
    WG_NETWORK="${WG_NETADDR}/${WG_CIDR}"
else
    WG_SERVER_ADDRESS="172.16.0.1"
    WG_NETWORK="172.16.0.0/12"
fi

genkeys "${WG_ETC}"

WG_PRIVATEKEY=`getprivkey "${WG_ETC}"` || exit $?

WG_PORT="${WG_PORT:-51820}"

cat << EOF > "${WG_CONF}"
[Interface]
Address = ${WG_SERVER_ADDRESS}/32
ListenPort = ${WG_PORT}
PrivateKey = ${WG_PRIVATEKEY}
EOF

if [ -n "${WG_MTU}" ]; then
    if ! chk_number "${WG_MTU}"; then
        err "${WG_MTU}: invalid MTU."
        exit 1
    fi

    echo "MTU = ${WG_MTU}" >> "${WG_CONF}"

    printf "%s" "${WG_MTU}" > "${WG_MTU_FILE}"
fi

printf "%s" "${WG_ENDPOINT}" > "${WG_ENDPOINT_FILE}"
printf "%s" "${WG_NETWORK}" > "${WG_NETWORK_FILE}"
printf "%s" "${WG_PORT}" > "${WG_PORT_FILE}"

if [ -n "${WG_PERSISTENTKEEPALIVE}" ]; then
    printf "%s" "${WG_PERSISTENTKEEPALIVE}" > "${WG_PERSISTENTKEEPALIVE_FILE}"
fi

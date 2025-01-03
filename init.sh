#!/usr/bin/bash

set -eu

# requires env variables: HOST_INTERFACE, VLAN_ID, IP_ADDRESS
HOST_INTERFACE=${HOST_INTERFACE%$'\n'}
VLAN_ID=${VLAN_ID%$'\n'}
IP_ADDRESS=${IP_ADDRESS%$'\n'}

MAC_ADDRESS=$(ip -json link ls ${HOST_INTERFACE} | jq -r '.[0].address')

WWW_ROOT="/www"
CONF_DIR="/conf"
VPP_CONF="${CONF_DIR}/vpp.conf"
STARTUP_CONF="${CONF_DIR}/startup.conf"

echo "Starting VPP with HOST_INTERFACE ${HOST_INTERFACE}, MAC_ADDRESS ${MAC_ADDRESS}, VLAN_ID ${VLAN_ID}, IP_ADDRESS ${IP_ADDRESS}"
echo "Current capabilities are:"
capsh --print

create_vpp_conf() {
    cat <<EOF > ${VPP_CONF}
unix {
  nodaemon cli-listen /run/vpp/cli-vpp1.sock
  startup-config ${STARTUP_CONF}
}
api-segment { prefix vpp1 }
plugins { plugin dpdk_plugin.so { disable } }
EOF
}

print_vpp_conf() {
    echo "VPP conf is:"
    cat ${VPP_CONF}
}

create_startup_conf() {
    cat <<EOF > ${STARTUP_CONF}
create host-interface name ${HOST_INTERFACE}
set interface mac address host-${HOST_INTERFACE} ${MAC_ADDRESS}
set int state host-${HOST_INTERFACE} up
create sub-interfaces host-${HOST_INTERFACE} ${VLAN_ID}
set interface state host-${HOST_INTERFACE}.${VLAN_ID} up
set int ip address host-${HOST_INTERFACE}.${VLAN_ID} ${IP_ADDRESS}
http static server www-root ${WWW_ROOT} uri tcp://0.0.0.0/80 cache-size 512m
EOF
}

print_startup_conf() {
    echo "Startup conf is:"
    cat ${STARTUP_CONF}
}

create_tmp_www() {
    mkdir -p ${WWW_ROOT}
    echo "Welcome" > ${WWW_ROOT}/index.html
}

create_tmp_www
create_vpp_conf
print_vpp_conf
create_startup_conf
print_startup_conf

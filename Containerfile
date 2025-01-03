FROM registry.fedoraproject.org/fedora:41
RUN dnf copr enable nucleo/vpp-24.10 -y && yum install vpp vpp-plugins vpp-ext-deps jq iproute procps-ng -y
# RUN dnf install libbpf-tools -y
COPY init.sh /init.sh
RUN setcap 'cap_net_raw+eip cap_net_admin+eip cap_ipc_lock+eip cap_net_broadcast+eip' /usr/bin/vpp
RUN chmod +x init.sh

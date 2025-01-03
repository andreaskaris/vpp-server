# POC: AF_PACKET userspace networking with VPP

## Layout

This POC deploys a NetworkAttachmentDefinition inside namespace `vpp-server`. The NetworkAttachmentDefinition creates
a MACVLAN interface on top of one of the worker node interfaces. The MACVLAN interface is created inside the pod and
is named `macvlan0`. The pod's init container creates the necessary VPP configuration files for the main application
container. The main application container starts a VPP process which uses the configuration files which were created by
the init container.
The VPP application creates an AF_PACKET type socket on `macvlan0`. The AF_PACKET socket type creates a copy of each
packet that arrives on `macvlan0` and forwards it into the VPP application. The VPP application then implements a VLAN
in userspace, `host-macvlan0.<VLAN_ID>`, and assigns an IP address to `host-macvlan0.<VLAN_ID>`.
As a last step, the VPP application runs an HTTP server.

Let's say that the master interface is eth0, the VLAN ID is 123, and the IP address is 192.168.123.150/24. A client on the
same VLAN (123) and subnet (192.168.123.0/24) should be able to ping 192.168.123.150 and it should also be able to
run `curl http://192.168.123.150/index.html`.

```
                                          VLAN (via VPP)
                                                │                                 
               ┌────────────────────────────────┼────────────────────────────────┐
               │                                │                  WORKER NODE   │
               │                                │                                │
               │     ┌──────────────────────────┼──────────────────────────┐     │
               │     │                          │                    POD   │     │
               │     │                          │                          │     │
               │     │   ┌──────────────────────┼────────────────────┐     │     │
               │     │   │                      │     VPP application│     │     │
               │     │   ┌──────────────────┐   ▼   ┌────────────────┐     │     │
               │     │   │ host-macvlan0    ├───────┤host-macvlan0.123     │     │
               │     │   └──────┬───────────┘───────└────────────────┘     │     │
AF_PACKET  ────┼─────┼───────►  │                                          │     │
 socket        │     ├──────────┴───────────┐                              │     │
               │     │                      │                              │     │
               │     │      macvlan0        │                              │     │
               │     └──────────┬───────────┘──────────────────────────────┘     │
 MACVLAN   ────┼─────────────►  │                                                │
interface      │     ┌──────────┴───────────┐                                    │
               │     │                      │                                    │
               │     │ Host intf (e.g. eth0)│                                    │
               └─────└──────────────────────┘────────────────────────────────────┘
```

The application runs fully rootless and with minimum capabilities. In order to do so, it deploys a new SCC and binds
the pod's ServiceAccount to it.

## Deployment instructions

This POC can be deployed as follows:

```
make deploy MACVLAN_MASTER=<HOST MASTER INTERFACE> VLAN_ID=<VLAN ID ON TOP OF MACVLAN> IP_ADDRESS=<IP ADDRESS IN CONTAINER>
```

Where the 3 variables are as follows:

```
* MACVLAN_MASTER: The worker node's interface. The macvlan interface inside the pod will be the slave of this interface.
                  Configure by the NetworkAttachmentDefinition. The MACVLAN interface is passed into the container as
                  `macvlan0`.
* VLAN_ID: The VLAN ID that the VPP application is using on top of the MACVLAN interface.
* IP_ADDRESS: The IP address that the VPP application assigns to the VLAN.
```

In order to see all generated YAML files, you can run:
```
make kustomize
```

## Demonstration

Deploy the application (deployed here with the defaults, this must be adjusted for each lab environment):

```
$ make deploy
```

Check the pod:

```
$ oc get pods -n vpp-server
NAME                         READY   STATUS    RESTARTS   AGE
vpp-server-c6bb4fcbd-lhcbx   1/1     Running   0          37s
```

Check the MACVLAN definition. In the reference lab, the MACVLAN interface sits on top of the worker node's `eno8403np1`:

```
$ oc get net-attach-def -n vpp-server macvlan0 -o yaml
apiVersion: k8s.cni.cncf.io/v1
kind: NetworkAttachmentDefinition
metadata:
  annotations:
    kubectl.kubernetes.io/last-applied-configuration: |
      {"apiVersion":"k8s.cni.cncf.io/v1","kind":"NetworkAttachmentDefinition","metadata":{"annotations":{},"name":"macvlan0","namespace":"vpp-server"},"spec":{"config":"{\n\"cniVersion\": \"0.3.1\",\n\"name\": \"macvlan0\",\n\"type\": \"macvlan\",\n\"master\": \"eno8403np1\",\n\"linkInContainer\": false,\n\"mode\": \"bridge\"\n}"}}
  creationTimestamp: "2025-01-03T20:58:39Z"
  generation: 1
  name: macvlan0
  namespace: vpp-server
  resourceVersion: "12722445"
  uid: 7d11e871-6355-4673-84d3-123971119039
spec:
  config: |-
    {
    "cniVersion": "0.3.1",
    "name": "macvlan0",
    "type": "macvlan",
    "master": "eno8403np1",
    "linkInContainer": false,
    "mode": "bridge"
    }
```

The worker node's interface is not using promiscuous mode:

```
[root@worker01 ~]# ip -d --json link ls dev eno8403np1 | jq '.[0].promiscuity'
0
```


Connect to the pod and check the pod's networking. You can see here that the macvlan0 interface was created inside the
pod. (The IPv6 address was configured via auto-configuration and is not part of anything that we configured)

```
$ oc rsh -n vpp-server vpp-server-c6bb4fcbd-lhcbx 
Defaulted container "vpp-server" out of: vpp-server, init-vpp-server (init)
sh-5.2$ ip a
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
    inet6 ::1/128 scope host 
       valid_lft forever preferred_lft forever
2: eth0@if30223: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1400 qdisc noqueue state UP group default 
    link/ether 0a:58:0a:80:00:6a brd ff:ff:ff:ff:ff:ff link-netnsid 0
    inet 10.128.0.106/23 brd 10.128.1.255 scope global eth0
       valid_lft forever preferred_lft forever
    inet6 fe80::858:aff:fe80:6a/64 scope link 
       valid_lft forever preferred_lft forever
3: macvlan0@if3: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default 
    link/ether c6:b4:b5:74:11:88 brd ff:ff:ff:ff:ff:ff link-netnsid 0
    inet6 2600:52:7:18:c4b4:b5ff:fe74:1188/64 scope global dynamic mngtmpaddr 
       valid_lft 86379sec preferred_lft 14379sec
    inet6 fe80::c4b4:b5ff:fe74:1188/64 scope link 
       valid_lft forever preferred_lft forever
```

Note that the `macvlan0` interface is also not using promiscuous mode:

```
$ ip -d link ls dev macvlan0
3: macvlan0@if3: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP mode DEFAULT group default 
    link/ether c6:b4:b5:74:11:88 brd ff:ff:ff:ff:ff:ff link-netnsid 0 promiscuity 0 minmtu 68 maxmtu 9600 
    macvlan mode bridge bcqueuelen 1000 usedbcqueuelen 1000 numtxqueues 1 numrxqueues 1 gso_max_size 65536 gso_max_segs 65535 tso_max_size 65536 tso_max_segs 65535 gro_max_size 65536
```

Next, connect to the VPP application (run this inside the pod):

```
sh-5.2$ vppctl -s /run/vpp/cli-vpp1.sock
    _______    _        _   _____  ___ 
 __/ __/ _ \  (_)__    | | / / _ \/ _ \
 _/ _// // / / / _ \   | |/ / ___/ ___/
 /_/ /____(_)_/\___/   |___/_/  /_/    

vpp# 
```

And list the configuration:

```
vpp# show hardware-interfaces 
              Name                Idx   Link  Hardware
host-macvlan0                      1     up   host-macvlan0
  Link speed: unknown
  RX Queues:
    queue thread         mode      
    0     main (0)       interrupt 
  TX Queues:
    TX Hash: [name: hash-eth-l34 priority: 50 description: Hash ethernet L34 headers]
    queue shared thread(s)      
    0     no     0
  Ethernet address c6:b4:b5:74:11:88
  Linux PACKET socket interface v3
  FEATURES:
    qdisc-bpass-enabled
    cksum-gso-enabled
  RX Queue 0:
    block size:65536 nr:160  frame size:2048 nr:5120 next block:76
  TX Queue 0:
    block size:69206016 nr:1  frame size:67584 nr:1024 next frame:0
    available:1024 request:0 sending:0 wrong:0 total:1024
local0                             0    down  local0
  Link speed: unknown
  local
vpp# show interface 
              Name               Idx    State  MTU (L3/IP4/IP6/MPLS)     Counter          Count     
host-macvlan0                     1      up          9000/0/0/0     rx packets                  5936
                                                                    rx bytes                  563213
                                                                    drops                       5936
                                                                    ip4                          728
                                                                    ip6                          154
host-macvlan0.123                 2      up           0/0/0/0       rx packets                    24
                                                                    rx bytes                    1440
                                                                    drops                         24
local0                            0     down          0/0/0/0       
vpp# show int addr
host-macvlan0 (up):
host-macvlan0.123 (up):
  L3 192.168.123.150/24
local0 (dn):
vpp# 
```

As stated earlier, any packet to the `macvlan0` interface is copied into userspace via an AF_PACKET socket. VPP internally
picks up these packets and internally implements an HTTP server which listens on a userspace only VLAN implementation.

Here are the 2 configuration files that are used to configure VPP:

```
sh-5.2$ cat /conf/vpp.conf 
unix {
  nodaemon cli-listen /run/vpp/cli-vpp1.sock
  startup-config /conf/startup.conf
}
api-segment { prefix vpp1 }
plugins { plugin dpdk_plugin.so { disable } }
sh-5.2$ cat /conf/startup.conf 
create host-interface name macvlan0
set interface mac address host-macvlan0 c6:b4:b5:74:11:88
set int state host-macvlan0 up
create sub-interfaces host-macvlan0 123
set interface state host-macvlan0.123 up
set int ip address host-macvlan0.123 192.168.123.150/24
http static server www-root /www uri tcp://0.0.0.0/80 cache-size 512m
```

And `ss` shows that this is an AF_PACKET socket (`p_raw`):

```
sh-5.2$ ss -f link -anp
Netid          State           Recv-Q          Send-Q                   Local Address:Port                       Peer Address:Port         Process          
p_raw          UNCONN          0               0                                    *:macvlan0                               *                            
```

The application runs rootless and only uses the necessary capabilities:

```
sh-5.2$ id
uid=10000(10000) gid=10000 groups=10000,1001170000
sh-5.2$ ps aux
USER         PID %CPU %MEM    VSZ   RSS TTY      STAT START   TIME COMMAND
10000          1 99.5  0.9 18283924 1259620 ?    Rs   20:58  11:50 vpp -c /conf/vpp.conf
10000          7  0.0  0.0   4392  3992 pts/0    Ss   21:00   0:00 /bin/sh
10000         25  0.0  0.0   5420  3216 pts/0    R+   21:10   0:00 ps aux
sh-5.2$ getpcaps 1
1: cap_net_broadcast,cap_net_admin,cap_net_raw,cap_ipc_lock=ep
```

Now, connect to a client system and ping and/or curl to the pod. The first few attempts may actually fail, but right
after that, everything will work:

```
[root@client ~]# curl http://192.168.123.150/index.html
^C
[root@client ~]# curl http://192.168.123.150/index.html
^C
[root@client ~]# ip neigh | grep 123.150
192.168.123.150 dev eth0.123 FAILED 
[root@client ~]# curl http://192.168.123.150/index.html
Welcome
[root@client ~]# ping -c1 -W1 192.168.123.150
PING 192.168.123.150 (192.168.123.150) 56(84) bytes of data.
64 bytes from 192.168.123.150: icmp_seq=1 ttl=64 time=2.13 ms

--- 192.168.123.150 ping statistics ---
1 packets transmitted, 1 received, 0% packet loss, time 0ms
rtt min/avg/max/mdev = 2.132/2.132/2.132/0.000 ms
```

You can remove the application with:

```
make undeploy
```

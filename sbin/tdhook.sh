#!/bin/bash
if [ "$1" == "session.up" ]; then
    ifconfig $2 hw ether $MACADDR
    dhcpcd -4L $2
    ip route add default table uplink dev uplink
else
    echo "Uncatched Hook: $*"
fi

#!/bin/bash

_term() {
    echo "Caught SIGTERM signal!"
    kill -TERM $children 2>/dev/null
}

trap _term SIGTERM

for i in `seq 3 -1 1`; do
    echo -ne "Starting in $i...   \r"
    sleep 1
done
echo "Starting...        "

hostname $HOSTNAME

BRIDGES=( digger1446 digger1462 digger1312 )

OLSR_IF_MESH=()
OLSR_IF_ETHER=()
OLSR_HNA=()

export IP=`ip --brief addr show dev eth0 | sed 's/ \+/ /g' | cut -d' ' -f3 | cut -d/ -f1`
echo "IP: $IP"

ip rule add lookup olsr prio 1000
iptables -t nat -A POSTROUTING -o uplink -j MASQUERADE

calcnet() {
    IFS=. read -r i1 i2 i3 i4 <<< "$1"
    IFS=. read -r m1 m2 m3 m4 <<< "$2"
    printf "%d.%d.%d.%d\n" "$((i1 & m1))" "$((i2 & m2))" "$((i3 & m3))" "$((i4 & m4))"
}
fullips() {
    s=""
    while [ ! -z "$1" ]; do
        octs=`echo "$1" | sed 's/\./ /g' | wc -w`
        if [ $octs -lt 4 -a "$1" == "`echo $1 | sed 's/[^0-9\.]//g'`" ];then
            s="$s ${IP_BASE}$1"
        else
            s="$s $1"
        fi
        shift
    done
    echo $s
}

### Tunneldigger
if [ ! -z "$DIGGERIPS" -a ! -z "$DIGGERDHCP" ]; then
    envsubst < /etc/l2tp_broker.conf.prep > /etc/l2tp_broker.conf
    source "/usr/local/sbin/bridge_functions.sh"
    args="-d -p0"
    args="$args -F `fullips $DIGGERDHCP | sed 's/\s/,/g'`"
    DIGGERIPS=( $DIGGERIPS )
    for ((i=0;i<${#BRIDGES[@]};++i)); do
        BIP=`fullips ${DIGGERIPS[i]}`
        echo "Creating bridge interface ${BRIDGES[i]} with IP $BIP..."
        ensure_bridge "${BRIDGES[i]}"
        ifconfig "${BRIDGES[i]}" "$BIP" netmask "${DIGGERIPS[-1]}"
        ip route add "`calcnet ${BIP} ${DIGGERIPS[-1]}`/${DIGGERIPS[-1]}" table nets dev "${BRIDGES[i]}" src ${BIP}
        args="$args -i ${BRIDGES[i]}"
        OLSR_IF_MESH+=( ${BRIDGES[i]} )
    done
    OLSR_HNA+=("`calcnet $( fullips ${DIGGERIPS[0]} ) ${DIGGERIPS[-1]}` ${DIGGERIPS[-1]}")
    echo "Starting dnsmasq..."
    dnsmasq $args &
    children="$children $!"

    echo "Starting tunneldigger_broker..."
    python -m tunneldigger_broker.main /etc/l2tp_broker.conf &
    children="$children $!"
fi

### OpenVPN
export CAFILE=`ls /etc/openvpn/certs/*.ca | head -n1`
export DHFILE=`ls /etc/openvpn/certs/*.dh | head -n1`
export CERTFILE=`ls /etc/openvpn/certs/*.crt | head -n1`
export KEYFILE=`ls /etc/openvpn/certs/*.key | head -n1`
if [ ! -z "$OPENVPNNET" -a -s "$CAFILE" -a -s "$DHFILE" -a -s "$CERTFILE" -a -s "$KEYFILE" ];then
    OPENVPNNET=`fullips $OPENVPNNET`
    envsubst < /etc/openvpn/pdmvpn.conf.prep > /etc/openvpn/pdmvpn.conf
    openvpn --mktun --dev-type tap --dev openvpn
    ip link set dev openvpn up
    ensure_policy from all iif openvpn lookup nets prio 2000
    ensure_policy from all iif openvpn lookup uplink prio 5000
    openvpn --config /etc/openvpn/pdmvpn.conf &
    children="$children $!"
    OLSR_IF_MESH+=( openvpn )
    NET=`calcnet ${OPENVPNNET}`
    OPENVPNNET=( $OPENVPNNET )
    ip route add "${NET}/${DIGGERIPS[-1]}" table nets dev openvpn
    OLSR_HNA+=("${NET} ${OPENVPNNET[-1]}")
fi

### L2TP Server-to-Server
if [ ! -z "$S2S_IP" -a ! -z "$S2S_ID" ];then
    S2S_IP=( $S2S_IP )
    ensure_bridge "s2s"
    ifconfig s2s "`fullips ${S2S_IP[0]}`" netmask "${S2S_IP[1]}"
    OLSR_IF_ETHER+=( s2s )
    NET=`calcnet $( fullips ${S2S_IP[0]} ) ${S2S_IP[1]}`
    ip route add "${NET}/${S2S_IP[1]}" table nets dev s2s
    OLSR_HNA+=("${NET} ${S2S_IP[1]}")
    for TID in `seq 11 19`; do
        p="S2S_$TID"
        if [ ! -z "${!p}" -a "$TID" -ne "$S2S_ID" ]; then
            RIP=`gethostip "${!p}" | cut -d' ' -f2`
            ip l2tp add tunnel remote ${RIP} local ${IP} tunnel_id ${TID} peer_tunnel_id ${S2S_ID} encap udp udp_sport 17${TID} udp_dport 1701 udp_csum on
            ip l2tp add session name s2s_${TID} tunnel_id ${TID} session_id ${TID} peer_session_id ${S2S_ID}
            iptables -t nat -I PREROUTING 1 -i eth0 -p udp -s ${RIP} -d ${IP} --sport 1701 --dport 1701 -j DNAT --to-destination ${IP}:17${TID}
            iptables -t nat -I POSTROUTING 1 -o eth0 -p udp -s ${IP} -d ${RIP} --sport 17${TID} --dport 1701 -j SNAT --to-source ${IP}:1701
            ip link set dev s2s_${TID} up
            brctl addif s2s s2s_${TID}
        fi
    done
fi

### Tunneldigger uplink
if [ ! -z "$TDUPLINKS" ];then
    MACADDR="fe"
    for byte in 2 3 4 5 6; do
        MACADDR=$MACADDR`dd if=/dev/urandom bs=1 count=1 2> /dev/null | hexdump -e '1/1 ":%02x"'`
    done
    # tunneldigger client setup
    UUID=$MACADDR
    for byte in 7 8 9 10; do
        UUID=$UUID`dd if=/dev/urandom bs=1 count=1 2> /dev/null | hexdump -e '1/1 ":%02x"'`
    done

    args="-f -u $UUID -i uplink -a -s /usr/local/sbin/tdhook.sh"
    for broker in $TDUPLINKS; do
        args="$args -b $broker"
    done

    echo "Starting tunneldigger_client..."
    MACADDR=$MACADDR tunneldigger $args &
    children="$children $!"
fi

### OLSR
envsubst < /etc/olsrd.conf.prep > /etc/olsrd.conf
for p in /usr/local/lib/olsrd_*.so.*; do
    p=`basename $p`
    px=`echo $p | sed 's/\.so\.[0-9\.]\+/.so.x/g'`
    sed -i "s/$px/$p/g" /etc/olsrd.conf
done
if [ "$OLSR_DROPHNA" == "1" ]; then
    for p in /usr/local/lib/olsrd_drophna.so.*; do
        echo -e "LoadPlugin \"`basename $p`\"\n{\n}\n" >> /etc/olsrd.conf
    done
fi

(
    echo -e "Hna4\n{"
    for hna in "${OLSR_HNA[@]}"; do
        echo -e "\t$hna"
    done
    echo -e "}\n"
) >> /etc/olsrd.conf

for i in "${OLSR_IF_MESH[@]}"; do
    p="OLSR_LQMULT_$i"
    lqmult=${!p}
    if [ -z $lqmult ]; then lqmult=$OLSR_LQMULT_MESH; fi
    if [ -z $lqmult ]; then lqmult=$OLSR_LQMULT; fi
    (
        echo -e "Interface \"$i\"\n{"
    if [ ! -z $lqmult ]; then
        echo -e "\tLinkQualityMult default $lqmult"
    fi
        echo -e "\tMode \"mesh\""
        echo -e "}\n"
    ) >> /etc/olsrd.conf
done

for i in "${OLSR_IF_ETHER[@]}"; do
    p="OLSR_LQMULT_$i"
    lqmult=${!p}
    if [ -z $lqmult ]; then lqmult=$OLSR_LQMULT_ETHER; fi
    if [ -z $lqmult ]; then lqmult=$OLSR_LQMULT; fi
    (
        echo -e "Interface \"$i\"\n{"
    if [ ! -z $lqmult ]; then
        echo -e "\tLinkQualityMult default $lqmult"
    fi
        echo -e "\tMode \"ether\""
        echo -e "}\n"
    ) >> /etc/olsrd.conf
done

olsrd -f /etc/olsrd.conf -nofork &
children="$children $!"

wait $children

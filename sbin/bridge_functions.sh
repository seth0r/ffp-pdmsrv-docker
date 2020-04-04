calcnet() {
    IFS=. read -r i1 i2 i3 i4 <<< "$1"
    IFS=. read -r m1 m2 m3 m4 <<< "$2"
    printf "%d.%d.%d.%d\n" "$((i1 & m1))" "$((i2 & m2))" "$((i3 & m3))" "$((i4 & m4))"
}

ensure_policy()
{
  ip rule del $* 2>/dev/null
  ip rule add $*
}

ensure_bridge()
{
  local brname="$1"
  brctl addbr $brname 2>/dev/null
  
  if [[ "$?" == "0" ]]; then
    echo "Created bridge interface ${brname}."
    # Bridge did not exist before, we have to initialize it
    ip link set dev $brname up
    # TODO The IP address should probably not be hardcoded here?
#    ip addr add 10.254.0.2/16 dev $brname
    # TODO Policy routing should probably not be hardcoded here?
#    ensure_policy from all iif $brname lookup olsr prio 1000
    ensure_policy from all iif $brname lookup nets prio 2000
    ensure_policy from all iif $brname lookup uplink prio 5000
    # Disable forwarding between bridge ports
    ebtables -A FORWARD --logical-in $brname -j DROP

    for $BIP in ${DIGGERIPS[@]::${#DIGGERIPS[@]}-1}; do
        ip -f inet addr show | grep "$BIP/" && continue

        ifconfig "$brname" "$BIP" netmask "${DIGGERIPS[-1]}"
        ip route add "`calcnet ${BIP} ${DIGGERIPS[-1]}`/${DIGGERIPS[-1]}" table nets dev "$brname" src ${BIP}
    done
    killall olsrd
  fi
}


#!/bin/bash

_term() {
    echo "Caught SIGTERM signal!"
    kill -TERM $children 2>/dev/null
}

trap _term SIGTERM

hostname $HOSTNAME

IP=`ip --brief addr show dev eth0 | sed 's/ \+/ /g' | cut -d' ' -f3 | cut -d/ -f1`
sed "s/%IP%/${IP}/g" /etc/l2tp_broker.cfg.prep > /etc/l2tp_broker.cfg

python -m tunneldigger_broker.main /etc/l2tp_broker.cfg &
children="$children $!"

wait $children

#!/bin/bash
if [  -f "$1" ]; then
    while read l; do
        if [ "`echo $l | grep "^S2S_"`" != "" ]; then
            export "$l"
        fi
    done < $1

    if [ ! -z "$S2S_IP" -a ! -z "$S2S_ID" ];then
        for TID in `seq 11 19`; do
            p="S2S_$TID"
            if [ ! -z "${!p}" -a "$TID" -ne "$S2S_ID" ]; then
                echo $TID
            fi
        done
    fi
fi

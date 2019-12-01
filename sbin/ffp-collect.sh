#!/bin/bash

## script variables
EXCLUDE_DEVICES=""
UPLOADURL="http://monitor.freifunk-potsdam.de/fff"
SCRIPTVERSION='19.11-srv'

COLLDIR=/tmp/collstat

source /tmp/docker.env

if [ ! -d "$COLLDIR" ]; then
	mkdir "$COLLDIR"
fi
time=`date +%s`

xuptime() {
	echo "<uptime>"
	uptime
	echo "</uptime>"
}

xifconfig() {
	echo "<ifconfig>"
	for dev in `ls /sys/class/net/` ; do
		ndev=`echo $dev | sed 's/\./_/g'`
		if [ "`echo $EXCLUDE_DEVICES | grep -w $ndev`" = "" ] ; then
			echo "<$ndev>"
			ifconfig $dev | sed 's/[<>]/ /g'
			echo "</$ndev>"
		fi
	done
	echo "</ifconfig>"
}

xdhcp() {
	echo "<dhcp_leases>"
	cut -d' ' -f1,3 /var/lib/misc/dnsmasq.leases
	echo "</dhcp_leases>"
}

xlinks() {
	echo "<links>"
        curl 127.0.0.1:9090/links 2>/dev/null
	echo "</links>"
}

xtop() {
	echo "<top>"
	sleep 3
	top -b -n1 | head -n5
	echo "</top>"
}

xdf() {
	echo "<df>"
	df | grep -v "/etc/hosts"
	echo "</df>"
}

xconn() {
	echo "<conn>"
	cut -c12-20 /proc/net/nf_conntrack | sort | uniq -c
	echo "</conn>"
}

xbrctl() {
	echo "<brctl>"
	brctl show
	echo "</brctl>"
}

xroutes() {
	echo "<tunnel>"
	ip tunnel show
	echo "</tunnel>"
	echo "<routes>"
	ip route show table main | grep default
	ip route show table ffuplink 2> /dev/null | grep default
	ip route show table olsr-default | grep default
	ip route show table olsr-tunnel | grep default
	echo "</routes>"
}

xoptions() {
	echo "<options>"
	echo "option latitude $LAT"
	echo "option longitude $LON"
	echo "option location $HOSTHOSTNAME"
	echo "option mail $CONTACT"
	echo "</options>"
}

xsystem() {
	echo "<system>"
	echo "firmware : $GIT_COMMIT"
	echo "machine  : Docker"
	echo "</system>"
}

echocrlf() {
	echo -n "$1"
	echo -e "\r"
}

plog() {
        MSG="$*"
        echo ${MSG}
        logger -t $0 ${MSG}
}

fupload() {
	if [ -f "$1" ]; then
                curl -F f=@${1} ${UPLOADURL} 2>/dev/null
	fi
}

collect() {
	m=`date +%-M`
	f=$COLLDIR/$time.cff
	echo "<ffstat host='$HOSTNAME' time='$time' ver='$SCRIPTVERSION'>" > $f
	(
		xtop
		xuptime
		xdhcp
		xlinks
		xconn
		xroutes
		if [ $(( $m % 5 )) -eq 0 ]; then
			xsystem
			xoptions
			xdf
			xbrctl
			xifconfig
		fi
	) >> $f
	echo "</ffstat>" >> $f
	mv $f $f.xml
	rm -r $COLLDIR/*.cff 2> /dev/null
}

upload_rm() {
	if [ -f "$1" ]; then
		plog "uploading $1..."
		res=`fupload $1 | tail -n1`
		if [ "$res" = "success" ]; then
			rm $1
		fi
	fi
}

upload_rm_or_gzip() {
	if [ -f "$1" ]; then
		plog "uploading $1..."
		res=`fupload $1 | tail -n1`
		if [ "$res" = "success" ]; then
			rm $1
		else
			plog "uploading $1 failed, zipping..."
			gzip $1 2> /dev/null
		fi
	fi
}

upload() {
	for f in $COLLDIR/*.cff.xml.gz; do
		upload_rm $f &
		sleep 1
	done
	for f in $COLLDIR/*.cff.xml; do
		upload_rm_or_gzip $f &
		sleep 1
	done
	wait
	filled=`df $COLLDIR | tail -n1 | sed -E 's/^.* ([0-9]+)%.*$/\1/g'`
	while [ $filled -gt 50 ]; do
		f=`ls -lrc $COLLDIR | sed 's/ \+/\t/g' | cut -f9 | head -n1`
		if [ "$f" != "" ]; then
			rm "$COLLDIR/$f"
		else
			break
		fi
	done
}

$1

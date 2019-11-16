FROM       debian:stable
MAINTAINER Seth0r "https://github.com/seth0r"

ARG PKGS="\
    vim procps bsdmainutils gettext syslinux-utils \
    net-tools iptables iproute2 bridge-utils dhcpcd5 dnsmasq openvpn \
    libnfnetlink0 libnetfilter-conntrack3 libasyncns0 libnl-3-200 libnl-genl-3-200 bison flex \
    python python-setuptools python-cffi python-netfilter "

ARG BUILDPKGS="\
    build-essential cmake git \
    python-dev libnfnetlink-dev libnetfilter-conntrack-dev libffi-dev libevent-dev \
    libnl-genl-3-dev libnl-3-dev libasyncns-dev libgps-dev"

RUN apt-get update
RUN apt-get dist-upgrade -y

RUN apt-get install -y $PKGS

RUN apt-get install -y $BUILDPKGS

RUN git clone https://github.com/wlanslovenija/tunneldigger.git /tunneldigger && \
    cd /tunneldigger/broker && python setup.py install && \
    cd /tunneldigger/client && cmake . && make && make install && \
    rm -r /tunneldigger

RUN git clone -b drophna https://github.com/freifunk-berlin/olsrd.git /olsrd && \
    cd /olsrd && make build_all && make install_all && \
    rm -r /olsrd

#RUN apt-get purge -y $BUILDPKGS && apt-get -y autoremove

RUN apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

COPY .vimrc /root/.vimrc

COPY l2tp_broker.conf /etc/l2tp_broker.conf.prep
COPY openvpn.conf /etc/openvpn/pdmvpn.conf.prep

RUN echo "111     olsr" >> /etc/iproute2/rt_tables && \
    echo "112     olsr-default" >> /etc/iproute2/rt_tables && \
    echo "113     olsr-tunnel" >> /etc/iproute2/rt_tables && \
    echo "114     uplink" >> /etc/iproute2/rt_tables
COPY olsrd.conf /etc/olsrd.conf.prep

COPY sbin/* /usr/local/sbin/
RUN chmod +x /usr/local/sbin/*
CMD ["/usr/local/sbin/run.sh"]

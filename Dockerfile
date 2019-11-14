FROM       debian:stable
MAINTAINER Seth0r "https://github.com/seth0r"

RUN apt-get update
RUN apt-get dist-upgrade -y

RUN apt-get install -y openvpn tor python vim git procps \
    net-tools iptables iproute2 bridge-utils libnfnetlink0 libnetfilter-conntrack3 \
    python-setuptools build-essential python-cffi python-netfilter \
    python-dev libnfnetlink-dev libnetfilter-conntrack-dev libffi-dev libevent-dev

RUN apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

RUN git clone https://github.com/wlanslovenija/tunneldigger.git && cd tunneldigger/broker && python setup.py install && rm -r /tunneldigger

COPY l2tp_broker.cfg /etc/l2tp_broker.cfg.prep

RUN echo "123     mesh" >> /etc/iproute2/rt_tables

COPY scripts/*.sh /usr/local/sbin/
RUN chmod +x /usr/local/sbin/*.sh
CMD ["/usr/local/sbin/run.sh"]

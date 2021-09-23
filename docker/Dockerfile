FROM debian:buster-slim

RUN apt update && apt install inotify-tools sshpass python3-six wget curl jq -y  && apt clean

ENV YQ_VER=v4.14.2 BINARY=yq_linux_amd64
RUN wget https://github.com/mikefarah/yq/releases/download/${YQ_VER}/${BINARY} -O /usr/bin/yq && chmod +x /usr/bin/yq

COPY sources.list /etc/apt/sources.list
COPY trusted.gpg /etc/apt/trusted.gpg

RUN apt update && apt install -y openssh-server \
    python3-apt ifupdown2 python-apt iputils-ping tcpdump traceroute bridge-utils iptables frr

COPY entrypoint.sh /
ENTRYPOINT ["/entrypoint.sh"]

FROM ubuntu:24.04

ENV container=docker
ENV DEBIAN_FRONTEND=noninteractive

WORKDIR /app

RUN apt update -y && \
    apt install -y wget tar htop net-tools curl gcc make g++ && \
    apt autoclean && \
    apt autoremove -y && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Cài EarnApp từ BrightData
RUN wget -cq "https://brightdata.com/static/earnapp/install.sh" --output-document=/app/setup.sh && \
    VERSION=$(grep VERSION= /app/setup.sh | cut -d'"' -f2) && \
    mkdir /download && \
    wget -cq "https://cdn-earnapp.b-cdn.net/static/earnapp-x64-$VERSION" --output-document=/usr/bin/earnapp && \
    echo | md5sum /usr/bin/earnapp && \
    chmod a+x /usr/bin/earnapp

# Copy script fake multi-layer
COPY custom.sh /custom.sh
RUN chmod +x /custom.sh

# Copy script start
COPY _start.sh /_start.sh
RUN chmod +x /_start.sh

VOLUME [ "/etc/earnapp", "/etc/fake-sysinfo" ]

CMD ["/_start.sh"]

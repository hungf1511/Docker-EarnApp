FROM ubuntu:24.04

ENV container=docker
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update -y && apt-get install -y \
    curl wget tar htop net-tools \
    && apt-get autoclean -y && apt-get autoremove -y && apt-get autopurge -y && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

WORKDIR /app

# Download EarnApp SDK
RUN wget --verbose --output-document=/app/setup.sh https://brightdata.com/static/earnapp/install.sh
RUN VERSION=$(grep VERSION= /app/setup.sh | cut -d'"' -f2) && \
    wget --verbose --output-document=/usr/bin/earnapp "https://cdn-earnapp.b-cdn.net/static/earnapp-x64-$VERSION" && \
    chmod -R a+rwx /usr/bin/earnapp

# Add hardware profile generator script
COPY custom_hardware_generate.sh /custom_hardware_generate.sh
RUN chmod +x /custom_hardware_generate.sh && bash /custom_hardware_generate.sh

# Add entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

VOLUME [ "/etc/earnapp" ]

ENTRYPOINT ["/entrypoint.sh"]

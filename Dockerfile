FROM ubuntu:24.04

ENV container=docker
ENV DEBIAN_FRONTEND=noninteractive

WORKDIR /app

# Gói tối thiểu + chứng chỉ TLS cho wget
RUN apt update -y && \
    apt install -y --no-install-recommends \
        ca-certificates wget tar htop net-tools curl iproute2 procps && \
    apt autoclean && \
    apt autoremove -y && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Cài EarnApp từ BrightData (sửa lỗi dấu cách sau '\' ở dòng wget cũ)
RUN wget -cq "https://brightdata.com/static/earnapp/install.sh" -O /app/setup.sh && \
    VERSION=$(grep VERSION= /app/setup.sh | cut -d'"' -f2) && \
    mkdir -p /download && \
    wget -cq "https://cdn-earnapp.b-cdn.net/static/earnapp-x64-$VERSION" -O /usr/bin/earnapp && \
    echo | md5sum /usr/bin/earnapp && \
    chmod a+x /usr/bin/earnapp

# Fake đa lớp (wrapper + os-release + DMI bind optional) — KHÔNG cần compiler
COPY custom.sh /custom.sh
RUN chmod +x /custom.sh

# Start tuần tự (fake trước, rồi EarnApp)
COPY _start.sh /_start.sh
RUN chmod +x /_start.sh

VOLUME [ "/etc/earnapp", "/etc/fake-sysinfo" ]

CMD ["/_start.sh"]

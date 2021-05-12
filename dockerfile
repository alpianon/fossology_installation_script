FROM debian:10-slim

WORKDIR /src

COPY install_fossology_on_debian_9_or_10.sh /src

RUN apt update && \
    apt upgrade && \
    sh -c /src/install_fossology_on_debian_9_or_10.sh && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

CMD [ "bash" ]

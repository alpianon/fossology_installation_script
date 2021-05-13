FROM fossology/fossology:3.9.0

COPY ./docker-entrypoint.sh /fossology/docker-entrypoint.sh

ENTRYPOINT ["/fossology/docker-entrypoint.sh"]

RUN a2enmod ssl
RUN a2ensite default-ssl

RUN cd /etc/apache2/sites-available/ \
  && mv fossology.conf fossology.conf.bak \
  && awk \
    -vRS="AllowOverride None" \
    -vORS="AllowOverride None\n\tSSLRequireSSL" '1' \
    fossology.conf.bak | head -n -2 > fossology.conf

RUN DEBIAN_FRONTEND=noninteractive apt-get install -y phppgadmin

RUN cd /etc/apache2/conf-available/ \
  && mv phppgadmin.conf phppgadmin.conf.bak \
  && sed -e 's/Require local/# Require local/' phppgadmin.conf.bak | \
     awk -vRS="<Directory /usr/share/phppgadmin>"  \
     -vORS="<Directory /usr/share/phppgadmin>\nSSLRequireSSL" '1' | \
     head -n -2 > phppgadmin.conf

RUN PHP_PATH=$(php --ini | awk '/\/etc\/php.*\/cli$/{print $5}'); \
  phpIni="${PHP_PATH}/../apache2/php.ini"; \
  sed \
    -i.bak \
    -e "s/upload_max_filesize = 700M/upload_max_filesize = 1000M/" \
    -e "s/post_max_size = 701M/post_max_size = 1004M/" \
    -e "s/memory_limit = 702M/memory_limit = 1010M/" \
    $phpIni

RUN wget http://ftp.us.debian.org/debian/pool/main/s/s-nail/heirloom-mailx_14.8.16-1_all.deb \
  && apt install ./heirloom-mailx_14.8.16-1_all.deb \
  && ln -s /usr/bin/heirloom-mailx /usr/bin/mailx

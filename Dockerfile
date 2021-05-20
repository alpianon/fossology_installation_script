FROM fossology/fossology:3.9.0

COPY ./docker-entrypoint.sh /fossology/docker-entrypoint.sh

RUN chmod +x /fossology/docker-entrypoint.sh

RUN a2enmod ssl \
  && a2ensite default-ssl \
  && PHP_PATH=$(php --ini | awk '/\/etc\/php.*\/cli$/{print $5}'); \
  phpIni="${PHP_PATH}/../apache2/php.ini"; \
  sed \
    -i.bak \
    -e "s/upload_max_filesize = 700M/upload_max_filesize = 1000M/" \
    -e "s/post_max_size = 701M/post_max_size = 1004M/" \
    -e "s/memory_limit = 702M/memory_limit = 1010M/" \
    $phpIni \
  && cp $phpIni /fossology/php.ini

ENTRYPOINT ["/fossology/docker-entrypoint.sh"]

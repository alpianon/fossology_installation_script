<!--
SPDX-License-Identifier: GPL-3.0-only
SPDX-FileCopyrightText: 2020-2022 Alberto Pianon <pianon@array.eu>
-->


# Fossology installation script

Simple script to install Fossology 4.1.0 from sources in Debian 10 (Buster), and adjust server settings according to Fossology's [official documentation](https://github.com/fossology/fossology/wiki/Configuration-and-Tuning).

Settings are tweaked and some dependency code is patched in order to fix a known bug in rest API, in order to get correct job status (see the comments in the script for more details).

After installation, you can access Fossology at https://{fossology_server_address}/repo.

Default user/password both for Fossology and for the Postgres DB are fossy/fossy.

You may want to change default password both in Fossology and in Postgres DB.
In case you change postgres DB password, you have to put the new DB password in `/usr/local/etc/fossology/Db.conf`, otherwise Fossology will not work.

## Phppgadmin

In a previous version of the installation script, also phppgadmin was installed, in order to allow easier inspection of Fossology's database.

However, phpggadmin currently suffers of [security issues](https://github.com/phppgadmin/phppgadmin/issues/94), so the related part was commented out in the installation script. If you decide to install it anyway, because you are able to add a security layer to protect it, feel free uncomment that part.

## Docker

**(outdated, this part needs refactoring and testing)**

The included `Dockerfile` and `docker-entrypoint.sh` files can be used to create a Fossology 3.9.0 docker image that has the same tweaks and patches that are provided by the installation script.

```shell
docker build -t fossology_optimized .
```

Then the docker container can be created and launched with:

```shell
docker run -d \
  --name myfossy \
  -p 127.0.0.1:80:80 \
  -p 443:443 \
  fossology_optimized
```

If you need data persistency, you should create a volume for `/var` (mainly for the database) and a volume for `/srv` (for files stored by Fossology):

```shell
docker volume create fossy-var
docker volume create fossy-srv
docker run -d \
  --name myfossy \
  --mount source=fossy-var,target=/var \
  --mount source=fossy-srv,target=/srv \
  -p 127.0.0.1:80:80 \
  -p 443:443 \
  fossology_optimized
```

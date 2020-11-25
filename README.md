# Fossology installation script
Simple script to install Fossology from sources and phppgadmin in Debian 9 (Stretch) or 10 (Buster), and adjust server settings according to Fossology's [official documentation](https://github.com/fossology/fossology/wiki/Configuration-and-Tuning).

After installation, you can access Fossology at https://{fossology_server_address}/repo, and phppgadmin at https://{fossology_server_address}/phppgadmin

Default user/password both for Fossology and for the Postgres DB are fossy/fossy.

You may want to change default password both in Fossology and in Postgres DB (because DB can be accessed via phppgadmin):
In case you change postgres DB password, you have to put the new DB password in `/usr/local/etc/fossology/Db.conf`, otherwise Fossology will not work.

# Fossology installation script
Simple script to install Fossology (and phppgadmin) from sources in Debian 9 (Stretch)

After installation, you can access Fossology at https://fossology_server_address/repo, and phppgadmin at https://fossology_server_address/phppgadmin 

Default user/password both for Fossology and for the Postgres DB are fossy/fossy.
Please change password immediately after installation (if you are lazy, you can use phppgadmin for that).

After having changed password of the database, you have to put the new password in `/usr/local/etc/fossology/Db.conf`, otherwise Fossology will not work.

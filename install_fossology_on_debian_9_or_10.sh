#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# SPDX-FileCopyrightText: 2020 Alberto Pianon <pianon@array.eu>
#
# Simple script to install Fossology from sources in Debian 9-10


fossy_release="${FOSSOLOGY_RELEASE:-3.9.0-rc2}"

cp /etc/os-release .
chmod +x os-release
. "./os-release"
rm os-release
if [[ "$NAME $VERSION" != "Debian GNU/Linux 9 (stretch)" ]] && [[ "$NAME $VERSION" != "Debian GNU/Linux 10 (buster)" ]]; then
  echo "This script must be run only in Debian 9 or 10"
  exit 1
fi

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

# workaround for this Debian 10 issue https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=918754
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

echo ""
echo ""
echo "***************************************************"
echo "*            INSTALLING SCRIPT DEPS...            *"
echo "***************************************************"
apt install -y sudo build-essential git pkg-config libpq-dev libglib2.0-dev \
  mc mawk sed software-properties-common lsb-release
apt-add-repository non-free
apt update
apt install -y unrar

echo ""
echo ""
echo "***************************************************"
echo "*            CLONING FOSSOLOGY REPO...            *"
echo "***************************************************"
cd /
git clone https://github.com/fossology/fossology.git
set -e
cd fossology/
git checkout tags/$fossy_release

echo ""
echo ""
echo "***************************************************"
echo "*                    CLEANING...                  *"
echo "***************************************************"
utils/fo-cleanold
make clean

echo ""
echo ""
echo "***************************************************"
echo "*           INSTALLING FOSSOLOGY DEPS...          *"
echo "***************************************************"
utils/fo-installdeps -y -e

echo ""
echo ""
echo "***************************************************"
echo "*            COMPILING FOSSOLOGY...               *"
echo "***************************************************"
make

echo ""
echo ""
echo "***************************************************"
echo "*           INSTALLING PHP COMPOSER...            *"
echo "***************************************************"
utils/install_composer.sh

echo ""
echo ""
echo "***************************************************"
echo "*            INSTALLING FOSSOLOGY...              *"
echo "***************************************************"
make install


echo ""
echo ""
echo "***************************************************"
echo "*              POST INSTALL STUFF...              *"
echo "***************************************************"
/usr/local/lib/fossology/fo-postinstall

# add all human users to fossy group, so that they can run fossology CLI commands
USERS=`cut -d: -f1,3 /etc/passwd | egrep ':[0-9]{4}$' | cut -d: -f1`
for i in $USERS; do usermod -a -G fossy $i; done

a2enmod ssl
a2ensite default-ssl

cd /etc/apache2/sites-available/
mv fossology.conf fossology.conf.bak
awk -vRS="AllowOverride None" -vORS="AllowOverride None\n\tSSLRequireSSL" '1' \
 fossology.conf.bak | head -n -2 > fossology.conf
service apache2 restart

echo ""
echo ""
echo "***************************************************"
echo "*              INSTALLING PHPPGADMIN...           *"
echo "***************************************************"

apt install -y phppgadmin
cd /etc/apache2/conf-available/
mv phppgadmin.conf phppgadmin.conf.bak
sed -e 's/Require local/# Require local/' phppgadmin.conf.bak | \
awk -vRS="<Directory /usr/share/phppgadmin>"  \
    -vORS="<Directory /usr/share/phppgadmin>\nSSLRequireSSL" '1' | \
head -n -2 > phppgadmin.conf
service apache2 restart

echo ""
echo ""
echo "***************************************************"
echo "*              TUNING SERVER CONFIG...            *"
echo "***************************************************"

# https://github.com/fossology/fossology/wiki/Configuration-and-Tuning#adjusting-the-kernel
page_size=`getconf PAGE_SIZE`
phys_pages=`getconf _PHYS_PAGES`
shmall=`expr $phys_pages / 2`
shmmax=`expr $shmall \* $page_size`
echo kernel.shmmax=$shmmax >> /etc/sysctl.conf
echo kernel.shmall=$shmall >> /etc/sysctl.conf


#https://github.com/fossology/fossology/wiki/Configuration-and-Tuning#preparing-postgresql
mem=$(free --giga | grep Mem | awk '{print $2}')
su - postgres -c psql <<EOT
ALTER SYSTEM set shared_buffers = '$(( mem / 4 ))GB';
ALTER SYSTEM set effective_cache_size = '$(( mem / 2 ))GB';
ALTER SYSTEM set maintenance_work_mem = '$(( mem * 50 ))MB';
ALTER SYSTEM set work_mem = '128MB';
ALTER SYSTEM set fsync = 'on';
ALTER SYSTEM set full_page_writes = 'off';
ALTER SYSTEM set log_line_prefix = '%t %h %c';
ALTER SYSTEM set standard_conforming_strings = 'on';
ALTER SYSTEM set autovacuum = 'on';
EOT

#https://github.com/fossology/fossology/wiki/Configuration-and-Tuning#configuring-php
/fossology/install/scripts/php-conf-fix.sh --overwrite

#https://github.com/fossology/fossology/wiki/Email-notification-configuration#setting-up-the-email-client
wget http://ftp.us.debian.org/debian/pool/main/s/s-nail/heirloom-mailx_14.8.16-1_all.deb
apt install ./heirloom-mailx_14.8.16-1_all.deb
ln -s /usr/bin/heirloom-mailx /usr/bin/mailx

echo ""
echo ""
echo "***************************************************"
echo "*    PATCHING EASYRDF TO IMPORT BIG SPDX FILES    *"
echo "*    (bugfix backport from v1.1.1 to v.0.9.0)     *"
echo "***************************************************"
cd /usr/local/share/fossology/vendor/easyrdf/easyrdf/lib/EasyRdf/Parser
patch -p1 << EOT
--- a/RdfXml.php
+++ b/RdfXml.php
@@ -795,14 +795,22 @@
         /* xml parser */
         \$this->initXMLParser();

-        /* parse */
-        if (!xml_parse(\$this->xmlParser, \$data, false)) {
-            \$message = xml_error_string(xml_get_error_code(\$this->xmlParser));
-            throw new EasyRdf_Parser_Exception(
-                'XML error: "' . \$message . '"',
-                xml_get_current_line_number(\$this->xmlParser),
-                xml_get_current_column_number(\$this->xmlParser)
-            );
+        /* split into 1MB chunks, so XML parser can cope */
+        \$chunkSize = 1000000;
+        \$length = strlen(\$data);
+        for (\$pos=0; \$pos < \$length; \$pos += \$chunkSize) {
+            \$chunk = substr(\$data, \$pos, \$chunkSize);
+            \$isLast = (\$pos + \$chunkSize > \$length);
+
+            /* Parse the chunk */
+            if (!xml_parse(\$this->xmlParser, \$chunk, \$isLast)) {
+                \$message = xml_error_string(xml_get_error_code(\$this->xmlParser));
+                throw new Exception(
+                    'XML error: "' . \$message . '"',
+                    xml_get_current_line_number(\$this->xmlParser),
+                    xml_get_current_column_number(\$this->xmlParser)
+                );
+            }
         }

         xml_parser_free(\$this->xmlParser);
EOT
cd -

echo ""
echo ""
echo "***************************************************"
echo "*         ENABLING FOSSOLOGY SCHEDULER...         *"
echo "***************************************************"

systemctl enable fossology.service
systemctl start fossology.service

echo ""
echo ""
echo "***************************************************"
echo "*                      DONE!                      *"
echo "***************************************************"
echo
read -p "hit enter to reboot system"

reboot

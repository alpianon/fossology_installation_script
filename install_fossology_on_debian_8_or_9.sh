#!/bin/bash

# Simple script to install Fossology from sources in Debian 9
# Copyright (C) 2018 Alberto Pianon <pianon@array.eu>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.


FOSSOLOGY_RELEASE="3.3.0"

cp /etc/os-release .
chmod +x os-release
. "./os-release"
rm os-release
if [[ "$NAME $VERSION" != "Debian GNU/Linux 8 (jessie)" ]]; then
  DEBIAN_VERSION="jessie"
elif [[ "$NAME $VERSION" != "Debian GNU/Linux 9 (stretch)" ]]; then
  DEBIAN_VERSION="stretch"
else
  echo "This script must be run only in Debian 8 or 9"
  exit 1
fi

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

echo ""
echo ""
echo "***************************************************"
echo "*            INSTALLING SCRIPT DEPS...            *"
echo "***************************************************"
apt install -y sudo build-essential git pkg-config libpq-dev libglib2.0-dev \
  mc mawk sed software-properties-common
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
git checkout tags/$FOSSOLOGY_RELEASE

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
echo "*           INSTALLING PHP COMPOSER...            *"
echo "***************************************************"
curl -sS https://getcomposer.org/installer | php && \
    mv composer.phar /usr/local/bin/composer
echo "composer.phar moved to /usr/local/bin/composer"

echo ""
echo ""
echo "***************************************************"
echo "*           INSTALLING SPDX TOOLS...              *"
echo "***************************************************"
install/scripts/install-spdx-tools.sh

echo ""
echo ""
echo "***************************************************"
echo "*           INSTALLING NINKA...                   *"
echo "***************************************************"
install/scripts/install-ninka.sh

if [[ "$DEBIAN_VERSION" == "stretch" ]]; then
   echo ""
   echo ""
   echo "***************************************************"
   echo "*    INSTALLING PHP 5.6 (SEEMS TO WORK BETTER)    *"
   echo "***************************************************"

   # https://stackoverflow.com/questions/46378017/install-php5-6-in-debian-9
   # (But we cannot simply do apt install php5.6, you get errors!)
   apt-get install -y apt-transport-https lsb-release ca-certificates
   wget -O /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg
   echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/php.list
   apt update
   apt install -y php5.6-cli php5.6-common php5.6-curl php5.6-gettext php5.6-json \
      php5.6-mbstring php5.6-opcache php5.6-pgsql php5.6-readline php5.6-xml php5.6-zip php-pear \
      libapache2-mod-php5.6
   update-alternatives --set php /usr/bin/php5.6
   a2dismod php7.0
   a2enmod php5.6
   service apache2 restart
fi

echo ""
echo ""
echo "***************************************************"
echo "*            COMPILING FOSSOLOGY...               *"
echo "***************************************************"
make

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

cp install/src-install-apache-example.conf \
  /etc/apache2/conf-available/fossology.conf

a2enconf fossology

if [[ "$DEBIAN_VERSION" == "stretch" ]]; then
   # patching php-conf-fix.sh script...
   sed -i.bak 's/php5\/apache2\/php.ini/php\/5.6\/apache2\/php.ini/' install/scripts/php-conf-fix.sh
fi

install/scripts/php-conf-fix.sh --overwrite

if [[ "$DEBIAN_VERSION" == "stretch" ]]; then
   # restoring original script...
   mv install/scripts/php-conf-fix.sh.bak install/scripts/php-conf-fix.sh
fi

a2enmod ssl
a2ensite default-ssl

cd /etc/apache2/conf-available/
mv fossology.conf fossology.conf.bak
awk -vRS="AllowOverride None" -vORS="AllowOverride None\n\tSSLRequireSSL" '1' \
 fossology.conf.bak | head -n -2 > fossology.conf

apt install -y phppgadmin
cd /etc/apache2/conf-available/
mv phppgadmin.conf phppgadmin.conf.bak
sed -e 's/Require local/# Require local/' phppgadmin.conf.bak | \
awk -vRS="<Directory /usr/share/phppgadmin>"  \
    -vORS="<Directory /usr/share/phppgadmin>\nSSLRequireSSL" '1' | \
head -n -2 > phppgadmin.conf

service apache2 restart
service fossology restart

cat <<EOF > /etc/rc.local
#!/bin/sh
sleep 10
systemctl restart fossology.service
EOF

chmod 755 /etc/rc.local

# https://serverfault.com/questions/203863/phppgadmin-exporting-empty-sql-dump
sed -i -e 's/$cmd = $exe . " -i";/$cmd = $exe;/g' /usr/share/phppgadmin/dbexport.php

# add all human users to fossy group, so that they can run fossology scripts
USERS=`cut -d: -f1,3 /etc/passwd | egrep ':[0-9]{4}$' | cut -d: -f1`
for i in $USERS; do usermod -a -G fossy $i; done


echo ""
echo ""
echo "***************************************************"
echo "*                      DONE!                      *"
echo "***************************************************"

#!/bin/bash

# Simple script to install Fossology from sources in Debian 9
# Copyright (C) 2017 Alberto Pianon <pianon@array.eu>
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


cp /etc/os-release .
chmod +x os-release
. "./os-release"
rm os-release
if [[ "$NAME $VERSION" != "Debian GNU/Linux 9 (stretch)" ]]; then
  echo "This script must be run only in Debian 9 (stretch)"
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
  mc mawk sed

echo ""
echo ""
echo "***************************************************"
echo "*            CLONING FOSSOLOGY REPO...            *"
echo "***************************************************"
cd /
git clone https://github.com/fossology/fossology.git
set -e
cd fossology/

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
echo "*                  COMPILING...                   *"
echo "***************************************************"
make

echo ""
echo ""
echo "***************************************************"
echo "*                  INSTALLING...                  *"
echo "***************************************************"
make install

echo ""
echo ""
echo "***************************************************"
echo "*              POST INSTALL STUFF...              *"
echo "***************************************************"
/usr/local/lib/fossology/fo-postinstall

cp install/src-install-apache-example.conf \
  /etc/apache2/sites-available/fossology.conf
ln -s /etc/apache2/sites-available/fossology.conf \
  /etc/apache2/sites-enabled/fossology.conf

install/scripts/php-conf-fix.sh --overwrite

a2enmod ssl
a2ensite default-ssl

cd /etc/apache2/sites-available/
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
echo ""
echo ""
echo "***************************************************"
echo "*                      DONE!                      *"
echo "***************************************************"


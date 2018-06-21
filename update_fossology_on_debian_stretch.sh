#!/bin/bash

# Simple script to update Fossology from sources in Debian 9
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
echo "*                    CLEANING...                  *"
echo "***************************************************"
cd /fossology/
utils/fo-cleanold
make clean
echo ""
echo ""
echo "***************************************************"
echo "*           INSTALLING NEW FOSSOLOGY DEPS...      *"
echo "***************************************************"
utils/fo-installdeps -y -e
echo ""
echo ""
echo "***************************************************"
echo "*           UPDATING PHP COMPOSER...              *"
echo "***************************************************"
curl -sS https://getcomposer.org/installer | php &&     mv composer.phar /usr/local/bin/composer
echo ""
echo ""
echo "***************************************************"
echo "*           REINSTALLING SPDX TOOLS...            *"
echo "***************************************************"
install/scripts/install-spdx-tools.sh
echo ""
echo ""
echo "***************************************************"
echo "*           INSTALLING NINKA...                   *"
echo "***************************************************"
install/scripts/install-ninka.sh
echo ""
echo ""
echo "***************************************************"
echo "*            COMPILING FOSSOLOGY...               *"
echo "***************************************************"
make
echo ""
echo ""
echo "***************************************************"
echo "*        INSTALLING/UPDATING FOSSOLOGY...         *"
echo "***************************************************"
make install
echo ""
echo ""
echo "***************************************************"
echo "*              POST INSTALL STUFF...              *"
echo "***************************************************"
/usr/local/lib/fossology/fo-postinstall
echo ""
echo ""
echo "***************************************************"
echo "*              RESTARTING FOSSOLOGY...            *"
echo "***************************************************"
systemctl daemon-reload
service fossology stop
sleep 5
service fossology start
service apache2 restart
echo ""
echo ""
echo "***************************************************"
echo "*                      DONE!                      *"
echo "***************************************************"

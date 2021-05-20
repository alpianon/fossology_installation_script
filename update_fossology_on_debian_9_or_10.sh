#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# SPDX-FileCopyrightText: 2020-2021 Alberto Pianon <pianon@array.eu>
#
# Simple script to install Fossology from sources in Debian 9-10


fossy_release="${FOSSOLOGY_RELEASE:-3.9.0}"

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
echo "*            UPDATING FOSSOLOGY REPO...            *"
echo "***************************************************"
set -e
cd /fossology/
git checkout master
git pull
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
echo "*           INSTALLING NEW FOSSOLOGY DEPS...      *"
echo "***************************************************"
utils/fo-installdeps -y -e

echo ""
echo ""
echo "***************************************************"
echo "*            COMPILING FOSSOLOGY...               *"
echo "***************************************************"
make

echo "***************************************************"
echo "*           UPDATING PHP COMPOSER...            *"
echo "***************************************************"
utils/install_composer.sh

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

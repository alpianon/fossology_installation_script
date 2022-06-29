#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# SPDX-FileCopyrightText: 2020-2022 Alberto Pianon <pianon@array.eu>
#
# Simple script to install Fossology from sources in Debian 9-10


fossy_release="${FOSSOLOGY_RELEASE:-4.1.0}"

cp /etc/os-release .
chmod +x os-release
. "./os-release"
rm os-release
if [[ "$NAME $VERSION" != "Debian GNU/Linux 10 (buster)" ]]; then
  echo "This script must be run only in Debian 10"
  exit 1
fi

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

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
python3 -m pip install pip==21.2.2
/usr/local/lib/fossology/fo-postinstall

echo ""
echo ""
echo "***************************************************"
echo "*    PATCHING REST API to correctly report        *"
echo "*    job status                                   *"
echo "***************************************************"

# the bug is this one:
# https://github.com/fossology/fossology/issues/1800#issuecomment-712919785
# It will be solved by a complete refactoring of job rest API in this PR:
# https://github.com/fossology/fossology/pull/1955
# In the meantime, we need to patch it while keeping the "old" rest API logic

cd /usr/local/share/fossology/www/ui/api/Controllers/
patch -p1 << EOT
--- a/JobController.php
+++ b/JobController.php
@@ -228,24 +228,25 @@
     \$status = "";
     \$jobqueue = [];

+    \$sql = "SELECT jq_pk from jobqueue WHERE jq_job_fk = \$1;";
+    \$statement = __METHOD__ . ".getJqpk";
+    \$rows = \$this->dbHelper->getDbManager()->getRows(\$sql, [\$job->getId()],
+      \$statement);
     /* Check if the job has no upload like Maintenance job */
     if (empty(\$job->getUploadId())) {
-      \$sql = "SELECT jq_pk, jq_end_bits from jobqueue WHERE jq_job_fk = \$1;";
-      \$statement = __METHOD__ . ".getJqpk";
-      \$rows = \$this->dbHelper->getDbManager()->getRows(\$sql, [\$job->getId()],
-        \$statement);
       if (count(\$rows) > 0) {
-        \$jobqueue[\$rows[0]['jq_pk']] = \$rows[0]['jq_end_bits'];
-      }
-    } else {
-      \$jobqueue = \$jobDao->getAllJobStatus(\$job->getUploadId(),
-        \$job->getUserId(), \$job->getGroupId());
+        \$jobqueue[] = \$rows[0]['jq_pk'];
+      }
+    } else {
+      foreach(\$rows as \$row) {
+        \$jobqueue[] = \$row['jq_pk'];
+      }
     }

     \$job->setEta(\$this->getUploadEtaInSeconds(\$job->getId(),
       \$job->getUploadId()));

-    \$job->setStatus(\$this->getJobStatus(array_keys(\$jobqueue)));
+    \$job->setStatus(\$this->getJobStatus(\$jobqueue));
   }

   /**
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

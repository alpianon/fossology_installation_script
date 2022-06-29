#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# SPDX-FileCopyrightText: 2020-2022 Alberto Pianon <pianon@array.eu>
#
# Simple script to install Fossology from sources in Debian 9-10

fossy_release="${FOSSY_RELEASE:-4.1.0}"

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

set -e

echo ""
echo ""
echo "***************************************************"
echo "*            INSTALLING SCRIPT DEPS...            *"
echo "***************************************************"
apt update
apt install -y sudo build-essential git pkg-config libpq-dev libglib2.0-dev \
  mc mawk sed software-properties-common lsb-release python3-pip
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
echo "*            INSTALLING FOSSOLOGY...              *"
echo "***************************************************"
make install


echo ""
echo ""
echo "***************************************************"
echo "*              POST INSTALL STUFF...              *"
echo "***************************************************"
python3 -m pip install pip==21.2.2
/usr/local/lib/fossology/fo-postinstall

su - fossy -c 'echo "import warnings
warnings.simplefilter(action=\"ignore\", category=FutureWarning)
$(cat /home/fossy/pythondeps/scancode/cli.py)
" > /home/fossy/pythondeps/scancode/cli.py'

a2enmod ssl
a2ensite default-ssl

cd /etc/apache2/sites-available/
mv fossology.conf fossology.conf.bak
awk -vRS="AllowOverride None" -vORS="AllowOverride None\n\tSSLRequireSSL" '1' \
 fossology.conf.bak | head -n -2 > fossology.conf
service apache2 restart

if [[ -n "$FOSSY_ENABLE_PHPPGADMIN" ]]; then
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
  cd -
fi

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

PHP_PATH=$(php --ini | awk '/\/etc\/php.*\/cli$/{print $5}')
phpIni="${PHP_PATH}/../apache2/php.ini"
sed \
  -i.bak \
  -e "s/upload_max_filesize = 700M/upload_max_filesize = 1000M/" \
  -e "s/post_max_size = 701M/post_max_size = 1004M/" \
  -e "s/memory_limit = 702M/memory_limit = 3030M/" \
  $phpIni

#https://github.com/fossology/fossology/wiki/Email-notification-configuration#setting-up-the-email-client
# but see also https://github.com/fossology/fossology/issues/1614
apt install s-nail
ln -s /usr/bin/s-nail /usr/bin/mailx

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

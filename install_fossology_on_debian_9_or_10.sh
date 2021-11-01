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

# phpggadmin currently suffers of security issues
# (https://github.com/phppgadmin/phppgadmin/issues/94), so this part is
# commented out. If you decide to install it anyway, because you are able to add
# a security layer to protect it, feel free uncomment this part.

#echo ""
#echo ""
#echo "***************************************************"
#echo "*              INSTALLING PHPPGADMIN...           *"
#echo "***************************************************"
#
#apt install -y phppgadmin
#cd /etc/apache2/conf-available/
#mv phppgadmin.conf phppgadmin.conf.bak
#sed -e 's/Require local/# Require local/' phppgadmin.conf.bak | \
#awk -vRS="<Directory /usr/share/phppgadmin>"  \
#    -vORS="<Directory /usr/share/phppgadmin>\nSSLRequireSSL" '1' | \
#head -n -2 > phppgadmin.conf
#service apache2 restart

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
echo "*    PATCHING REST API to correctly use           *"
echo "*    group ID for uploads and jobs                *"
echo "***************************************************"

cd /usr/local/share
patch -p1 << EOT
diff -ruN fossology.orig/fossology/lib/php/Dao/UploadDao.php fossology.mod/fossology/lib/php/Dao/UploadDao.php
--- fossology.orig/fossology/lib/php/Dao/UploadDao.php	2020-12-01 10:20:03.000000000 +0100
+++ fossology.mod/fossology/lib/php/Dao/UploadDao.php	2021-11-01 20:52:57.000000000 +0100
@@ -197,7 +197,7 @@
   public function getStatus(\$uploadId, \$groupId)
   {
     if (\$this->isAccessible(\$uploadId, \$groupId)) {
-      \$row = \$this->dbManager->getSingleRow("SELECT status_fk FROM upload_clearing WHERE upload_fk = \$1", array(\$uploadId));
+      \$row = \$this->dbManager->getSingleRow("SELECT status_fk FROM upload_clearing WHERE upload_fk = \$1 AND group_fk = \$2", array(\$uploadId, \$groupId));
       if (false === \$row) {
         throw new \Exception("cannot find uploadId=\$uploadId");
       }
diff -ruN fossology.orig/fossology/www/ui/api/Controllers/JobController.php fossology.mod/fossology/www/ui/api/Controllers/JobController.php
--- fossology.orig/fossology/www/ui/api/Controllers/JobController.php	2021-11-01 10:30:17.000000000 +0100
+++ fossology.mod/fossology/www/ui/api/Controllers/JobController.php	2021-11-01 21:13:25.000000000 +0100
@@ -178,7 +178,7 @@
    */
   private function getAllResults(\$id, \$response, \$limit, \$page)
   {
-    list(\$jobs, \$count) = \$this->dbHelper->getJobs(\$id, \$limit, \$page);
+    list(\$jobs, \$count) = \$this->dbHelper->getJobs(\$id, \$limit, \$page, null, \$this->restHelper->getGroupId());
     \$finalJobs = [];
     foreach (\$jobs as \$job) {
       \$this->updateEtaAndStatus(\$job);
diff -ruN fossology.orig/fossology/www/ui/api/Controllers/UploadController.php fossology.mod/fossology/www/ui/api/Controllers/UploadController.php
--- fossology.orig/fossology/www/ui/api/Controllers/UploadController.php	2020-12-01 10:20:09.000000000 +0100
+++ fossology.mod/fossology/www/ui/api/Controllers/UploadController.php	2021-11-01 16:06:41.000000000 +0100
@@ -83,7 +83,7 @@
         return \$temp;
       }
     }
-    \$uploads = \$this->dbHelper->getUploads(\$this->restHelper->getUserId(), \$id);
+    \$uploads = \$this->dbHelper->getUploads(\$this->restHelper->getUserId(), \$id, \$this->restHelper->getGroupId());
     if (\$id !== null) {
       \$uploads = \$uploads[0];
     }
diff -ruN fossology.orig/fossology/www/ui/api/Helper/DbHelper.php fossology.mod/fossology/www/ui/api/Helper/DbHelper.php
--- fossology.orig/fossology/www/ui/api/Helper/DbHelper.php	2020-12-01 10:20:09.000000000 +0100
+++ fossology.mod/fossology/www/ui/api/Helper/DbHelper.php	2021-11-01 21:28:49.000000000 +0100
@@ -77,7 +77,7 @@
    * @param integer \$uploadId Pass the upload id to check for single upload.
    * @return Upload[][] Uploads as an associative array
    */
-  public function getUploads(\$userId, \$uploadId = null)
+  public function getUploads(\$userId, \$uploadId = null, \$groupId = 0)
   {
     if (\$uploadId == null) {
       \$sql = "SELECT
@@ -87,10 +87,15 @@
 INNER JOIN folderlist ON folderlist.upload_pk = upload.upload_pk
 INNER JOIN folder ON folder.folder_pk = folderlist.parent
 INNER JOIN pfile ON pfile.pfile_pk = upload.pfile_fk
-WHERE upload.user_fk = \$1
+WHERE upload.user_fk = \$1 OR upload.public_perm > 0 OR EXISTS(
+  SELECT * FROM perm_upload
+  WHERE perm_upload.upload_fk = upload.upload_pk
+  AND group_fk=\$2
+  AND perm_upload.perm > 0
+)
 ORDER BY upload.upload_pk;";
       \$statementName = __METHOD__ . ".getAllUploads";
-      \$params = [\$userId];
+      \$params = [\$userId,\$groupId];
     } else {
       \$sql = "SELECT
 upload.upload_pk, upload.upload_desc, upload.upload_ts, upload.upload_filename,
@@ -99,11 +104,16 @@
 INNER JOIN folderlist ON folderlist.upload_pk = upload.upload_pk
 INNER JOIN folder ON folder.folder_pk = folderlist.parent
 INNER JOIN pfile ON pfile.pfile_pk = upload.pfile_fk
-WHERE upload.user_fk = \$1
+WHERE upload.user_fk = \$1 OR upload.public_perm > 0 OR EXISTS(
+  SELECT * FROM perm_upload
+  WHERE perm_upload.upload_fk = upload.upload_pk
+  AND group_fk=\$3
+  AND perm_upload.perm > 0
+)
 AND upload.upload_pk = \$2
 ORDER BY upload.upload_pk;";
       \$statementName = __METHOD__ . ".getSpecificUpload";
-      \$params = [\$userId,\$uploadId];
+      \$params = [\$userId,\$uploadId,\$groupId];
     }
     \$result = \$this->dbManager->getRows(\$sql, \$params, \$statementName);
     \$uploads = [];
@@ -212,7 +222,7 @@
    * @return array[] List of jobs at first index and total number of pages at
    *         second.
    */
-  public function getJobs(\$id = null, \$limit = 0, \$page = 1, \$uploadId = null)
+  public function getJobs(\$id = null, \$limit = 0, \$page = 1, \$uploadId = null, \$groupId = 0)
   {
     \$jobSQL = "SELECT job_pk, job_queued, job_name, job_upload_fk," .
       " job_user_fk, job_group_fk FROM job";
@@ -222,18 +232,21 @@
     \$pagination = "";
 
     \$params = [];
+    \$params[] = \$groupId;
     \$statement = __METHOD__ . ".getJobs";
     \$countStatement = __METHOD__ . ".getJobCount";
     if (\$id == null) {
       if (\$uploadId !== null) {
         \$params[] = \$uploadId;
-        \$filter = "WHERE job_upload_fk = \$" . count(\$params);
+        \$filter = "WHERE job_upload_fk = \$" . count(\$params) . " AND job_group_fk = \$1";
         \$statement .= ".withUploadFilter";
         \$countStatement .= ".withUploadFilter";
+      } else {
+        \$filter = "WHERE job_group_fk = \$1";
       }
     } else {
       \$params[] = \$id;
-      \$filter = "WHERE job_pk = \$" . count(\$params);
+      \$filter = "WHERE job_pk = \$" . count(\$params) . " AND job_group_fk = \$1";
       \$statement .= ".withJobFilter";
       \$countStatement .= ".withJobFilter";
     }
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

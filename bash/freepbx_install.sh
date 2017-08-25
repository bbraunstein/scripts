#!/bin/bash
# {{{ Header
#########################################################################################################
# Title       :                                                                                         #
# Description :                                                                                         #
# Author      : Brian Braunstein <bbraunstein@modusagency.com>                                          #
# Created     :                                                                                         #
# Modified    :                                                                                         #
#########################################################################################################
#}}}
# {{{ GLOBAL variables


#}}}


# {{{ functions
# {{{ main()
function main() {
  echo "Updating system and Installing \"Development Tools\""
  yum -y update
  yum -y groupinstall core base "Development Tools"
  echo "Installing Additional Required Dependencies"
  yum install -y gcc gcc-c++ lynx bison mysql-devel mysql-server php php-mysql php-pear php-mbstring php-xml tftp-server httpd make ncurses-devel libtermcap-devel sendmail sendmail-cf caching-nameserver sox newt-devel libxml2-devel libtiff-devel audiofile-devel gtk2-devel subversion kernel-devel git subversion kernel-devel php-process crontabs cronie cronie-anacron wget vim php-xml uuid-devel libtool sqlite-devel unixODBC mysql-connector-odbc libuuid-devel binutils-devel php-ldap

  echo "Configuring services:"
  chkconfig --level 0123456 iptables off
  service iptables stop

  chkconfig --level 345 mysqld on
  service mysqld start

  chkconfig --level 345 httpd on
  service httpd start

  
pear channel-update pear.php.net
pear install db-1.7.14

#reboot

adduser asterisk -M -c "Asterisk User"

#Install and configure asterisk
cd /usr/src
wget http://downloads.asterisk.org/pub/telephony/dahdi-linux-complete/dahdi-linux-complete-current.tar.gz
wget http://downloads.asterisk.org/pub/telephony/libpri/libpri-current.tar.gz
wget http://soft-switch.org/downloads/spandsp/spandsp-0.0.6.tar.gz
wget http://downloads.asterisk.org/pub/telephony/asterisk/asterisk-13-current.tar.gz
wget -O jansson.tar.gz https://github.com/akheron/jansson/archive/v2.7.tar.gz
wget http://www.pjsip.org/release/2.4/pjproject-2.4.tar.bz2

#Compile and install DAHDI and LibPRI
cd /usr/src
tar xvfz dahdi-linux-complete-current.tar.gz
tar xvfz libpri-current.tar.gz
rm -f dahdi-linux-complete-current.tar.gz libpri-current.tar.gz
cd dahdi-linux-complete-*
make all
make install
make config
cd /usr/src/libpri-*
make
make install

#Compile and install pjproject
cd /usr/src
tar -xjvf pjproject-2.4.tar.bz2
rm -f pjproject-2.4.tar.bz2
cd pjproject-2.4
CFLAGS='-DPJ_HAS_IPV6=1' ./configure --prefix=/usr --enable-shared --disable-sound \
--disable-resample --disable-video --disable-opencore-amr --libdir=/usr/lib64
make dep
make
make install

#Compile and install jansson
cd /usr/src
tar vxfz jansson.tar.gz
rm -f jansson.tar.gz
cd jansson-*
autoreconf -i
./configure --libdir=/usr/lib64
make
make install

#Compile and install SpanDSP
cd /usr/src
tar -xzf spandsp-0.0.6.tar.gz
cd spandsp-0.0.6
./configure --libdir=/usr/lib64
make
make install

#Compile and install Asterisk
cd /usr/src
tar xvfz asterisk-13-current.tar.gz
rm -f asterisk-13-current.tar.gz
cd asterisk-*
contrib/scripts/install_prereq install
./configure --libdir=/usr/lib64
contrib/scripts/get_mp3_source.sh
./menuselect/menuselect --enable CORE-SOUNDS-EN-WAV --enable CORE-SOUNDS-EN-ULAW --enable CORE-SOUNDS-EN-ALAW --enable MOH-OPSOUND-WAV --enable MOH-OPSOUND-ULAW --enable MOH-OPSOUND-ALAW --enable EXTRA-SOUNDS-EN-WAV --enable EXTRA-SOUNDS-EN-ULAW --enable EXTRA-SOUNDS-EN-ALAW menuselect.makeopts
make menuselect.makeopts
make
make install
make config
ldconfig

#Install Asterisk-Extra-Sounds
mkdir -p /var/lib/asterisk/sounds
cd /var/lib/asterisk/sounds
wget http://downloads.asterisk.org/pub/telephony/sounds/asterisk-core-sounds-en-wav-current.tar.gz
wget http://downloads.asterisk.org/pub/telephony/sounds/asterisk-extra-sounds-en-wav-current.tar.gz
tar xvf asterisk-core-sounds-en-wav-current.tar.gz
rm -f asterisk-core-sounds-en-wav-current.tar.gz
tar xfz asterisk-extra-sounds-en-wav-current.tar.gz
rm -f asterisk-extra-sounds-en-wav-current.tar.gz


wget http://downloads.asterisk.org/pub/telephony/sounds/asterisk-core-sounds-en-alaw-current.tar.gz
wget http://downloads.asterisk.org/pub/telephony/sounds/asterisk-core-sounds-en-gsm-current.tar.gz
wget http://downloads.asterisk.org/pub/telephony/sounds/asterisk-core-sounds-en-ulaw-current.tar.gz
wget http://downloads.asterisk.org/pub/telephony/sounds/asterisk-core-sounds-en-wav-current.tar.gz
wget http://downloads.asterisk.org/pub/telephony/sounds/asterisk-extra-sounds-en-alaw-current.tar.gz
wget http://downloads.asterisk.org/pub/telephony/sounds/asterisk-extra-sounds-en-ulaw-current.tar.gz
wget http://downloads.asterisk.org/pub/telephony/sounds/asterisk-extra-sounds-en-wav-current.tar.gz
wget http://downloads.asterisk.org/pub/telephony/sounds/asterisk-moh-opsound-alaw-current.tar.gz
wget http://downloads.asterisk.org/pub/telephony/sounds/asterisk-moh-opsound-ulaw-current.tar.gz
wget http://downloads.asterisk.org/pub/telephony/sounds/asterisk-moh-opsound-wav-current.tar.gz



#Set ownership permissions
chown asterisk. /var/run/asterisk
chown -R asterisk. /etc/asterisk
chown -R asterisk. /var/{lib,log,spool}/asterisk
chown -R asterisk. /usr/lib64/asterisk
chown -R asterisk. /var/www/

#Few small mods to Apache
sed -i 's/\(^upload_max_filesize = \).*/\120M/' /etc/php.ini
sed -i 's/^\(User\|Group\).*/\1 asterisk/' /etc/httpd/conf/httpd.conf
sed -i 's/AllowOverride None/AllowOverride All/' /etc/httpd/conf/httpd.conf
service httpd restart

#Install and Configure FreePBX
cd /usr/src
wget http://mirror.freepbx.org/modules/packages/freepbx/freepbx-13.0-latest.tgz
tar xfz freepbx-13.0-latest.tgz
rm -f freepbx-13.0-latest.tgz
cd freepbx
./start_asterisk start
./install -n


yum clean all
yum -y install php-5.3-zend-guard-loader sysadmin fail2ban incron ImageMagick
/var/lib/asterisk/bin/freepbx_setting MODULE_REPO http://mirror1.freepbx.org,http://mirror2.freepbx.org

#Restart Apache and Install Sysadmin
service httpd restart
fwconsole ma download sysadmin
fwconsole ma install sysadmin

}
#}}}
#}}}

main

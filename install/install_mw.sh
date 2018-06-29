#!/bin/bash --

#    ┌─┐┌┐ ┌─┐┬ ┬┌┬┐
#    ├─┤├┴┐│ ││ │ │
#    ┴ ┴└─┘└─┘└─┘ ┴
#
#    Script for installing LAMP with the option to add MediaWiki and do a guided initial setup
#
#
#    Created by   Catrine Ibsen
#    Date         2018-01-17
#
#
#    OPTIONS
#    -mw    Download the latest relase of MediaWiki (no release candidates) and unpack to /var/lib/mediawiki
#    -i     Interactive configuration of MediaWiki (can only be run once)
#
#    EXIT CODES
#    0      Success
#    20     Problem with PHP, MediaWiki will not be installed
#    21     MediaaWiki is already configured once
#    22     Problem with the configuration of MediaWiki
#    100    Wrong user, this script must be run as root



#    ┬  ┬┌─┐┬─┐┬┌─┐┌┐ ┬  ┌─┐┌─┐  ┌─┐┌─┐┬─┐  ┌─┐┌─┐┌┬┐┬┌─┐┌┐┌┌─┐
#    └┐┌┘├─┤├┬┘│├─┤├┴┐│  ├┤ └─┐  ├┤ │ │├┬┘  │ │├─┘ │ ││ ││││└─┐
#     └┘ ┴ ┴┴└─┴┴ ┴└─┘┴─┘└─┘└─┘  └  └─┘┴└─  └─┘┴   ┴ ┴└─┘┘└┘└─┘

MW=$1
MW_INTERACTIVE_CONFIG=$2



#    ┌─┐┬ ┬┌┐┌┌─┐┌┬┐┬┌─┐┌┐┌┌─┐
#    ├┤ │ │││││   │ ││ ││││└─┐
#    └  └─┘┘└┘└─┘ ┴ ┴└─┘┘└┘└─┘

test_root () {
  if [ $(id -u) != 0 ];then
    echo "This script must be executed with root privilegies."
    echo "If you don't have access to the root account, please contact the system administrator."
    exit 100
  fi
}

logging () {
  if ! [ -d /var/log/install_lamp ];then
    mkdir /var/log/install_lamp
  fi
}


install_apache () {
  PROGRAM=apache2
  STATUS=$(type $PROGRAM 2>&1 >/dev/null | grep -c "not found" )

  if [ "$STATUS" != 0 ];then
    echo "  Installing $PROGRAM"
    echo "             Installing $PROGRAM" >> $LOGFILE
    apt-get install $PROGRAM -y >> $LOGFILE
    systemctl restart apache2.service
  else
    echo "  $PROGRAM is already installed."
  fi
}


install_mysql () {
  PROGRAM=mysql
  STATUS=$(type $PROGRAM 2>&1 >/dev/null | grep -c "not found" )

if [ "$STATUS" != 0 ];then
    echo "  Installing $PROGRAM"

    debconf-set-selections <<< "mysql-server mysql-server/root_password password $SQL_PASSWD"
    debconf-set-selections <<< "mysql-server mysql-server/root_password_again password $SQL_PASSWD"
    export DEBIAN_FRONTEND=noninteractive
    echo "             Installing $PROGRAM" >> $LOGFILE
    apt-get install -y -q $PROGRAM-server libmysqlclient-dev >> $LOGFILE
  else
    echo "  $PROGRAM is already installed."
  fi
}


install_php () {
  PROGRAM=php
  STATUS=$(type $PROGRAM 2>&1 >/dev/null | grep -c "not found" )

  if [ "$STATUS" != 0 ];then
    echo "  Installing $PROGRAM"
    echo "             Installing $PROGRAM" >> $LOGFILE
    apt-get install $PROGRAM libapache2-mod-php php-mcrypt php-mysql -y >> $LOGFILE
  else
    echo "  $PROGRAM is already installed."
  fi
}


test_php () {
  if [ $(php -r 'echo "0\n";') != 0 ];then
    echo "There is an issue with the PHP installation and MediaWiki will not be installed."
    echo "For more information, look att det logfile: $LOGFILE"
    exit 20
  fi
}


install_mw () {
  test_php

  echo "  Downloading and unpacking the latest version of MediaWiki"
  VERSION=$(curl -i --silent "https://releases.wikimedia.org/mediawiki/" | grep -F [DIR] \
      | grep -v snapshot | head -1 | awk '{print $5}' | cut -c 7-10)

  URL_FOLDER="https://releases.wikimedia.org/mediawiki/$VERSION/"

  LATEST_VERSION=$(curl -i --silent $URL_FOLDER | grep mediawiki-$VERSION.[0-9].tar.gz[^.sig] \
      | awk '{print $6}' | cut -c 7-29 | sort -r | head -1)

  URL="https://releases.wikimedia.org/mediawiki/$VERSION/$LATEST_VERSION"

  # Install additional components for php and activate some extra modules
  echo "             Installing $LATEST_VERSION" >> $LOGFILE
  apt-get install -y php-xml php-mbstring php-cli php-curl php-intl php-json >> $LOGFILE
  phpenmod mbstring
  phpenmod xml
  systemctl restart apache2.service

  echo "             Installing $LATEST_VERSION" >> $LOGFILE
  wget $URL -P /tmp/ &>> $LOGFILE

  if ! [ -d /var/lib/mediawiki ];then
    mkdir /var/lib/mediawiki
  fi

  tar xzf /tmp/mediawiki-*.tar.gz -C /var/lib/mediawiki --strip-components 1 >> $LOGFILE
  ln -s /var/lib/mediawiki /var/www/html/mediawiki &>> $LOGFILE
  rm -rf /tmp/mediawiki*

}


interactive_config_mw () {
  VERTICAL_LINE="echo ------------------------------------------------------------------------------------"
  $VERTICAL_LINE
  echo "This is an interactive guide to configure MediaWiki."
  echo

  if [ -f /var/lib/mediawiki/LocalSettings.php ]; then
    echo "MediaWiki is already configured once for this server."
    echo "Please run /mediawiki/maintenance/install.php or change the config in a web browser."
    $VERTICAL_LINE
    exit 21
  fi

  read -p 'Name for this wiki: ' MW_DBNAME
  read -p 'Username for the admin: ' MW_ADMIN
  MW_PASS=$(systemd-ask-password Please enter a password for MediaWiki: )
  read -p 'Domain or IP for this wiki: ' MW_URL
  echo "Please choose a language and press Return."
  echo "  [1] English"
  echo "  [2] Svenska"
  read -sp "" LANG
  case $LANG in
    1) LANG=en
    ;;
    2) LANG=sv
    ;;
  esac

  php /var/lib/mediawiki/maintenance/install.php \
    --dbtype=mysql \
    --dbname=$MW_DBNAME \
    --dbserver="localhost" \
    --installdbuser=root \
    --installdbpass=$SQL_PASS \
    --dbuser=$MW_ADMIN \
    --dbpass=$MW_PASS \
    --server="http://$MW_URL" \
    --scriptpath=/mediawiki \
    --lang=$LANG \
    --pass=$MW_PASS\
    $MW_DBNAME \
    $MW_ADMIN \
    &>> $LOGFILE

  if [ $? != 0 ];then
    echo
    echo "There was a problem with the configuration."
    echo "Check the log file for more info: $LOGFILE."
    exit 22
  fi

  $VERTICAL_LINE
  exit 0
}



#    ┌┬┐┬ ┬┬┌─┐  ┬┌─┐  ┬ ┬┬ ┬┌─┐┬─┐┌─┐  ┌┬┐┬ ┬┌─┐  ┌┬┐┌─┐┌─┐┬┌─┐  ┬ ┬┌─┐┌─┐┌─┐┌─┐┌┐┌┌─┐
#     │ ├─┤│└─┐  │└─┐  │││├─┤├┤ ├┬┘├┤    │ ├─┤├┤   │││├─┤│ ┬││    ├─┤├─┤├─┘├─┘├┤ │││└─┐
#     ┴ ┴ ┴┴└─┘  ┴└─┘  └┴┘┴ ┴└─┘┴└─└─┘   ┴ ┴ ┴└─┘  ┴ ┴┴ ┴└─┘┴└─┘  ┴ ┴┴ ┴┴  ┴  └─┘┘└┘└─┘

test_root
SQL_PASS=$(systemd-ask-password Please enter a root password for MySQL: )

echo "And so it begins... "

logging
LOGFILE="/var/log/install_lamp/$(date +%Y%m%d-%H%M%S)"

install_apache
install_mysql
install_php

case $MW in
  -mw)
  install_mw
  case $MW_INTERACTIVE_CONFIG in
    -i)
    interactive_config_mw
    exit 0
    ;;
    *)
    exit 0
    ;;
    esac
  ;;
  *)
  exit 0
  ;;
esac

#!/bin/bash
PN=`basename "$0"`


#####################################################################################
# configuration
#####################################################################################
FOLDER_PATH=/var/www
CONF_PATH=/etc/apache2
REP_USER=git
REP_GROUP=www-data
REP_DOMAIN="http://<yourdomain>"


#####################################################################################
# Usage
#####################################################################################
Usage()
{
  echo "$PN - Script to simplify the configuration of a git repository."
  echo "It adds the apache configuration, password files and create empty"
  echo "git repositorie(s)"
  echo ""
  echo "usage: $PN [-t] <name>"
  echo ""
  echo "Sample: $PN my-repository"
  echo "# this will create an apache entry to access the repository"
}


#####################################################################################
# Create repository
#####################################################################################
reloadConfig()
{
  echo ">Reload apache and systemctl"
  sudo su - -c "service apache2 reload"
  sudo su - -c "systemctl daemon-reload"
}


#####################################################################################
# Get user credentials
#####################################################################################
getUserCredentials()
{
  # get credentials
  read -p 'Username: ' username
  read -sp 'Password: ' password
  echo ""
}


#####################################################################################
# create apache access
#####################################################################################
createApacheAccess()
{
  if [ -d "$FOLDER_PATH/$1" ]; then
    echo "This gitfolder $FOLDER_PATH/$1 alredy exist!"
    return
  fi

  echo "The url is $REP_DOMAIN/$1/"

  getUserCredentials
  echo ""
  if ! [ -n "$username" ]; then
    echo "Invalid empty username!"
    exit 1
  fi
  if ! [ -n "$password" ]; then
    echo "Invalid empty password!"
    exit 1
  fi

  sudo su - -c "echo \>Create folter"
  sudo su - -c "mkdir -p $FOLDER_PATH/$1"
  sudo su - -c "chown -R ${REP_USER}:${REP_GROUP} $FOLDER_PATH/$1"

  # be sure folders existing (also in test)
  sudo su - -c "mkdir -p $CONF_PATH/conf-available" >/dev/null 2>&1
  sudo su - -c "mkdir -p $CONF_PATH/conf-enabled" >/dev/null 2>&1
  sudo su - -c "mkdir -p $CONF_PATH/gitpasswd" >/dev/null 2>&1

  echo ">Create new Virtual Host"
  cat <<< "<Location \"/$1\">
DAV on
AuthType Basic
AuthName \"Git repositories for $1\"
AuthUserFile $CONF_PATH/gitpasswd/$1.passwd
Require valid-user
  </Location>" > /tmp/$1.conf$$
  sudo su - -c "cat /tmp/$1.conf$$ > $CONF_PATH/conf-available/$1.conf && rm /tmp/$1.conf$$"

  sudo su -c "ln -s $CONF_PATH/conf-available/$1.conf $CONF_PATH/conf-enabled/$1.conf"

  echo ">Create htpsswd file"
  echo -n ">"
  sudo su - -c "htpasswd -c -b $CONF_PATH/gitpasswd/$1.passwd $username $password"
  reloadConfig
}


#####################################################################################
# Create repository
#####################################################################################
createRepo()
{
  if [ -d "$FOLDER_PATH/$1/$2.git" ]; then
    echo "This repository $FOLDER_PATH/$1/$2.git alredy exist!"
    return
  fi

  echo "The url is $REP_DOMAIN/$1/$2.git"
  echo ">Creating repositroy $2.git .."
  sudo su $REP_USER -c "mkdir -p $FOLDER_PATH/$1/$2.git"

  # init git repository
  echo -n ">"
  sudo su $REP_USER -c "cd $FOLDER_PATH/$1/$2.git && git init --bare --shared"
  sudo su $REP_USER -c "cd $FOLDER_PATH/$1/$2.git && git update-server-info"
  sudo su $REP_USER -c "cd $FOLDER_PATH/$1/$2.git && chmod 775 -R *"
  reloadConfig
}


#####################################################################################
#
#####################################################################################
askContinue()
{
  read -p "Continue (y/n)? " choice

  # change to lower case
  choice=$(echo $choice | tr '[:upper:]' '[:lower:]')
}


#####################################################################################
# main
#####################################################################################
NAME=""
ADD_USER="false"
setup_git=0
while [ $# -gt 0 ]
do
  case "$1" in
    -s)	setup_git=1 ;;  
    -t)	FOLDER_PATH=/tmp/repo/www && CONF_PATH=/tmp/repo/apache2 ;;
    -u)	ADD_USER="true" ;;
    -h)	Usage; exit 1 ;;
    -*)	Usage; exit 1 ;;
    *)	NAME="$NAME$1"; break ;;
  esac
  shift
done

if ! [ -n "$NAME" ]; then
  echo "Invalid parameter, missing name!"
  exit 1
fi

if [ $setup_git -eq 1 ]; then
  sudo su - -c "cat <<< \"LoadModule dav_module libexec/httpd/libdav.so
AddModule mod_dav.c
DAVLockDB \"/usr/local/apache2/temp/DAV.lock\"\" > /etc/apache2/httpd.conf"

  sudo a2enmod dav_fs
  sudo systemctl restart apache2
  sudo useradd $REP_USER
  sudo chown -R $REP_USER:$REP_GROUP $FOLDER_PATH
fi

createApacheAccess $NAME

while true
do
  echo ""
  echo "Do you want to create an additional repository?"
  askContinue
  if [ "$choice" == "y" ]; then
    read -p 'Reponame: ' reponame
    if ! [ -n "$reponame" ]; then
      echo "Invalid empty reponame!"
    else
      echo ""
      createRepo $NAME $reponame
    fi
  else
    break;
  fi
done

if [ "$ADD_USER" == "true" ]; then
  echo ""
  getUserCredentials
  echo -n ">"
  sudo su - -c "htpasswd -b $CONF_PATH/gitpasswd/$NAME.passwd $username $password"
fi


#####################################################################################
# EOF
#####################################################################################

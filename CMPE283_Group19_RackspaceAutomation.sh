#!/bin/bash
# =============================================================================
# - title        : Migrating Servers Using RSYNC on Rackspace
# - description  : For migrating the data between instances.
# - License      : General Public License
# - author       : CMPE283-Virtualization Technologies (Group-19)
# - date         : 2014-04-29
# - version      : 1.0
# - usage        : bash rsrsyncLive.sh
# - OS Supported : Ubuntu 
# =============================================================================

# Trap Errors and or Exits
trap "CONTROL_C" SIGINT
trap "EXIT_ERROR Line Number: ${LINENO} Exit Code: $?" ERR

# Set modes
set -u
set -e

# Root user check for install 
# =============================================================================
function CHECKFORROOT() {
  USERCHECK=$( whoami  )
  if [ "$(id -u)" != "0" ]; then
    echo -e "This script must be run as ROOT
You have attempted to run this as ${USERCHECK}
use sudo $0 or change to root.
"
    exit 1
  fi
}


# Root user check for install 
# =============================================================================
function CREATE_SWAP() {

  cat > /tmp/swap.sh <<EOF
#!/usr/bin/env bash
if [ ! "\$(swapon -s | grep -v Filename)" ];then
  SWAPFILE="/SwapFile"
  if [ -f "\${SWAPFILE}" ];then
    swapoff -a
    rm \${SWAPFILE}
  fi
  dd if=/dev/zero of=\${SWAPFILE} bs=1M count=1024
  chmod 600 \${SWAPFILE}
  mkswap \${SWAPFILE}
  swapon \${SWAPFILE}
fi
EOF

  cat > /tmp/swappiness.sh <<EOF
#!/usr/bin/env bash
SWAPPINESS=\$(sysctl -a | grep vm.swappiness | awk -F' = ' '{print \$2}')
if [ "\${SWAPPINESS}" != 60 ];then
  sysctl vm.swappiness=60
fi
EOF

  if [ ! "$(swapon -s | grep -v Filename)" ];then
    chmod +x /tmp/swap.sh
    chmod +x /tmp/swappiness.sh
    /tmp/swap.sh && /tmp/swappiness.sh
  fi
}


# Trap a CTRL-C Command 
# =============================================================================
function CONTROL_C() {
  set +e
  echo -e "
\033[1;31mExiting.....! \033[0m
\033[1;36mYou Pressed [ CTRL C ] \033[0m
"
  QUIT
  if [ "${INFLAMMATORY}" == "True" ];then 
    echo -e "Something is wrong..."
  fi

  echo "Deleting all the temporary files."
  EXIT_ERROR
}


# Tear down
# =============================================================================
function QUIT() {
  set +e
  set -v

  echo 'Removing Temp Files'
  GENFILES="/tmp/intsalldeps.sh /tmp/known_hosts /tmp/postopfix.sh /tmp/swap.sh"

  for temp_file in ${EXCLUDE_FILE} ${GENFILES} ${SSH_KEY_TEMP};do 
    [ -f ${temp_file} ] && rm ${temp_file}
  done

  set +v
}

function EXIT_ERROR() {
  # Print Messages
  echo -e "ERROR! Sorry About that... 
Here is what I know: $@
"
  QUIT
  exit 1
}


# Set the Source and Origin Drives
# =============================================================================
function GETDRIVE1() {
  read -p "
Press [Enter] to Continue accepting the normal Rackspace Defaults 
or you may Specify a Source Directory: " DRIVE1
  DRIVE1=${DRIVE1:-"/"}

  if [ ! -d "${DRIVE1}" ];then
    echo "The path or Device you specified does not exist."
    read -p "Specify \033[1;33mYOUR\033[0m Source Mount Point : " DRIVE1
    DRIVE1=${DRIVE1:-"/"}
    GETDRIVE1
  fi
}

function GETDRIVE2() {
  echo -e "
Here you Must Specify the \033[1;33mTarget\033[0m mount point.  This is 
\033[1;33mA MOUNT\033[0m Point. Under Normal Rackspace Circumstances this drive
would be \"/\" or \"/dev/xvdb1\". Remember, there is no way to check that the 
directory or drive exists. This means we are relying on \033[1;33mYOU\033[0m to
type correctly.
"
  read -p "Specify Destination Drive or press [Enter] for the Default : " DRIVE2
  DRIVE2=${DRIVE2:-"/dev/xvdb1"}
}


# Get the Target IP
# =============================================================================
function GETTIP() {
  MAX_RETRIES=${MAX_RETRIES:-5}
  RETRY_COUNT=0
  read -p "If you are ready to proceed enter your Target IP address : " TIP
  TIP=${TIP:-""}
  if [ -z "${TIP}" ];then
    echo "No IP was provided, please try again"
    unset TIP
    RETRY_COUNT=$((${RETRY_COUNT}+1))
    if [ ${RETRY_COUNT} -ge ${MAX_RETRIES} ];then
      EXIT_ERROR "Hit maximum number of retries, giving up."
    else
      GETTIP
    fi
  else
    unset MAX_RETRIES
  fi
}

# When UNKNOWN
# =============================================================================
function WHENUNKNOWN() {
    echo -e "
\033[1;31mWARNING! \033[0m
I could not determine your OS Type. This Application has only been tested on : 
\033[1;31mUbuntu\033[0m, \
You may need to edit the file '\033[1;31m/etc/issue\033[0m' in an effort to
correct the OS detection issues
"
  if [ "${INFLAMMATORY}" == "True" ];then 
      echo -e "Check OS Settings."
      sleep 2
  fi
  exit 1
}


# When Debian based distros
# =============================================================================
function WHENUBUNTU() {
  echo -e "\033[1;31mUbuntu Based System Detected\033[0m"

  echo "Performing Package Update"
  apt-get update > /dev/null 2>&1

  echo "Installing rsync Package."
  apt-get -y install rsync > /dev/null 2>&1

  cat > /tmp/intsalldeps.sh <<EOF
#!/usr/bin/env bash
# Debian Dep Script
apt-get update > /dev/null 2>&1
apt-get -y install rsync > /dev/null 2>&1
EOF

if [ "${INFLAMMATORY}" == "True" ];then 
    echo -e "Great choice by choosing a Ubuntu Based Distro. 
The Ubuntu way is by far the best way."; 
    sleep 1
  fi
}


# Do Distro Check
# =============================================================================
function DISTROCHECK() {
  # Check the Source Distro
  if [ -f /etc/issue ];then
   
    if [ "$(grep -i '\(debian\)\|\(ubuntu\)' /etc/issue)" ];then
      WHENUBUNTU
     else
      WHENUNKNOWN
    fi
else 
	WHENUNKNOWN
 fi
}

# RSYNC Check for Version and Set Flags
# =============================================================================
function RSYNCCHECKANDSET() {
  if [ ! $(which rsync) ];then
    echo -e "The \033[1;36m\"rsync\"\033[0m command was not found. The automatic 
  Installation of rsync failed so that means you NEED to install it."
    exit 1
  else
    RSYNC_VERSION_LINE=$(rsync --version | grep -E "version\ [0-9].[0-9].[0-9]")
    RSYNC_VERSION_NUM=$(echo ${RSYNC_VERSION_LINE} | awk '{print $3}')
    RSYNC_VERSION=$(echo ${RSYNC_VERSION_NUM} | awk -F'.' '{print $1}')
    if [ "${RSYNC_VERSION}" -ge "3" ];then
      RSYNC_VERSION_COMP="yes"
    fi
  fi
  
  # Set RSYNC Flags
  if [ "${RSYNC_VERSION_COMP}" == "yes" ];then 
    RSYNC_FLAGS='aHEAXSzx'
    echo "Using RSYNC <= 3.0.0 Flags."
  else 
    RSYNC_FLAGS='aHSzx'
    echo "Using RSYNC >= 2.0.0 but < 3.0.0 Flags."
  fi
}

# Dep Scripts
# =============================================================================
function KEYANDDEPSEND() {
  echo -e "\033[1;36mBuilding Key Based Access for the target host\033[0m"
  ssh-keygen -t rsa -f ${SSH_KEY_TEMP} -N ''

  # Making backup of known_host
  if [ -f "/root/.ssh/known_hosts" ];then
    cp /root/.ssh/known_hosts /root/.ssh/known_hosts.${DATE}.bak
  fi

  echo -e "Please Enter the Password of the \033[1;33mTARGET\033[0m Server."
  ssh-copy-id -i ${SSH_KEY_TEMP} root@${TIP}

  if [ -f /tmp/intsalldeps.sh ];then
    echo -e "Passing RSYNC Dependencies to the \033[1;33mTARGET\033[0m Server."
    scp -i ${SSH_KEY_TEMP} /tmp/intsalldeps.sh root@${TIP}:/root/
  fi

  if [ -f /tmp/swap.sh ];then
    echo -e "Passing  Swap script to the \033[1;33mTARGET\033[0m Server."
    scp -i ${SSH_KEY_TEMP} /tmp/swap.sh root@${TIP}:/root/
  fi
  
  if [ -f /tmp/swappiness.sh ];then
    echo -e "Passing  Swappiness script to the \033[1;33mTARGET\033[0m Server."
    scp -i ${SSH_KEY_TEMP} /tmp/swappiness.sh root@${TIP}:/root/
  fi
}

# Commands 
# =============================================================================
function RUNPREPROCESS() {
  echo -e "Running Dependency Scripts on the \033[1;33mTARGET\033[0m Server."
  SCRIPTS='[ -f "swap.sh" ] && bash swap.sh;
           [ -f "swappiness.sh" ] && bash swappiness.sh;
           [ -f "intsalldeps.sh" ] && bash intsalldeps.sh'
  ssh -i ${SSH_KEY_TEMP} -o UserKnownHostsFile=/dev/null \
                         -o StrictHostKeyChecking=no root@${TIP} \
                         "${SCRIPTS}" > /dev/null 2>&1
}


function RUNRSYNCCOMMAND() {
  set +e
  MAX_RETRIES=${MAX_RETRIES:-5}
  RETRY_COUNT=0

  # Set the initial return value to failure
  false

  while [ $? -ne 0 -a ${RETRY_COUNT} -lt ${MAX_RETRIES} ];do
    RETRY_COUNT=$((${RETRY_COUNT}+1))
    ${RSYNC} -e "${RSSH}" -${RSYNC_FLAGS} --progress \
                                          --exclude-from="${EXCLUDE_FILE}" \
                                          --exclude "${SSHAUTHKEYFILE}" \
                                          / root@${TIP}:/
    echo "Resting for 5 seconds..."
    sleep 5
  done
  
  if [ ${RETRY_COUNT} -ge ${MAX_RETRIES} ];then
    EXIT_ERROR "Hit maximum number of retries, giving up."
  fi

  unset MAX_RETRIES
  set -e
}

function RUNMAINPROCESS() {

  echo -e "\033[1;36mNow performing the Copy\033[0m"

  RSYNC="$(which rsync)"
  RSSH_OPTIONS="-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no"
  RSSH="ssh -i ${SSH_KEY_TEMP} ${RSSH_OPTIONS}"

  RUNRSYNCCOMMAND

  echo -e "\033[1;36mNow performing Final Sweep\033[0m"

  RSYNC_FLAGS="${RSYNC_FLAGS} --checksum"
  RUNRSYNCCOMMAND
}

# Say  something nice and exit
# =============================================================================
function IAMDONE() {
  echo "all Done."

  if [ "${INFLAMMATORY}" == "True" ];then 
    echo -e "I hope you enjoyed all of my hard work... :)"
  fi

  GITHUBADDR="\033[1;36mhttps://github.com/kshitijgupta/CMPE283Sync.git033[0m"
  
  echo -e "
Stop by ${GITHUBADDR} for other random tidbits...
"

  if [ "${INFLAMMATORY}" == "True" ];then 
    echo -e "You have reached the end of script...\033[1;33m This concludes the demo for RSYNC Automation\033[0m, :)
"
  fi
}



# Run Script
# =============================================================================
INFLAMMATORY=${INFLAMMATORY:-"False"}
VERBOSE=${VERBOSE:-"False"}
DEBUG=${DEBUG:-"False"}

# The Date as generated by the Source System
DATE=$(date +%y%m%d%H)

# The Temp Working Directory
TEMPDIR='/tmp'

# Name of the Temp SSH Key we will be using.
SSH_KEY_TEMP="${TEMPDIR}/tempssh.${DATE}"

# ROOT SSH Key File
SSHAUTHKEYFILE='/root/.ssh/authorized_keys'

# General Exclude List; The exclude list is space Seperated
EXCLUDE_LIST='/boot /dev/ /etc/conf.d/net /etc/fstab /etc/hostname 
/etc/HOSTNAME /etc/hosts /etc/issue /etc/init.d/nova-agent* /etc/mdadm* 
/etc/mtab /etc/network* /etc/network/* /etc/networks* /etc/network.d/*
/etc/rc.conf /etc/resolv.conf /etc/selinux/config /etc/sysconfig/network* 
/etc/sysconfig/network-scripts/* /etc/ssh/ssh_host_dsa_key 
/etc/ssh/ssh_host_rsa_key /etc/ssh/ssh_host_dsa_key.pub 
/etc/ssh/ssh_host_rsa_key.pub /etc/udev/rules.d/* /lock /net /sys /tmp 
/usr/sbin/nova-agent* /usr/share/nova-agent* /var/cache/yum/* '

# Allow the user to add excludes to the general Exclude list
USER_EXCLUDES=${USER_EXCLUDES:-""}


# Extra Exclude File 
EXCLUDE_FILE='/tmp/excludeme.file'

# Building Exclude File - DONT TOUCH UNLESS YOU KNOW WHAT YOU ARE DOING
# =============================================================================
if [ "${VERBOSE}" == "True" ];then
  set -v
fi

if [ "${DEBUG}" == "True" ];then
  set -x
fi

if [ "${USER_EXCLUDES}" ];then
  EXCLUDE_LIST+=${USER_EXCLUDES}
fi

EXCLUDEVAR=$(echo ${EXCLUDE_LIST} | sed 's/\ /\\n/g')

if [ -f ${EXCLUDE_FILE} ];then
  rm ${EXCLUDE_FILE}
fi

echo -e "${EXCLUDEVAR}" | tee -a ${EXCLUDE_FILE}

# Check that we are the root User
CHECKFORROOT

# Clear the screen to get ready for work
clear

if [ "${INFLAMMATORY}" == "True" ];then 
  echo -e "Inflammatory mode has been enabled... 
The application will now be really opinionated...
\033[1;33mYOU\033[0m have been warned...
" 
fi

  echo -e "This Utility Moves a \033[1;36mLIVE\033[0m System to an other System.
This application will work on \033[1;36mAll\033[0m Linux systems using RSYNC.
Before performing this action you \033[1;35mSHOULD\033[0m be in a screen
session.
"

sleep 1

echo -e "This Utility does an \033[1;32mRSYNC\033[0m copy of instances over the 
network. As such, I recommend that you perform this Migration Action on SNET 
(Internal IP), however any Network will work. 
Here is why I make this recommendation:
Service Net = \033[1;32mFREE\033[0m Bandwidth.
Public Net  = \033[1;35mNOT FREE\033[0m Bandwidth
" 

# If the Target IP is not set, ask for it
GETTIP

# Allow the user to specify the source drive
GETDRIVE1
GETDRIVE2

# check what distro we are running on
DISTROCHECK

# Make sure we can swap 
CREATE_SWAP

# Check RSYNC version and set the in use flags
RSYNCCHECKANDSET

# Create a Key for target access and send over a dependency script
KEYANDDEPSEND

# Removing known_host entry made by script
if [ -f "/root/.ssh/known_hosts" ];then
  cp /root/.ssh/known_hosts /tmp/known_hosts
  sed '$ d' /tmp/known_hosts > /root/.ssh/known_hosts
fi

RUNPREPROCESS
                       
RUNMAINPROCESS


echo -e "\033[1;36mThe target Instance is being rebooted\033[0m"

ssh -i ${SSH_KEY_TEMP} -o UserKnownHostsFile=/dev/null \
                       -o StrictHostKeyChecking=no root@${TIP} \
                       "shutdown -r now"

echo -e "If you were copying something that was not a Rackspace Cloud Server, 
You may need to ensure that your setting are correct, and the target is healthy
"


echo -e "Other wise you are good to go, and the target server should have been 
rebooted. If all is well, you should now be able to enjoy your newly cloned 
Virtual Instance.
"

# End of synchronization
IAMDONE

# Teardown what I setup on the source node and exit
QUIT

exit 0


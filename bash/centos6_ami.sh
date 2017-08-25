#!/bin/bash
# Script to generate centos 6 instance store AMIs. A lot of base code was inspired
# by centos7-ami creation scripts from the following authors:
# * https://github.com/adragomir/centos-7-ami
# * https://github.com/mkocher/ami_building/
# Maintainer bbondarenko@modusagency.com


REQUIRED_RPMS=(yum-plugin-fastestmirror ruby ruby-devel kpartx)
CFG_FILE=$HOME/.centos-ami-builder

## {{{  Builder functions ########################################################
function build_ami() {
  make_build_dirs
  make_img_file
  mount_img_file
  install_packages
  make_fstab
  setup_network
  configure_grub
  personalize_ami
#  enter_shell
  clean_up
  unmount_all
  bundle_ami
  upload_ami
  register_ami
  quit
}
#}}}
# {{{ function make_build_dirs() {
# Create the build hierarchy.  Unmount existing paths first, if need by
function make_build_dirs() {
  AMI_ROOT="${BUILD_ROOT}/${AMI_NAME}"
  AMI_IMG="${AMI_ROOT}/${AMI_NAME}.img"
  AMI_MNT="${AMI_ROOT}/mnt"
  AMI_OUT="${AMI_ROOT}/out"
  
  AMI_DEV=hda
  AMI_DEV_PATH=/dev/mapper/${AMI_DEV}
  AMI_PART_PATH=${AMI_DEV_PATH}1
  
  output "Creating build hierarchy in ${AMI_ROOT}..."
  
  if grep -q "^[^ ]\+ ${AMI_MNT}" /proc/mounts; then
    yesno "${AMI_MNT} is already mounted; unmount it"
    unmount_all
  fi
  
  mkdir -p ${AMI_MNT} ${AMI_OUT} || fatal "Unable to create create build hierarchy"
}
#}}}
# {{{ function ischroot()
function ischroot() {
[ "$(stat -c %d:%i /)" != "$(stat -c %d:%i /proc/1/root/./)" ]
}
#}}}
# {{{ Create our image file
function make_img_file() {
  output "Creating image fille ${AMI_IMG}..."
  if [[ ${AMI_TYPE} == 'pv' ]]; then
    [[ -f ${AMI_IMG} ]] && yesno "${AMI_IMG} already exists; overwrite it"
    # Create a sparse file
    dd if=/dev/zero status=none of=${AMI_IMG} bs=1M count=1 seek=${AMI_SIZE} || \
      fatal "Unable to create image file: ${AMI_IMG}"
    # Set up EXT4 on the image file
    mkfs.ext4 -F -j ${AMI_IMG}  || \
      fatal "Unable create file system on ${AMI_IMG}"
    sync
    LOOP_DEV=$(losetup -f)
    losetup ${LOOP_DEV} ${AMI_IMG} || fatal "Failed to bind ${AMI_IMG} to ${LOOP_DEV}."
  else
    if [[ -e ${AMI_DEV_PATH} ]]; then
      yesno "${AMI_DEV_PATH} is already defined; redefine it"
      undefine_hvm_dev
    fi
    [[ -f ${AMI_IMG} ]] && yesno "${AMI_IMG} already exists; overwrite it"

    # Create a sparse file
    rm -f ${AMI_IMG} && sync
    dd if=/dev/zero status=none of=${AMI_IMG} bs=1M count=1 seek=$((${AMI_SIZE} - 1))  || \
      fatal "Unable to create image file: ${AMI_IMG}"

    # Create a primary partition
    parted ${AMI_IMG} --script -- "unit s mklabel msdos mkpart primary 2048 100% set 1 boot on print quit" \
       || fatal "Unable to create primary partition for ${AMI_IMG}"
    sync; udevadm settle

    # Set up the the image file as a loop device so we can create a dm volume for it
    LOOP_DEV=$(losetup -f)
    losetup ${LOOP_DEV} ${AMI_IMG} || fatal "Failed to bind ${AMI_IMG} to ${LOOP_DEV}."
    
    # Create a device mapper volume from our loop dev
    DM_SIZE=$((${AMI_SIZE} * 2048))
    DEV_NUMS=$(cat /sys/block/$(basename ${LOOP_DEV})/dev)
    dmsetup create ${AMI_DEV} <<< "0 ${DM_SIZE} linear ${DEV_NUMS} 0" || \
      fatal "Unable to define devicemapper volume ${AMI_DEV_PATH}"
    kpartx -s -a ${AMI_DEV_PATH} || \
      fatal "Unable to read partition table from ${AMI_DEV_PATH}"
    udevadm settle

    # Create ext4 partition and set up the label
    mkfs.ext4 -F -j ${AMI_PART_PATH}  || \
      fatal "Unable to create EXT4 filesystem on ${AMI_PART_PATH}"
    tune2fs -L "/" ${AMI_PART_PATH} || \
      fatal "Unable to assign LABEL '/' to ${AMI_PART_PATH}"
    sync
  fi
}
#}}}
# {{{ Mount the image file and create and mount all of the necessary devices
function mount_img_file()
{
  output "Mounting image file ${AMI_IMG} at ${AMI_MNT}..."

  if [[ ${AMI_TYPE} == 'pv' ]]; then
    mount  ${LOOP_DEV} ${AMI_MNT}
  else
    mount ${AMI_PART_PATH} ${AMI_MNT}
  fi
  # check mount point failures
  mountpoint ${AMI_MNT} || fatal "Mount process failed for ${AMI_MNT}"
  if [[ ${AMI_TYPE} == "hvm" ]]; then
    install_grub
  fi

  # Make our chroot directory hierarchy
    mkdir -p ${AMI_MNT}/{dev,etc,proc,sys,var/{cache,log,lock,lib/rpm}}

/sbin/MAKEDEV -d ${AMI_MNT}/dev -x console
/sbin/MAKEDEV -d ${AMI_MNT}/dev -x null
/sbin/MAKEDEV -d ${AMI_MNT}/dev -x zero
/sbin/MAKEDEV -d ${AMI_MNT}/dev -x urandom

mount -o bind /dev      ${AMI_MNT}/dev
mount -o bind /dev/shm  ${AMI_MNT}/dev/shm
mount -o bind /proc     ${AMI_MNT}/proc
mount -o bind /sys      ${AMI_MNT}/sys
mount -o bind /dev/pts  ${AMI_MNT}/dev/pts
}
#}}}
# {{{ fucntion latest_version(){
# report latest CentOS version, based on the major version
function latest_version(){
  curl -s http://mirrors.kernel.org/centos/${LINUX_VERSION:0:1}/os/x86_64/isolinux/isolinux.cfg | grep 'Welcome to CentOS'| sed 's/[^0-9.]//g'
}
#}}}
# {{{ Install packages into AMI via yum 
# if user supplied version is in the form N.N use the
# vault URL to get the correct packages
function install_packages() {
  output "Installing ${LINUX_VERSION} packages into ${AMI_MNT}..."
_v=$(latest_version)
  [ ${#LINUX_VERSION} -gt 1 -a ${LINUX_VERSION:-x} != ${_v:-y} ] && _base="http://vault.centos.org/" || _base="http://mirror.centos.org/centos/"
  # Create our YUM config
  YUM_CONF=${AMI_ROOT}/yum.conf
cat > $YUM_CONF <<-EOT
[main]
reposdir=
plugins=0

[base]
name=CentOS-${LINUX_VERSION} - Base
baseurl=${_base}${LINUX_VERSION}/os/\$basearch/
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-6

#released updates 
[updates]
name=CentOS-${LINUX_VERSION} - Updates
baseurl=${_base}${LINUX_VERSION}/updates/\$basearch/
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-6

#additional packages that may be useful
[extras]
name=CentOS-${LINUX_VERSION} - Extras
baseurl=${_base}${LINUX_VERSION}/extras/\$basearch/
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-6

#additional packages that extend functionality of existing packages
[centosplus]
name=CentOS-${LINUX_VERSION} - Plus
baseurl=${_base}${LINUX_VERSION}/centosplus/\$basearch/
gpgcheck=1
enabled=0
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-6

#contrib - packages by Centos Users
[contrib]
name=CentOS-${LINUX_VERSION} - Contrib
baseurl=${_base}${LINUX_VERSION}/contrib/\$basearch/
gpgcheck=1
enabled=0
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-6
EOT
  
  # Install base pacakges
  yum --config=$YUM_CONF --installroot=${AMI_MNT} --quiet --assumeyes groupinstall Base
  [[ -f ${AMI_MNT}/bin/bash ]] || fatal "Failed to install base packages into ${AMI_MNT}"
  
  # Install additional packages that we are definitely going to want
  yum --config=$YUM_CONF --installroot=${AMI_MNT} --assumeyes install \
    grub dhclient ntp e2fsprogs sudo \
    openssh-clients vim postfix yum-plugin-fastestmirror sysstat \
    microcode_ctl bzip2 cloud-init openssh-server
  
#  yum --config=$YUM_CONF --installroot=${AMI_MNT} --assumeyes erase \
#  iptables* 
  # Enable our required services
  for s in  rsyslog ntpd sshd cloud-init cloud-init-local cloud-config cloud-final
  do
    chroot ${AMI_MNT} chkconfig ${s} on
  done
  # Disable thing we do not want atm, make it into the list
  for s in  lvm2-monitor
  do
    chroot ${AMI_MNT} chkconfig ${s} off
  done
  # setup bash stuff 
  cp /etc/skel/.bash* ${AMI_MNT}/root/

}
#}}}
# {{{ Create the AMI's fstab
function make_fstab() {
  output "Creating fstab..."
  if [[ ${AMI_TYPE} == "pv" ]]; then
    FSTAB_ROOT="/dev/xvde1    /   ext4  defaults 1  1"
    FSTAB_PVM="/dev/xvde2     /mnt/vol1   ext4  defaults  0 0
    /dev/xvde3    swap    swap  defaults 0 0"
  else
    FSTAB_ROOT="LABEL=/   /   ext4  defaults 1 1"
  fi

cat > ${AMI_MNT}/etc/fstab <<-EOT
$FSTAB_ROOT
none /dev/pts devpts gid=5,mode=620 0 0
none /dev/shm tmpfs defaults 0 0
none /proc proc defaults 0 0
none /sys sysfs defaults 0 0
$FSTAB_PVM
EOT
}
#}}}
# {{{ Create our eth0 ifcfg script and our SSHD config
function setup_network() {
  output "Setting up network..."

  # Create our DHCP-enabled eth0 config
cat > ${AMI_MNT}/etc/sysconfig/network-scripts/ifcfg-eth0 <<-EOT
DEVICE="eth0"
ONBOOT=yes
TYPE=Ethernet
BOOTPROTO=dhcp
DEFROUTE=yes
PEERDNS=yes
PEERROUTES=yes
IPV4_FAILURE_FATAL=yes
IPV6INIT=no
EOT

cat > ${AMI_MNT}/etc/sysconfig/network <<-EOT
NETWORKING=yes
HOSTNAME=localhost.localdomain
EOT

# Amend our SSHD config
cat >> ${AMI_MNT}/etc/ssh/sshd_config <<-EOT
PasswordAuthentication no
UseDNS no
PermitRootLogin without-password
EOT

  chroot ${AMI_MNT} chkconfig network on
}
#}}}
# {{{ function install_grub()
function install_grub() {
  mkdir -p ${AMI_MNT}/boot/grub
  echo "(hd0) ${AMI_DEV_PATH}" > ${AMI_MNT}/boot/grub/device.map
  grub-install --root-directory=${AMI_MNT} ${AMI_DEV_PATH} || fatal "Grub install failed!"
}
#}}}
# {{{ Create the grub config
function configure_grub() {
  
  AMI_BOOT_PATH=${AMI_MNT}/boot
  AMI_KERNEL_VER=$(ls $AMI_BOOT_PATH | egrep -o '2\..*' | head -1)

  # Install our grub.conf for only the PV machine, as it is needed by PV-GRUB
  if [[ ${AMI_TYPE} == "pv" ]]; then
    output "Installing PV-GRUB config..."
    AMI_GRUB_PATH=$AMI_BOOT_PATH/grub
    mkdir -p $AMI_GRUB_PATH
cat > $AMI_GRUB_PATH/grub.conf <<-EOT
default=0
timeout=0
hiddenmenu

title CentOS Linux ($AMI_KERNEL_VER) ${LINUX_VERSION} ($CLIENT)
    root (hd0)
    kernel /boot/vmlinuz-$AMI_KERNEL_VER ro root=/dev/xvde1 rd_NO_PLYMOUTH
    initrd /boot/initramfs-${AMI_KERNEL_VER}.img
EOT

  # Install grub only for the HVM image, as the PV image uses PV-GRUB
  else
    output "Configuring GRUB..."
    AMI_GRUB_PATH=$AMI_BOOT_PATH/grub

cat > $AMI_GRUB_PATH/grub.conf <<-EOT
default=0
timeout=0
hiddenmenu

title CentOS Linux ($AMI_KERNEL_VER) ${LINUX_VERSION} ($CLIENT)
    root (hd0,0)
    kernel /boot/vmlinuz-$AMI_KERNEL_VER ro root=LABEL=/ rd_NO_PLYMOUTH console=ttyS0 xen_pv_hvm=enable
    initrd /boot/initramfs-${AMI_KERNEL_VER}.img
EOT

  fi
    ln -sf /boot/grub/grub.conf $AMI_GRUB_PATH/menu.lst
}
#}}}
# {{{ Allow user to make changes to the AMI outside of the normal build process
function enter_shell() {
  output "Entering AMI chroot; customize as needed.  Enter 'exit' to finish build."
  mountpoint ${AMI_MNT} || fatal "${AMI_MNT} not a mountpoint"
  cp /etc/resolv.conf ${AMI_MNT}/etc
  PS1="[${AMI_NAME}-chroot \W]# " chroot ${AMI_MNT} &> /dev/tty
  rm -f ${AMI_MNT}/{etc/resolv.conf,root/.bash_history}
}
#}}}
# {{{ Personalize the AMI
function personalize_ami(){
  ischroot || sed -i 's/\([ \t]\+name: \).*/\1modus/; s/\([ \t]\+gecos: \).*/\1Modus User/' ${AMI_MNT}/etc/cloud/cloud.cfg && chroot ${AMI_MNT} sed -i 's/\([ \t]\+name: \).*/\1modus/; s/\([ \t]\+gecos: \).*/\1Modus User/' /etc/cloud/cloud.cfg

}
#}}}
# {{{ function clean_up()
function clean_up(){
  ischroot && fatal "Must run outside the chroot environment"
  chroot ${AMI_MNT} yum --quiet --assumeyes clean packages
  rm -fr ${AMI_MNT}/{root/.bash_history,etc/resolv.conf,var/cache/yum,var/lib/yum}
}
#}}}
# {{{ Unmount all of the mounted devices
function unmount_all() {
  mountpoint ${AMI_MNT} || fatal "${AMI_MNT} not a mountpoint"
  for _m in ${AMI_MNT}/{dev/pts,dev/shm,dev,proc,sys,}
  do
    mountpoint ${_m} && umount -ldf ${_m} || fatal "${_m} not a mount point or failed to unmount"
  done
  sync
  grep -q "^[^ ]\+ ${AMI_MNT}" /proc/mounts && \
    fatal "Failed to unmount all devices mounted under ${AMI_MNT}!"

  # Also undefine our hvm devices if they are currently set up with this image file
  mountpoint ${AMI_MNT} &&  umount ${AMI_MNT}
   
 
  losetup -a | grep -q ${AMI_NAME} && ([ ${AMI_TYPE} == "pv" ] && losetup -d ${LOOP_DEV} || undefine_hvm_dev)
}
#}}}
# {{{ Remove the dm volume and loop dev for an HVM image file
function undefine_hvm_dev() {
  # undefine hda1
  kpartx -d ${AMI_DEV_PATH}  || fatal "Unable remove partition map for ${AMI_DEV_PATH}"
  sync; udevadm settle
  
  dmsetup remove ${AMI_DEV}  || fatal "Unable to remove devmapper volume for ${AMI_DEV}"
  sync; udevadm settle
  # remove all loop devices associated with this image
  losetup -j ${AMI_IMG}|while read _line
  do
    losetup -d $(echo "${_line}"| sed 's/:.*//') || fatal "Unable to remove $(echo "${_line}"| sed 's/:.*//')"
  done
  sleep 1; sync; udevadm settle
}
#}}}
# {{{ Create an AMI bundle from our image file
function bundle_ami() {
  output "Bundling AMI for upload..."
  RUBYLIB=/usr/lib/ruby/site_ruby/ ec2-bundle-image --privatekey ${AWS_PRIVATE_KEY} --cert ${AWS_CERT} \
    --user $AWS_USER --image ${AMI_IMG} --prefix ${AMI_NAME} --destination ${AMI_OUT} --arch x86_64 || \
    fatal "Failed to bundle image!"
  AMI_MANIFEST=${AMI_OUT}/${AMI_NAME}.manifest.xml
}
#}}}
# {{{ Upload our bundle to our S3 bucket
function upload_ami() {
  output "Uploading AMI to ${AMI_S3_DIR}..."
  RUBYLIB=/usr/lib/ruby/site_ruby/ ec2-upload-bundle --bucket ${AMI_S3_DIR} --manifest $AMI_MANIFEST \
    --access-key ${AWS_ACCESS} --secret-key ${AWS_SECRET} --retry --region ${S3_REGION}  || \
    fatal "Failed to upload image!"
}
#}}}
# {{{ Register our uploading S3 bundle as a valid AMI
function register_ami() {
  if [[ ${AMI_TYPE} == "pv" ]]; then
    output "Looking up latest PV-GRUB kernel image..."
    PVGRUB_AKI=$(aws ec2 describe-images --output text --owners amazon --filters \
      Name=image-type,Values=kernel Name=name,Values='*pv-grub-hd0_*' Name=architecture,Values=x86_64 \
      | sort -r -t$'\t' -k9 | head -1 | cut -f6)
    [[ -z ${PVGRUB_AKI} ]] && fatal "Unable to find PV-GRUB AKI!"
    output "Found AKI ${PVGRUB_AKI}"

    output "Registering AMI ${AMI_NAME} with AWS..."
    aws ec2 register-image --image-location ${AMI_S3_DIR}/${AMI_NAME}.manifest.xml --name ${AMI_NAME} --region ${S3_REGION} \
      --architecture x86_64 --kernel ${PVGRUB_AKI} --virtualization-type paravirtual  || \
      fatal "Failed to register image!"
  else
    aws ec2 register-image --image-location ${AMI_S3_DIR}/${AMI_NAME}.manifest.xml --name ${AMI_NAME} --region ${S3_REGION} \
      --architecture x86_64 --virtualization-type hvm  || \
      fatal "Failed to register image!"
  fi
}
#}}}
## {{{ Utilitiy functions #######################################################
# {{{ Print a message and exit
function quit() {
  output "$1"
  exit 1
}
#}}}
# {{{ Print a fatal message and exit
function fatal() {
  # do the inteligent clean up before bailing
  # do not leave failed attempt
  kpartx -d ${AMI_DEV_PATH}  
  sync; udevadm settle
  dmsetup remove ${AMI_DEV} 
  sync; udevadm settle
  OLD_LOOPS=$(losetup -j ${AMI_IMG} | sed 's#^/dev/loop\([0-9]\+\).*#loop\1#' | paste -d' ' - -)
  [[ -n ${OLD_LOOPS} ]] && losetup -d /dev/${OLD_LOOPS}
  sleep 1; sync; udevadm settle
  quit "FATAL: $1"
}
#}}}
# {{{ Perform our initial setup routines
function do_setup() {

  source ${CFG_FILE}  || get_config_opts
  install_setup_rpms
  setup_aws
  sanity_check

  # Add /usr/local/bin to our path if it doesn't exist there
  [[ ":$PATH:" != *":/usr/local/bin"* ]] && export PATH=$PATH:/usr/local/bin

  output "All build requirements satisfied."
}
#}}}
# {{{ Read config opts and save them to disk
function get_config_opts() {

  source ${CFG_FILE}

  get_input "Path to local build folder (i.e. /mnt/amis)" "BUILD_ROOT"
  get_input "AMI size (in MB)" "AMI_SIZE"
  get_input "AWS User ID #" "AWS_USER"
  get_input "Path to S3 AMI storage (i.e. bucket/dir)" "S3_ROOT"
  get_input "S3 bucket region (i.e. us-west-2)" "S3_REGION"
  get_input "AWS R/W access key" "AWS_ACCESS"
  get_input "AWS R/W secret key" "AWS_SECRET"
  get_input "Path to AWS X509 key" "AWS_PRIVATE_KEY"
  get_input "Path to AWS X509 certifcate" "AWS_CERT"
  get_input "Client name" "CLIENT"
  get_input "Linux version" "LINUX_VERSION"
  get_input "AMI root user" "ROOT_USER"
  get_input "AMI user name" "ROOT_NAME"

  # Create our AWS config file
  mkdir -p ~/.aws
  chmod 700 ~/.aws
cat > $HOME/.aws/config <<-EOT
[default]
output = json
region = ${S3_REGION}
aws_access_key_id = ${AWS_ACCESS}
aws_secret_access_key = ${AWS_SECRET}
EOT

  # Write our config options to a file for subsequent runs
  rm -f ${CFG_FILE}
  touch ${CFG_FILE}
  chmod 600 ${CFG_FILE}
  for f in BUILD_ROOT AMI_SIZE AWS_USER S3_ROOT S3_REGION AWS_ACCESS AWS_SECRET AWS_PRIVATE_KEY AWS_CERT CLIENT LINUX_VERSION ROOT_USER ROOT_NAME; do
    eval echo "$f=\'\$$f\'" >> ${CFG_FILE}
  done

}
#}}}
#{{{ function show_config_opts
function show_config_opts(){
  . ${CFG_FILE}
  for f in BUILD_ROOT AMI_SIZE AWS_USER S3_ROOT S3_REGION AWS_ACCESS AWS_SECRET AWS_PRIVATE_KEY AWS_CERT CLIENT LINUX_VERSION ROOT_USER ROOT_NAME; do
    eval echo $f=\"\$$f\" &> /dev/tty
  done

}
#}}}
# {{{ Read a variable from the user
function get_input()
{
  # Read into a placeholder variable
  ph=
  eval cv=\$${2}
  while [[ -z $ph ]]; do
    printf "%-45.45s : " "$1" &> /dev/tty
    read -e -i "$cv" ph &> /dev/tty
  done

  # Assign placeholder to passed variable name
  eval ${2}=\"$ph\"
}
#}}}
# {{{ Present user with a yes/no question, quit if answer is no
function yesno() {
  read -p "${1}? y/[n] " answer &> /dev/tty
  [[ $answer == "y" ]] || quit "Exiting"
}
#}}}
# {{{ function output()
function output() {
  echo $* > /dev/tty
}
#}}}
# {{{ Sanity check what we can
function sanity_check() {


  # Make sure our ami size is numeric
  [[ "${AMI_SIZE}" =~ ^[0-9]+$ ]] || fatal "AMI size must be an integer!"
  (( "${AMI_SIZE}" >= 1000 )) || fatal "AMI size must be at least 1000 MB (currently ${AMI_SIZE} MB!)"
    (( "${AMI_SIZE}" <= 8192 )) || fatal "AMI size should be no more than 8192 (8GB)"


  # Check for ket/cert existance
  [[ ! -f ${AWS_PRIVATE_KEY} ]] && fatal "EC2 private key '${AWS_PRIVATE_KEY}' doesn't exist!"
  [[ ! -f ${AWS_CERT} ]] && fatal "EC2 certificate '${AWS_CERT}' doesn't exist!"

  # Check S3 access and file existence
  aws s3 ls s3://${S3_ROOT} &> /dev/null
  [[ $? -gt 1 ]] && fatal "S3 bucket doesn't exist or isn't readable!"
  [[ -n $(aws s3 ls s3://${AMI_S3_DIR}) ]] && \
    fatal "AMI S3 path (${AMI_S3_DIR}) already exists;  Refusing to overwrite it"

}
#}}}
# {{{ Install RPMs required by setup
function install_setup_rpms() {

  RPM_LIST=/tmp/rpmlist.txt
  
  # dump rpm list to disk
  rpm -qa > ${RPM_LIST}
  
  # Iterate over required rpms and install missing ones
  TO_INSTALL=
  for rpm in "${REQUIRED_RPMS[@]}"; do
    if ! grep -q "${rpm}-[0-9]" ${RPM_LIST}; then
      TO_INSTALL="$rpm ${TO_INSTALL}"
    fi
  done

  if [[ -n ${TO_INSTALL} ]]; then
    output "Installing build requirements: ${TO_INSTALL}..."
    yum -y install ${TO_INSTALL}
  fi
}
#}}}
# {{{ Set up our various EC2/S3 bits and bobs
function setup_aws() {

  # ec2-ami-tools
  if [[ ! -f /usr/local/bin/ec2-bundle-image ]]; then
    output "Installing EC2 AMI tools..."
    rpm -ivh http://s3.amazonaws.com/ec2-downloads/ec2-ami-tools-1.5.6.noarch.rpm
  fi

  # PIP (needed to install aws cli)
  if [[ ! -f /bin/pip ]]; then
    output "Installing PIP..."
    easy_install pip
  fi
  if [[ ! -f /bin/aws ]]; then
    output "Installing aws-cli"
    pip install awscli
  fi

  # Set the target directory for our upload
  AMI_S3_DIR=${S3_ROOT}/${AMI_NAME}
}
#}}}
#}}}
# {{{ Main code #################################################################
# {{{ Blackhole stdout of all commands unless debug mode requested
#[[ "$3" != "debug" ]] && exec &> /dev/null
#}}}
# {{{ parameter processing
case "$1" in
  reconfig)
    get_config_opts
    ;;
  showconfig)
    show_config_opts
    ;;
  pv)
    AMI_NAME=${2// /_}
    AMI_TYPE=pv
    [[ -z ${AMI_NAME} ]] && quit "Usage: $0 pv <pv_name>"
    do_setup
    build_ami
    ;;
  hvm)
    AMI_NAME=${2// /_}
    AMI_TYPE=hvm
    [[ -z ${AMI_NAME} ]] && quit "Usage: $0 hvm <hvm_name>"
    do_setup
    build_ami
    ;;
  *)
    quit "Usage: $0 <[re|show]config | pv PV_NAME | hvm HVM_NAME> [debug]"
esac
#}}}
# vim: shiftwidth=2 softtabstop=2 number foldlevel=1 backspace=2 foldmethod=marker formatoptions=qlj

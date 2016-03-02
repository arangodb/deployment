# This starts multiple ubuntu instances using VMWare vCloud Air and then
# starts an ArangoDB cluster on them.
#
# Use -r to permanently remove an existing cluster and all machine instances.
#
# Prerequisites: TODO: FORCE CHECK THOSE VALUES, EXIT IF NOT FOUND
# The following environment variables are used:
#
#   Local Network : name of the local network (e.g. -l local_net)
#   Ext. Network  : name of the ext network (e.g. -e ext_net)
#   External IP   : name of the ext network (e.g. -i 10.20.30.40)
#
# Optional prerequisites:
# The following environment variables are used:
#
#   CPU     : cpus to use (e.g. -c 2)
#   MEMORY  : memory to use (e.g. -m 1024)
#   NUMBER  : count of machines to create (e.g. -n 3)
#   OUTPUT  : local output log folder (e.g. -d /my/directory)

if [ platformVCLOUD/VMWareVCloudAir_ArangoDB_Cluster.sh -nt ./vCloud_ArangoDB_Cluster.sh ] || [ Docker/ArangoDBClusterWithDocker.sh -nt ./vCloud_ArangoDB_Cluster.sh ] ; then
  echo 'You almost certainly have forgotten to say "make" to assemble this'
  echo 'script from its parts in subdirectories. Stopping.'
  exit 1
fi

trap "kill 0" SIGINT

#Current Public Catalog images available
# vca catalog

MEMORY="1024"
CPU="2"
NUMBER="2"
OUTPUT="vCloud"
PUBLICIP=""
ORG=""
INSTANCE=""
EXTERNALNET=""
LOCALNET=""
SSH_KEY_PATH=""

function deleteMachine () {
  echo "deleting machine $PREFIX$1"
  vapp=${SERVERS_VAPPS_ARR[`expr $1 - 1`]}

  vca vapp delete --vapp "$vapp"

  if [ $? -eq 0 ]; then
    echo "OK: Deleted instance $vapp"
  else
    echo "ERROR: instance $vapp could not be deleted."
  fi
}

vCloudDestroyMachines() {

    if [ ! -e "$OUTPUT" ] ;  then
      echo "$0: directory '$OUTPUT' not found"
      exit 1
    fi

    . $OUTPUT/clusterinfo.sh

    declare -a SERVERS_VAPPS_ARR=(${SERVERS_VAPPS[@]})

    NUMBER=${#SERVERS_VAPPS_ARR[@]}

    echo "NUMBER OF MACHINES: $NUMBER"
    echo "OUTPUT DIRECTORY: $OUTPUT"
    echo "MACHINE PREFIX: $PREFIX"

    for i in `seq $NUMBER`; do
      deleteMachine $i &
    done

    wait

    # delete network rules TODO: really delete all rules?
    vca nat delete -a

    wait

    read -p "Delete directory: '$OUTPUT' ? [y/n]: " -n 1 -r
      echo
    if [[ $REPLY =~ ^[Yy]$ ]]
      then
        rm -r "$OUTPUT"
        echo "Directory deleted. Finished."
      else
        echo "For a new cluster instance, please remove the directory or specifiy another output directory with -d '/my/directory'"
    fi

    exit 0
}

REMOVE=0

while getopts ":l:e:i:c:m:n:d:s:hr" opt; do
  case $opt in
    h)
       cat <<EOT
This starts multiple ubuntu instances using VMWare vCloud Air and then
starts an ArangoDB cluster on them.

Use -r to permanently remove an existing cluster and all machine instances.

Optional prerequisites:
The following environment variables are used:

  CPU     : cpus to use (e.g. -c 2)
  MEMORY  : memory to use (e.g. -m 1024)
  NUMBER  : count of machines to create (e.g. -n 3)
  OUTPUT  : local output log folder (e.g. -d /my/directory)
EOT
      ;;
    c)
      CPU="$OPTARG"
      ;;
    n)
      NUMBER="$OPTARG"
      ;;
    i)
      PUBLICIP="$OPTARG"
      ;;
    e)
      EXTERNALNET="$OPTARG"
      ;;
    l)
      LOCALNET="$OPTARG"
      ;;
    m)
      MEMORY="$OPTARG"
      ;;
    d)
      OUTPUT="$OPTARG"
      ;;
    s)
      SSH_KEY_PATH="$OPTARG"
      ;;
    r)
      REMOVE=1
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      exit 1
      ;;
    :)
      echo "Option -$OPTARG requires an argument." >&2
      exit 1
      ;;
  esac
done

PREFIX="arangodb-test-$$-"
echo "OUTPUT DIRECTORY: $OUTPUT"

DEFAULT_KEY_PATH="$HOME/.ssh/${PREFIX}vcloud-ssh-key"

#We have to keep all images up to date
# Current Version: UbuntuServer12.04LTS(amd6420150127)
# Catalog: vca catalog

#IMAGE="UbuntuServer12.04LTS(amd6420150127)"
# get the latest ubuntu amd64 image id
IMAGE=`vca catalog | grep -E 'UbuntuServer.*amd64.*' |awk '{print $5}'`

if test -e "$OUTPUT";  then
  if [ "$REMOVE" == "1" ] ; then
    vCloudDestroyMachines
    exit 0
  fi

  echo "$0: refusing to use existing directory '$OUTPUT'"
  exit 1
fi

if [ "$REMOVE" == "1" ] ; then
  echo "$0: did not find an existing directory '$OUTPUT'"
  exit 1
fi

echo "CPUs: $CPU"
echo "MEMORY: $MEMORY"
echo "NUMBER OF MACHINES: $NUMBER"
echo "MACHINE PREFIX: $PREFIX"

mkdir -p "$OUTPUT/temp"
      
#write external ip address to file
echo $PUBLICIP > "$OUTPUT/temp/EXTERNAL"

if [[ -s "$HOME/.ssh/${PREFIX}vcloud-ssh-key" ]] ; then
  echo "vCloud SSH-Key existing."
else
  echo "No vCloud SSH-Key existing. Creating a new SSH-Key."

  ssh-keygen -t rsa -C "${PREFIX}vcloud-ssh-key" -f "$OUTPUT"/${PREFIX}vcloud-ssh-key

  if [ $? -eq 0 ]; then
    echo OK
  else
    echo Failed to create SSH-Key. Exiting.
    exit 1
  fi

  cp "$OUTPUT/${PREFIX}vcloud-ssh-key"* "$HOME/.ssh/"
  chmod 400 "$HOME"/.ssh/${PREFIX}vcloud-ssh-key

fi ;

#check if ssh agent is running
if [ -n "${SSH_AUTH_SOCK}" ]; then
    echo "SSH-Agent is running."

    #check if key already added to ssh agent
    if ssh-add -l | grep $DEFAULT_KEY_PATH > /dev/null ; then
      echo SSH-Key already added to SSH-Agent;
    else
      ssh-add "$DEFAULT_KEY_PATH"
    fi

  else
    echo "No SSH-Agent running. Skipping."
fi

wait

# vcloud machine ready
# status = Powered off , in progress = Unresolved
function getMachine () {
  status=`vca vapp | grep "$PREFIX$1"-vapp |awk '{print $6}'`
  state=0

  while [ "$state" == 0 ]; do
    if [ "$status" == "Unresolved" ]; then
     echo "Machine $PREFIX$1 not ready yet."
     sleep 3
    else
     echo "Machine $PREFIX$1 ready."

     #get vm ip address
     priv=`vca vm --vapp "$PREFIX$1"-vapp |grep "$PREFIX$1"-vapp |awk '{print $9}'`
     echo $priv > "$OUTPUT/temp/INTERNAL$1"

     state=1
    fi
  done

}

function createMachine () {
  echo "creating machine $PREFIX$1"-vm

  INSTANCE=`vca vapp create -a "$PREFIX$1"-vapp -V "$PREFIX$1"-vm -c 'Public Catalog' -t "$IMAGE" \
  -n "$LOCALNET" -m POOL --cpu "$CPU" --ram "$MEMORY"`

  echo "$PREFIX$1"-vapp > "$OUTPUT/temp/VAPP$1"
  echo "$PREFIX$1"-vm > "$OUTPUT/temp/VM$1"
}

function deployKeysOnMachines () {
  echo "Deploying and starting ssh keys. Machine: $PREFIX$1."
  vca vapp customize --vapp "$PREFIX$1"-vapp --vm "$PREFIX$1"-vm --file "$OUTPUT/temp/deploy_ssh.sh"
}

function waitForStartup () {
  #TODO: is docker script waiting? or do we need to wait here?
  echo "Waiting for machines..."
  sleep 10
}

function configureNetworkOnMachines () {

  #TODO: how to generate the number for ssh ports? atm it is just starting at 400 and adding +1 for every machine

  port=`echo $[(400) + $1]`
  echo "$port" > "$OUTPUT/temp/PORT$1"
  echo "Adding SSH network rules to machine: $PREFIX$1 with port $port"
  localip=`cat "$OUTPUT/temp/INTERNAL$i"`
  vca nat add --type DNAT --original-ip "$PUBLICIP" --original-port "$port" --translated-ip "$localip" --translated-port 22 --protocol tcp --network "$EXTERNALNET"
}

declare -a SERVERS_EXTERNAL_VCLOUD
declare -a SERVERS_INTERNAL_VCLOUD
declare -a SERVERS_VMS_VCLOUD
declare -a SERVERS_VAPPS_VCLOUD
declare -a SERVERS_PORTS_VCLOUD

SSH_USER="ubuntu"
SSH_CMD="ssh"

for i in `seq $NUMBER`; do
  createMachine $i &
done

wait

sleep 5

for i in `seq $NUMBER`; do
  getMachine $i &
done

wait

# read public key to string
PUBKEY=`cat "$OUTPUT/${PREFIX}vcloud-ssh-key.pub"`

# create deploy ssh script
echo "#!/bin/bash" > "$OUTPUT/temp/deploy_ssh.sh"
echo "mkdir -p /home/ubuntu/.ssh" >> "$OUTPUT/temp/deploy_ssh.sh"
echo "echo $PUBKEY >> /home/ubuntu/.ssh/authorized_keys" >> "$OUTPUT/temp/deploy_ssh.sh"
echo "chown ubuntu.ubuntu /home/ubuntu/.ssh" >> "$OUTPUT/temp/deploy_ssh.sh"
echo "chown ubuntu.ubuntu /home/ubuntu/.ssh/authorized_keys" >> "$OUTPUT/temp/deploy_ssh.sh"
echo "chmod go-rwx /home/ubuntu/.ssh" >> "$OUTPUT/temp/deploy_ssh.sh"
echo "chmod go-rwx /home/ubuntu/.ssh/authorized_keys" >> "$OUTPUT/temp/deploy_ssh.sh"

#set execution rights on sh file
chmod a+x "$OUTPUT/temp/deploy_ssh.sh"

wait

for i in `seq $NUMBER`; do
  #configureNetworkOnMachines $i &

  echo "Creating network rules for machine $PREFIX$i"
  #vmware does not like creating network rules in parallel
  configureNetworkOnMachines $i
done

wait

for i in `seq $NUMBER`; do
  deployKeysOnMachines $i &
done

wait

for i in `seq $NUMBER`; do
  waitForStartup $i &
done

wait

while :
do

  FINISHED=0

  for i in `seq $NUMBER`; do

    if [ -s "$OUTPUT/temp/INTERNAL$i" ] ; then
      SERVERS_INTERNAL_VCLOUD[`expr $i - 1`]=`cat "$OUTPUT/temp/INTERNAL$i"`
      SERVERS_EXTERNAL_VCLOUD=`cat "$OUTPUT/temp/EXTERNAL"`
      SERVERS_VMS_VCLOUD[`expr $i - 1`]=`cat "$OUTPUT/temp/VM$i"`
      SERVERS_VAPP_VCLOUD[`expr $i - 1`]=`cat "$OUTPUT/temp/VAPP$i"`
      SERVERS_PORTS_VCLOUD[`expr $i - 1`]=`cat "$OUTPUT/temp/PORT$i"`
      FINISHED=1
    else
      FINISHED=0
      break
    fi

  done

  if [ $FINISHED == 1 ] ; then
    echo "All machines are set up"
    break
  fi

  sleep 1

done

rm -rf $OUTPUT/temp

echo Internal IPs: ${SERVERS_INTERNAL_VCLOUD[@]}
echo External IP: $PUBLICIP
echo VMs         : ${SERVERS_VMS_VCLOUD[@]}
echo VAPPs       : ${SERVERS_VAPP_VCLOUD[@]}
echo PORTS       : ${SERVERS_PORTS_VCLOUD[@]}

echo Remove host key entry in ~/.ssh/known_hosts...
ssh-keygen -f ~/.ssh/known_hosts -R $PUBLICIP

SERVERS_INTERNAL="${SERVERS_INTERNAL_VCLOUD[@]}"
SERVERS_EXTERNAL="$PUBLICIP"
SERVERS_VMS="${SERVERS_VMS_VCLOUD[@]}"
SERVERS_VAPPS="${SERVERS_VAPP_VCLOUD[@]}"
SERVERS_PORTS="${SERVERS_PORTS_VCLOUD[@]}"

# Write data to file:
echo > $OUTPUT/clusterinfo.sh "SERVERS_INTERNAL=\"$SERVERS_INTERNAL\""
echo >>$OUTPUT/clusterinfo.sh "SERVERS_EXTERNAL=\"$SERVERS_EXTERNAL\""
echo >>$OUTPUT/clusterinfo.sh "SERVERS_PORTS=\"$SERVERS_PORTS\""
echo >>$OUTPUT/clusterinfo.sh "SERVERS_VMS=\"$SERVERS_VMS\""
echo >>$OUTPUT/clusterinfo.sh "SERVERS_VAPPS=\"$SERVERS_VAPPS\""
echo >>$OUTPUT/clusterinfo.sh "SSH_USER=\"$SSH_USER\""
echo >>$OUTPUT/clusterinfo.sh "SSH_CMD=\"$SSH_CMD\""
echo >>$OUTPUT/clusterinfo.sh "SSH_SUFFIX=\"$SSH_SUFFIX\""
echo >>$OUTPUT/clusterinfo.sh "PREFIX=\"$PREFIX\""

# Export needed variables
export SERVERS_INTERNAL
export SERVERS_EXTERNAL
export SERVERS_VMS
export SERVERS_VAPPS
export SSH_USER="ubuntu"
export SSH_CMD="ssh"
export SSH_SUFFIX="-i $DEFAULT_KEY_PATH -l $SSH_USER -p PORTS" #TODO get correct port for machine, because different for every machine

sleep 5

#TODO wait for SSH?
#login then via: ssh -i 'keyfile' ubuntu@'PUBLICIP' -p 'machine_port'
#Example: ssh -i vCloud/arangodb-test-14344-vcloud-ssh-key ubuntu@92.246.245.8 -p 401

#TODO ENABLE DOCKER MAGIC
#startArangoDBClusterWithDocker

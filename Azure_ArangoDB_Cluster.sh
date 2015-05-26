#!/bin/bash
#
# This script is provided as-is, no warrenty is provided or implied.
# The author is NOT responsible for any damages or data loss that may occur through the use of this script.
#
# This function starts a ArangoDB cluster by just using docker
#
# Prerequisites:
# The following environment variables are used:
#   SERVERS_EXTERNAL : list of IP addresses or hostnames, separated by 
#                      whitespace, this must be the network interfaces
#                      that are reachable from the outside
#   SERVERS_INTERNAL : list of IP addresses or hostnames, sep by whitespace
#                      must be same length as SERVERS_EXTERNAL
#                      this must be the corresponding network interfaces 
#                      that are reachable from the outside, can be the same
#   SSH_CMD          : command to use for ssh connection [default "ssh"]
#   SSH_ARGS         : arguments to SSH_CMD, will be expanded in
#                      quotes [default: "-oStrictHostKeyChecking no"]
#   SSH_USER         : user name on remote machine [default "core"]
#   SSH_SUFFIX       : suffix for ssh command [default ""].
#   NRDBSERVERS      : is always set to the length of SERVERS_EXTERNAL
#   NRCOORDINATORS   : default: $NRDBSERVERS, can be less, at least 1
#   PORT_DBSERVER    : default: 8629
#   PORT_COORDINATOR : default: 8529
#   DBSERVER_DATA    : default: "/home/$SSH_USER/dbserver"
#   COORDINATOR_DATA : default: "/home/$SSH_USER/coordinator"
#   DBSERVER_LOGS    : default: "/home/$SSH_USER/dbserver_logs"
#   COORDINATOR_LOGS : default: "/home/$SSH_USER/coordinator_logs"
#   AGENCY_DIR       : default: /home/$SSH_USER/agency"
#   DBSERVER_ARGS    : default: ""
#   COORDINATOR_ARGS : default: ""

# There will be one DBserver on each machine and at most one coordinator.
# There will be one agency running on the first machine.
# Each DBserver uses /

# All servers must be accessible without typing passwords (tell your agent!)
# via ssh using the following command for server number i:
#   ${SSH_CMD} "${SSH_ARGS}" ${SSH_USER}@${SERVERS_EXTERNAL_ARR[i]} ${SSH_SUFFIX} docker run ...

startArangoDBClusterWithDocker() {

    DOCKER_IMAGE_NAME=neunhoef/arangodb_cluster:latest

    # Two docker images are needed: 
    #  microbox/etcd for the agency and
    #  ${DOCKER_IMAGE_NAME} for
    #   - arangod
    #   - arangosh
    #   - some helper scripts

    # To stop the cluster simply stop and remove the containers with the
    # names
    #   - agency
    #   - discovery
    #   - coordinator
    #   - dbserver
    # on all machines.

    set +u

    if [ -z "$SERVERS_EXTERNAL" ] ; then
      echo Need SERVERS_EXTERNAL environment variable
      exit 1
    fi
    declare -a SERVERS_EXTERNAL_ARR=($SERVERS_EXTERNAL)
    echo SERVERS_EXTERNAL: ${SERVERS_EXTERNAL_ARR[*]}

    if [ -z "$SERVERS_INTERNAL" ] ; then
      declare -a SERVERS_INTERNAL_ARR=(${SERVERS_EXTERNAL_ARR[*]})
    else
      declare -a SERVERS_INTERNAL_ARR=($SERVERS_INTERNAL)
    fi
    echo SERVERS_INTERNAL: ${SERVERS_INTERNAL_ARR[*]}

    NRDBSERVERS=${#SERVERS_EXTERNAL_ARR[*]}
    LASTDBSERVER=`expr $NRDBSERVERS - 1`

    echo Number of DBServers: $NRDBSERVERS
    if [ -z "$NRCOORDINATORS" ] ; then
        NRCOORDINATORS=$NRDBSERVERS
    fi
    LASTCOORDINATOR=`expr $NRCOORDINATORS - 1`
    echo Number of Coordinators: $NRCOORDINATORS

    if [ -z "$SSH_CMD" ] ; then
      SSH_CMD=ssh
    fi
    echo SSH_CMD=$SSH_CMD

    if [ -z "$SSH_ARGS" ] ; then
      SSH_ARGS="-oStrictHostKeyChecking no"
    fi
    echo SSH_ARGS=$SSH_ARGS

    if [ -z "$SSH_USER" ] ; then
      SSH_USER=core
    fi
    echo SSH_USER=$SSH_USER

    if [ -z "$PORT_DBSERVER" ] ; then
      PORT_DBSERVER=8629
    fi
    echo PORT_DBSERVER=$PORT_DBSERVER

    if [ -z "$PORT_COORDINATOR" ] ; then
      PORT_COORDINATOR=8529
    fi
    echo PORT_COORDINATOR=$PORT_COORDINATOR

    if [ -z "$DBSERVER_DATA" ] ; then
      DBSERVER_DATA=/home/$SSH_USER/dbserver
    fi
    echo DBSERVER_DATA=$DBSERVER_DATA

    if [ -z "$DBSERVER_LOGS" ] ; then
      DBSERVER_LOGS=/home/$SSH_USER/dbserver_logs
    fi
    echo DBSERVER_LOGS=$DBSERVER_LOGS

    if [ -z "$AGENCY_DIR" ] ; then
      AGENCY_DIR=/home/$SSH_USER/agency
    fi
    echo AGENCY_DIR=$AGENCY_DIR

    if [ -z "$COORDINATOR_DATA" ] ; then
      COORDINATOR_DATA=/home/$SSH_USER/coordinator_data
    fi
    echo COORDINATOR_DATA=$COORDINATOR_DATA

    if [ -z "$COORDINATOR_LOGS" ] ; then
      COORDINATOR_LOGS=/home/$SSH_USER/coordinator_logs
    fi
    echo COORDINATOR_LOGS=$COORDINATOR_LOGS

    echo Creating directories on servers. This may take some time. Please wait.
    $SSH_CMD "${SSH_ARGS}" ${SSH_USER}@${SERVERS_EXTERNAL_ARR[0]} $SSH_SUFFIX mkdir $AGENCY_DIR >/dev/null 2>&1 &
    for i in `seq 0 $LASTDBSERVER` ; do
      $SSH_CMD "${SSH_ARGS}" ${SSH_USER}@${SERVERS_EXTERNAL_ARR[$i]} $SSH_SUFFIX mkdir $DBSERVER_DATA $DBSERVER_LOGS >/dev/null 2>&1 &
    done
    for i in `seq 0 $LASTCOORDINATOR` ; do
      $SSH_CMD "${SSH_ARGS}" ${SSH_USER}@${SERVERS_EXTERNAL_ARR[$i]} $SSH_SUFFIX mkdir $COORDINATOR_DATA $COORDINATOR_LOGS >/dev/null 2>&1 &
    done

    wait

    echo Starting agency...
    $SSH_CMD "${SSH_ARGS}" ${SSH_USER}@${SERVERS_EXTERNAL_ARR[0]} $SSH_SUFFIX "docker run --detach=true -p 4001:4001 -p 7001:7001 --name=agency -e "ETCD_NONO_WAL_SYNC=1" -v $AGENCY_DIR:/data ${DOCKER_IMAGE_NAME} /usr/lib/arangodb/etcd-arango --data-dir /data --listen-client-urls "http://0.0.0.0:4001" --listen-peer-urls "http://0.0.0.0:7001" >/home/$SSH_USER/agency.log"

    sleep 1
    echo Initializing agency...
    $SSH_CMD "${SSH_ARGS}" ${SSH_USER}@${SERVERS_EXTERNAL_ARR[0]} $SSH_SUFFIX "docker run --link=agency:agency --rm ${DOCKER_IMAGE_NAME} arangosh --javascript.execute /scripts/init_agency.js > /home/$SSH_USER/init_agency.log"
    echo Starting discovery...
    $SSH_CMD "${SSH_ARGS}" ${SSH_USER}@${SERVERS_EXTERNAL_ARR[0]} $SSH_SUFFIX "docker run --detach=true --link=agency:agency --name discovery ${DOCKER_IMAGE_NAME} arangosh --javascript.execute scripts/discover.js > /home/$SSH_USER/discovery.log"

    start_dbserver () {
        i=$1
        echo Starting DBserver on ${SERVERS_EXTERNAL_ARR[$i]}:$PORT_DBSERVER

        $SSH_CMD "${SSH_ARGS}" ${SSH_USER}@${SERVERS_EXTERNAL_ARR[$i]} $SSH_SUFFIX \
        docker run --detach=true -v $DBSERVER_DATA:/data \
         -v $DBSERVER_LOGS:/logs --net=host \
         --name=dbserver$PORT_DBSERVER ${DOCKER_IMAGE_NAME} \
          arangod --database.directory /data \
          --cluster.agency-endpoint tcp://${SERVERS_INTERNAL_ARR[0]}:4001 \
          --cluster.my-address tcp://${SERVERS_INTERNAL_ARR[$i]}:$PORT_DBSERVER \
          --server.endpoint tcp://0.0.0.0:$PORT_DBSERVER \
          --cluster.my-local-info dbserver:${SERVERS_INTERNAL_ARR[$i]}:$PORT_DBSERVER \
          --log.file /logs/$PORT_DBSERVER.log \
          $DBSERVER_ARGS \
          >/dev/null
    }

    start_coordinator () {
        i=$1
        echo Starting Coordinator on ${SERVERS_EXTERNAL_ARR[$i]}:$PORT_COORDINATOR

        $SSH_CMD "${SSH_ARGS}" ${SSH_USER}@${SERVERS_EXTERNAL_ARR[$i]} $SSH_SUFFIX \
         docker run --detach=true -v $COORDINATOR_DATA:/data \
            -v $COORDINATOR_LOGS:/logs --net=host \
            --name=coordinator$PORT_COORDINATOR \
            ${DOCKER_IMAGE_NAME} \
          arangod --database.directory /data \
           --cluster.agency-endpoint tcp://${SERVERS_INTERNAL_ARR[0]}:4001 \
           --cluster.my-address tcp://${SERVERS_INTERNAL_ARR[$i]}:$PORT_COORDINATOR \
           --server.endpoint tcp://0.0.0.0:$PORT_COORDINATOR \
           --cluster.my-local-info \
                     coordinator:${SERVERS_INTERNAL_ARR[$i]}:$PORT_COORDINATOR \
           --log.file /logs/$PORT_COORDINATOR.log \
           $COORDINATOR_ARGS \
           >/dev/null
    }

    for i in `seq 0 $LASTDBSERVER` ; do
        start_dbserver $i &
    done

    wait

    for i in `seq 0 $LASTCOORDINATOR` ; do
        start_coordinator $i &
    done

    wait 

    echo Waiting for cluster to come up...

    testServer() {
        ENDPOINT=$1
        while true ; do
            sleep 1
            curl -s -X GET "http://$ENDPOINT/_api/version" > /dev/null 2>&1
            if [ "$?" != "0" ] ; then
                echo Server at $ENDPOINT does not answer yet.
            else
                echo Server at $ENDPOINT is ready for business.
                break
            fi
        done
    }

    #for i in `seq 0 $LASTDBSERVER` ; do
    #    testServer ${SERVERS_EXTERNAL_ARR[$i]}:$PORT_DBSERVER
    #done

    for i in `seq 0 $LASTCOORDINATOR` ; do
        testServer ${SERVERS_EXTERNAL_ARR[$i]}:$PORT_COORDINATOR
    done

    echo Bootstrapping DBServers...
    curl -s -X POST "http://${SERVERS_EXTERNAL_ARR[0]}:$PORT_COORDINATOR/_admin/cluster/bootstrapDbServers" \
         -d '{"isRelaunch":false}' >/dev/null 2>&1

    echo Running DB upgrade on cluster...
    curl -s -X POST "http://${SERVERS_EXTERNAL_ARR[0]}:$PORT_COORDINATOR/_admin/cluster/upgradeClusterDatabase" \
         -d '{"isRelaunch":false}' >/dev/null 2>&1

    echo Bootstrapping Coordinators...
    for i in `seq 0 $LASTCOORDINATOR` ; do
        echo Doing ${SERVERS_EXTERNAL_ARR[$i]}:$PORT_COORDINATOR
        curl -s -X POST "http://${SERVERS_EXTERNAL_ARR[$i]}:$PORT_COORDINATOR/_admin/cluster/bootstrapCoordinator" \
             -d '{"isRelaunch":false}' >/dev/null 2>&1 &
    done

    wait

    echo ""
    echo "================================================================================================"
    echo "Done, your cluster is ready."
    echo "================================================================================================"
    echo ""
    echo "Frontends available at:"
    for i in `seq 0 $LASTCOORDINATOR` ; do
        echo "   http://${SERVERS_EXTERNAL_ARR[$i]}:$PORT_COORDINATOR"
    done
    echo ""
    echo "Access with docker, using arangosh:"
    for i in `seq 0 $LASTCOORDINATOR` ; do
        echo "   docker run -it --rm --net=host ${DOCKER_IMAGE_NAME} arangosh --server.endpoint tcp://${SERVERS_EXTERNAL_ARR[$i]}:$PORT_COORDINATOR"
    done
    echo ""
}

# This starts multiple coreos instances using Microsoft Azure and then starts
# an ArangoDB cluster on them.
#
# Use -r to permanently remove an existing cluster and all machine instances.
#
# Optional prerequisites:
#   ZONE    : site of the server (e.g. -z "US West")
#   SIZE    : size/machine-type of the instance (e.g. -m Medium)
#   NUMBER  : count of machines to create (e.g. -n 3)
#   OUTPUT  : local output log folder (e.g. -d /my/directory)
#   SSH     : path to your already on Azure deployed ssh key (e.g. -s /my/directory/mykey)

trap "kill 0" SIGINT

ZONE="West US"
MACHINE_TYPE="Medium"
NUMBER="3"
OUTPUT="azure"
IMAGE="2b171e93f07c4903bcad35bda10acf22__CoreOS-Stable-607.0.0"
SSH_KEY_PATH=""
DEFAULT_KEY_PATH="$OUTPUT/arangodb_azure_key"

function deleteMachine () {
  echo "deleting machine $PREFIX$1"
  id=${SERVERS_IDS_ARR[`expr $1 - 1`]}

  ok=0
  while [ "$ok" == "0" ]; do
    azure vm delete "$id" -q
    if [ $? -eq 0 ] ; then
      ok=1
    else
      echo Failed to delete service $PREFIX$1. Retrying.
    fi
  done
}

AzureDestroyMachines() {
  if [ ! -e "$OUTPUT" ] ;  then
    echo "$0: directory '$OUTPUT' not found"
    exit 1
  fi

  . $OUTPUT/clusterinfo.sh

  declare -a SERVERS_IDS_ARR=(${SERVERS_IDS[@]})

  NUMBER=${#SERVERS_IDS_ARR[@]}

  echo "NUMBER OF MACHINES: $NUMBER"
  echo "OUTPUT DIRECTORY: $OUTPUT"
  echo "MACHINE PREFIX: $PREFIX"

  echo "Destroying machines"
  for i in `seq $NUMBER`; do
    sleep 1
    deleteMachine $i &
  done

  wait

  echo "Destroying virtual network"
  azure network vnet delete "${PREFIX}vnet"

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

DEPLOY_KEY=0
REMOVE=0

while getopts ":z:m:n:d:s:hr" opt; do
  case $opt in
    h)
    cat <<EOT
This starts multiple coreos instances using Microsoft Azure and then starts
an ArangoDB cluster on them.

Use -r to permanently remove an existing cluster and all machine instances.

Optional prerequisites:
  ZONE  : size of the server (e.g. -z "US West")
  SIZE    : size/machine-type of the instance (e.g. -m Medium)
  NUMBER  : count of machines to create (e.g. -n 3)
  OUTPUT  : local output log folder (e.g. -d /my/directory)
  SSH     : path to your already on azure deployed ssh key (e.g. -s /my/directory/mykey)

EOT
    exit 0
    ;;
    z)
      ZONE="$OPTARG"
      ;;
    m)
      MACHINE_TYPE="$OPTARG"
      ;;
    n)
      NUMBER="$OPTARG"
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

if test -e "$OUTPUT";  then
  if [ "$REMOVE" == "1" ] ; then
    AzureDestroyMachines
    exit 0
  fi

  echo "$0: refusing to use existing directory '$OUTPUT'"
  exit 1
fi

if [ "$REMOVE" == "1" ] ; then
  echo "$0: did not find an existing directory '$OUTPUT'"
  exit 1
fi

echo "ZONE: $ZONE"
echo "MACHINE_TYPE: $MACHINE_TYPE"
echo "NUMBER OF MACHINES: $NUMBER"
echo "OUTPUT DIRECTORY: $OUTPUT"
echo "PROJECT: $PROJECT"
echo "MACHINE PREFIX: $PREFIX"

mkdir -p "$OUTPUT/temp"

if test -z "$SSH_KEY_PATH";
then

  if [[ -s "$HOME/.ssh/arangodb_azure_key" ]] ; then
    echo "ArangoDB Azure SSH-Key found."
    DEFAULT_KEY_PATH="$HOME/.ssh/arangodb_azure_key"
  else
    echo "No SSH-Key-Path given. Creating a new SSH-Key."
    ssh-keygen -t dsa -f "$DEFAULT_KEY_PATH" -C "arangodb@arangodb.com"

#    openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout "$DEFAULT_KEY_PATH" -out "$DEFAULT_KEY_PATH.pem"
    openssl req -x509 -key "$DEFAULT_KEY_PATH" -nodes -days 365 -newkey rsa:2048 -out "${DEFAULT_KEY_PATH}.pem"

    if [ $? -eq 0 ]; then
      echo Created SSH-Key.
    else
      echo Failed to create SSH-Key. Exiting.
      exit 1
    fi
    cp $DEFAULT_KEY_PATH* $HOME/.ssh/
    DEFAULT_KEY_PATH="$HOME/.ssh/arangodb_azure_key"
    chmod 600 $DEFAULT_KEY_PATH
  fi ;

else
  #Check if SSH-Files are available and valid
  echo "Trying to use $SSH_KEY_PATH."
  DEFAULT_KEY_PATH="$SSH_KEY_PATH"
  ssh-keygen -l -f "$DEFAULT_KEY_PATH"

  if [ $? -eq 0 ]; then
    echo SSH-Key is valid.
  else
    echo Failed to validate SSH-Key. Exiting.
    exit 1
  fi
fi


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

function getMachine () {

  state=""

  while [ "$state" != "ReadyRole" ]; do

    instance=`azure vm show "$PREFIX$1"`
    state=`echo "$instance" | grep InstanceStatus | awk '{print $3}' | cut -c 2- | rev | cut -c 2- | rev`
  done

  internalip=`echo "$instance" | grep IPAddress | head -n 1 |awk '{print $3}' | cut -c 2- | rev | cut -c 2- | rev`
  externalip=`echo "$instance" | grep virtualIPAddress | awk '{print $6}' | cut -c 2- | rev | cut -c 2- | rev`

  if [ -n "$internalip" ]; then
    echo $internalip > "$OUTPUT/temp/INTERNAL$1"
  fi
  if [ -n "$externalip" ]; then
    echo $externalip > "$OUTPUT/temp/EXTERNAL$1"
  fi
}

function createMachine () {
  ok=0
  while [ "$ok" == "0" ] ; do
    echo "creating machine $PREFIX$1"
    azure vm create --vm-size "$MACHINE_TYPE" --userName "core" --ssh 22 --ssh-cert "${DEFAULT_KEY_PATH}.pem" \
      --virtual-network-name "${PREFIX}vnet" --no-ssh-password "$PREFIX$1" "$IMAGE" >>/tmp/azure$1.log
    if [ $? -eq 0 ]; then
      ok=1
    else
      echo Failed to create machine $PREFIX$1. Retrying.
    fi
  done
}

function createEndpoint () {
  ok=0
  while [ "$ok" == "0" ] ; do
    echo "opening port 8529 on $PREFIX$1"
    azure vm endpoint create "$PREFIX$1" 8529 8529 >>/tmp/azure$1.log
    if [ $? -eq 0 ]; then
      ok=1
    else
      echo Failed to open port 8529 $PREFIX$1. Retrying.
    fi
  done
}

declare -a SERVERS_EXTERNAL_AZURE
declare -a SERVERS_INTERNAL_AZURE
declare -a SERVERS_IDS_AZURE

echo "Creating virtual network"
azure network vnet create "${PREFIX}vnet" --location "$ZONE"

for i in `seq $NUMBER`; do
  echo "Creating services for virtual machines."
  # not parallel because azure cannot spawn multiple services at the same time
  azure service create "$PREFIX$i" --location "$ZONE"
done

for i in `seq $NUMBER`; do
  sleep 2
  createMachine $i &
done

wait

# get machines information
for i in `seq $NUMBER`; do
  sleep 2
  getMachine $i &
done

#wait

while :
do

  FINISHED=0

  for i in `seq $NUMBER`; do

    if [ -s "$OUTPUT/temp/INTERNAL$i" ] ; then
      SERVERS_INTERNAL_AZURE[`expr $i - 1`]=`cat "$OUTPUT/temp/INTERNAL$i"`
      SERVERS_EXTERNAL_AZURE[`expr $i - 1`]=`cat "$OUTPUT/temp/EXTERNAL$i"`
      SERVERS_IDS_AZURE[`expr $i - 1`]=$PREFIX$i
      FINISHED=1
    else
      echo "Machines not ready yet."
      sleep 5
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

wait

for i in `seq $NUMBER`; do
  sleep 2
  createEndpoint $i &
#  azure vm endpoint create "$PREFIX$i" 8529 8529
done

wait

rm -rf $OUTPUT/temp

echo Internal IPs: ${SERVERS_INTERNAL_AZURE[@]}
echo External IPs: ${SERVERS_EXTERNAL_AZURE[@]}
echo IDs         : ${SERVERS_IDS_AZURE[@]}

SERVERS_INTERNAL="${SERVERS_INTERNAL_AZURE[@]}"
SERVERS_EXTERNAL="${SERVERS_EXTERNAL_AZURE[@]}"
SERVERS_IDS="${SERVERS_IDS_AZURE[@]}"

# Export needed variables
export SERVERS_INTERNAL
export SERVERS_EXTERNAL
export SERVERS_IDS
export SSH_USER="core"
export SSH_CMD="ssh"
export SSH_SUFFIX="-i $DEFAULT_KEY_PATH"
export ZONE

# Write data to file:
echo > $OUTPUT/clusterinfo.sh "SERVERS_INTERNAL=\"$SERVERS_INTERNAL\""
echo >>$OUTPUT/clusterinfo.sh "SERVERS_EXTERNAL=\"$SERVERS_EXTERNAL\""
echo >>$OUTPUT/clusterinfo.sh "SERVERS_IDS=\"$SERVERS_IDS\""
echo >>$OUTPUT/clusterinfo.sh "SSH_USER=\"$SSH_USER\""
echo >>$OUTPUT/clusterinfo.sh "SSH_CMD=\"$SSH_CMD\""
echo >>$OUTPUT/clusterinfo.sh "SSH_SUFFIX=\"$SSH_SUFFIX\""
echo >>$OUTPUT/clusterinfo.sh "PREFIX=\"$PREFIX\""
echo >>$OUTPUT/clusterinfo.sh "ZONE=\"$ZONE\""

startArangoDBClusterWithDocker

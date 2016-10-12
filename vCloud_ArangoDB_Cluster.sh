#!/bin/bash
#
# This script is provided as-is, no warrenty is provided or implied.
# The author is NOT responsible for any damages or data loss that may occur through the use of this script.
#
# This function starts an ArangoDB cluster by just using docker
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
#   NRDBSERVERS      : is always set to the length of SERVERS_EXTERNAL if
#                      not specified
#   NRCOORDINATORS   : default: $NRDBSERVERS, can be less, at least 1
#   PORT_DBSERVER    : default: 8629
#   PORT_COORDINATOR : default: 8529
#   PORT_REPLICA     : default: 8630
#   DBSERVER_DATA    : default: "/home/$SSH_USER/dbserver"
#   COORDINATOR_DATA : default: "/home/$SSH_USER/coordinator"
#   DBSERVER_LOGS    : default: "/home/$SSH_USER/dbserver_logs"
#   COORDINATOR_LOGS : default: "/home/$SSH_USER/coordinator_logs"
#   REPLICA_DATA     : default: "/home/$SSH_USER/replica"
#   REPLICA_LOGS     : default: "/home/$SSH_USER/replica_logs"
#   AGENCY_DIR       : default: /home/$SSH_USER/agency"
#   DBSERVER_ARGS    : default: ""
#   COORDINATOR_ARGS : default: ""
#   REPLICA_ARGS     : default: ""
#   REPLICAS         : default : "", if non-empty, one asynchronous replica
#                      is started for each DBserver, it resides on the "next"
#                      machine

# There will be one DBserver on each machine and at most one coordinator.
# There will be one agency running on the first machine.
# Each DBserver uses /

# All servers must be accessible without typing passwords (tell your agent!)
# via ssh using the following command for server number i:
#   ${SSH_CMD} "${SSH_ARGS}" ${SSH_USER}@${SERVERS_EXTERNAL_ARR[i]} ${SSH_SUFFIX} docker run ...

startArangoDBClusterWithDocker() {

    DOCKER_IMAGE_NAME=neunhoef/arangodb_cluster:2.6.dev-2.5

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

    if [ -z "$NRDBSERVERS" ] ; then
        NRDBSERVERS=${#SERVERS_EXTERNAL_ARR[*]}
    fi
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

    if [ -z "$PORT_REPLICA" ] ; then
      PORT_REPLICA=8630
    fi
    echo PORT_REPLICA=$PORT_REPLICA

    i=$NRDBSERVERS
    if [ $i -ge ${#SERVERS_INTERNAL_ARR[*]} ] ; then
        i=0
    fi
    COORDINATOR_MACHINES="$i"
    FIRST_COORDINATOR=$i
    for j in `seq 1 $LASTCOORDINATOR` ; do
        i=`expr $i + 1`
        if [ $i -ge ${#SERVERS_INTERNAL_ARR[*]} ] ; then
            i=0
        fi
        COORDINATOR_MACHINES="$COORDINATOR_MACHINES $i"
    done
    echo COORDINATOR_MACHINES:$COORDINATOR_MACHINES
    echo FIRST_COORDINATOR: $FIRST_COORDINATOR

    if [ -z "$DBSERVER_DATA" ] ; then
      DBSERVER_DATA=/home/$SSH_USER/dbserver
    fi
    echo DBSERVER_DATA=$DBSERVER_DATA

    if [ -z "$DBSERVER_LOGS" ] ; then
      DBSERVER_LOGS=/home/$SSH_USER/dbserver_logs
    fi
    echo DBSERVER_LOGS=$DBSERVER_LOGS

    if [ -z "$REPLICA_DATA" ] ; then
      REPLICA_DATA=/home/$SSH_USER/replica
    fi
    echo REPLICA_DATA=$REPLICA_DATA

    if [ -z "$REPLICA_LOGS" ] ; then
      REPLICA_LOGS=/home/$SSH_USER/replica_logs
    fi
    echo REPLICA_LOGS=$REPLICA_LOGS

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
    for i in $COORDINATOR_MACHINES ; do
        $SSH_CMD "${SSH_ARGS}" ${SSH_USER}@${SERVERS_EXTERNAL_ARR[$i]} $SSH_SUFFIX mkdir $COORDINATOR_DATA $COORDINATOR_LOGS >/dev/null 2>&1 &
    done
    if [ ! -z "$REPLICAS" ] ; then
        for i in `seq 0 $LASTDBSERVER` ; do
            j=`expr $i + 1`
            if [ $j -gt $LASTDBSERVER ] ; then
                j=0
            fi
            $SSH_CMD "${SSH_ARGS}" ${SSH_USER}@${SERVERS_EXTERNAL_ARR[$j]} $SSH_SUFFIX mkdir $REPLICA_DATA $REPLICA_LOGS >/dev/null 2>&1 &
        done
    fi

    wait

    echo Starting agency...
    until $SSH_CMD "${SSH_ARGS}" ${SSH_USER}@${SERVERS_EXTERNAL_ARR[0]} $SSH_SUFFIX "docker run --detach=true -p 4001:4001 -p 7001:7001 --name=agency -e "ETCD_NONO_WAL_SYNC=1" -v $AGENCY_DIR:/data ${DOCKER_IMAGE_NAME} /usr/lib/arangodb/etcd-arango --data-dir /data --listen-client-urls "http://0.0.0.0:4001" --listen-peer-urls "http://0.0.0.0:7001" >/home/$SSH_USER/agency.log"
    do
        echo "Error in remote docker run, retrying..."
    done

    sleep 1
    echo Initializing agency...
    until $SSH_CMD "${SSH_ARGS}" ${SSH_USER}@${SERVERS_EXTERNAL_ARR[0]} $SSH_SUFFIX "docker run --link=agency:agency --rm ${DOCKER_IMAGE_NAME} arangosh --javascript.execute /scripts/init_agency.js > /home/$SSH_USER/init_agency.log"
    do
        echo "Error in remote docker run, retrying..."
    done
    echo Starting discovery...
    until $SSH_CMD "${SSH_ARGS}" ${SSH_USER}@${SERVERS_EXTERNAL_ARR[0]} $SSH_SUFFIX "docker run --detach=true --link=agency:agency --name discovery ${DOCKER_IMAGE_NAME} arangosh --javascript.execute scripts/discover.js > /home/$SSH_USER/discovery.log"
    do
        echo "Error in remote docker run, retrying..."
    done

    start_dbserver () {
        i=$1
        echo Starting DBserver on ${SERVERS_EXTERNAL_ARR[$i]}:$PORT_DBSERVER

        until $SSH_CMD "${SSH_ARGS}" ${SSH_USER}@${SERVERS_EXTERNAL_ARR[$i]} $SSH_SUFFIX \
            docker run --detach=true -v $DBSERVER_DATA:/data \
             -v $DBSERVER_LOGS:/logs --net=host \
             --name=dbserver$PORT_DBSERVER ${DOCKER_IMAGE_NAME} \
              arangod --database.directory /data \
              --frontend-version-check false \
              --cluster.agency-endpoint tcp://${SERVERS_INTERNAL_ARR[0]}:4001 \
              --cluster.my-address tcp://${SERVERS_INTERNAL_ARR[$i]}:$PORT_DBSERVER \
              --server.endpoint tcp://0.0.0.0:$PORT_DBSERVER \
              --cluster.my-local-info dbserver:${SERVERS_INTERNAL_ARR[$i]}:$PORT_DBSERVER \
              --log.file /logs/$PORT_DBSERVER.log \
              --dispatcher.report-interval 15 \
              --server.foxx-queues false \
              --server.disable-statistics true \
              --scheduler.threads 3 \
              --server.threads 5 \
              $DBSERVER_ARGS \
              >/dev/null
        do
            echo "Error in remote docker run, retrying..."
        done
    }

    start_coordinator () {
        i=$1
        echo Starting Coordinator on ${SERVERS_EXTERNAL_ARR[$i]}:$PORT_COORDINATOR

        until $SSH_CMD "${SSH_ARGS}" ${SSH_USER}@${SERVERS_EXTERNAL_ARR[$i]} $SSH_SUFFIX \
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
               --dispatcher.report-interval 15 \
               --server.foxx-queues false \
               --server.disable-statistics true \
               --scheduler.threads 4 \
               --server.threads 40 \
               $COORDINATOR_ARGS \
               >/dev/null
        do
            echo "Error in remote docker run, retrying..."
        done
    }

    for i in `seq 0 $LASTDBSERVER` ; do
        start_dbserver $i &
    done

    wait

    for i in $COORDINATOR_MACHINES ; do
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

    for i in $COORDINATOR_MACHINES ; do
        testServer ${SERVERS_EXTERNAL_ARR[$i]}:$PORT_COORDINATOR
    done

    echo Bootstrapping DBServers...
    curl -s -X POST "http://${SERVERS_EXTERNAL_ARR[$FIRST_COORDINATOR]}:$PORT_COORDINATOR/_admin/cluster/bootstrapDbServers" \
         -d '{"isRelaunch":false}' >/dev/null 2>&1

    echo Running DB upgrade on cluster...
    curl -s -X POST "http://${SERVERS_EXTERNAL_ARR[$FIRST_COORDINATOR]}:$PORT_COORDINATOR/_admin/cluster/upgradeClusterDatabase" \
         -d '{"isRelaunch":false}' >/dev/null 2>&1

    echo Bootstrapping Coordinators...
    for i in $COORDINATOR_MACHINES ; do
        echo Doing ${SERVERS_EXTERNAL_ARR[$i]}:$PORT_COORDINATOR
        curl -s -X POST "http://${SERVERS_EXTERNAL_ARR[$i]}:$PORT_COORDINATOR/_admin/cluster/bootstrapCoordinator" \
             -d '{"isRelaunch":false}' >/dev/null 2>&1 &
    done

    wait

    if [ ! -z "$REPLICAS" ] ; then
        start_replica () {
            i=$1
            j=`expr $i + 1`
            if [ $j -gt $LASTDBSERVER ] ; then
                j=0
            fi
            echo Starting asynchronous replica for
            echo "  ${SERVERS_EXTERNAL_ARR[$i]}:$PORT_DBSERVER on ${SERVERS_EXTERNAL_ARR[$j]}:$PORT_REPLICA"

            until $SSH_CMD "${SSH_ARGS}" ${SSH_USER}@${SERVERS_EXTERNAL_ARR[$j]} $SSH_SUFFIX \
                docker run --detach=true -v $REPLICA_DATA:/data \
                 -v $REPLICA_LOGS:/logs --net=host \
                 --name=replica$PORT_REPLICA ${DOCKER_IMAGE_NAME} \
                  arangod --database.directory /data \
                  --frontend-version-check false \
                  --server.endpoint tcp://0.0.0.0:$PORT_REPLICA \
                  --log.file /logs/$PORT_REPLICA.log \
                  --dispatcher.report-interval 15 \
                  --server.foxx-queues false \
                  --server.disable-statistics true \
                  --scheduler.threads 1 \
                  --server.threads 2 \
                  $REPLICA_ARGS \
                  >/dev/null
            do
                echo "Error in remote docker run, retrying..."
            done
        }

        for i in `seq 0 $LASTDBSERVER` ; do
            start_replica $i &
        done

        echo Waiting 10 seconds till replicas are up and running...
        sleep 10

        for i in `seq 0 $LASTDBSERVER` ; do
            j=`expr $i + 1`
            if [ $j -gt $LASTDBSERVER ] ; then
                j=0
            fi
            echo Attaching replica on $j for $i ...
            curl -s -X PUT "http://${SERVERS_EXTERNAL_ARR[$j]}:$PORT_REPLICA/_api/replication/applier-config" -d '{"endpoint":"tcp://'${SERVERS_INTERNAL_ARR[$i]}:$PORT_DBSERVER'","database":"_system","includeSystem":false}' --dump -
            # >/dev/null 2>&1
            TICK=`curl -X PUT "http://${SERVERS_EXTERNAL_ARR[$j]}:$PORT_REPLICA/_api/replication/sync" -d '{"endpoint":"tcp://'${SERVERS_INTERNAL_ARR[$i]}:$PORT_DBSERVER'"}' | sed -e 's/^.*lastLogTick":"\([0-9]*\)"}.*$/\1/'`
            # >/dev/null 2>&1
            curl -X PUT "http://${SERVERS_EXTERNAL_ARR[$j]}:$PORT_REPLICA/_api/replication/applier-start?from=$TICK" --dump - && echo
            # >/dev/null 2>&1
        done
    wait
        
    fi

    echo ""
    echo "=============================================================================="
    echo "Done, your cluster is ready."
    echo "=============================================================================="
    echo ""
    echo "Frontends available at:"
    for i in $COORDINATOR_MACHINES ; do
        echo "   http://${SERVERS_EXTERNAL_ARR[$i]}:$PORT_COORDINATOR"
    done
    echo ""
    echo "Access with docker, using arangosh:"
    for i in $COORDINATOR_MACHINES ; do
        echo "   docker run -it --rm --net=host ${DOCKER_IMAGE_NAME} arangosh --server.endpoint tcp://${SERVERS_EXTERNAL_ARR[$i]}:$PORT_COORDINATOR"
    done
    echo ""
}

# This starts multiple coreos instances using amazon web services and then
# starts an ArangoDB cluster on them.
#
# Use -r to permanently remove an existing cluster and all machine instances.
#
# Optional prerequisites:
# The following environment variables are used:
#
#   SIZE          : size/machine-type of the instance (e.g. -m n1-standard-2)
#   NUMBER        : count of machines to create (e.g. -n 3)
#   Local Network : name of the local network (e.g. -l local_net)
#   Ext. Network  : name of the ext network (e.g. -e ext_net)
#   External IP   : name of the ext network (e.g. -i 10.20.30.40)
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

  CPU    : size/machine-type of the instance (e.g. -c 2)
  MEMORY    : size/machine-type of the instance (e.g. -m 2)
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
  echo "AWS SSH-Key existing."
else
  echo "No AWS SSH-Key existing. Creating a new SSH-Key."

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

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

    DOCKER_IMAGE_NAME=m0ppers/arangodb:3.0

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
    until $SSH_CMD "${SSH_ARGS}" ${SSH_USER}@${SERVERS_EXTERNAL_ARR[0]} $SSH_SUFFIX "docker run --detach=true -e ARANGO_NO_AUTH=1 -p 4001:8529 --name=agency -v $AGENCY_DIR:/var/lib/arangodb3 ${DOCKER_IMAGE_NAME} --agency.id 0 --agency.size 1 --javascript.v8-contexts 2 --agency.supervision true"
    do
        echo "Error in remote docker run, retrying..."
    done

    sleep 1

    start_dbserver () {
        i=$1
        echo Starting DBserver on ${SERVERS_EXTERNAL_ARR[$i]}:$PORT_DBSERVER

        until $SSH_CMD "${SSH_ARGS}" ${SSH_USER}@${SERVERS_EXTERNAL_ARR[$i]} $SSH_SUFFIX \
            docker run -p $PORT_DBSERVER:8529 --detach=true -e ARANGO_NO_AUTH=1 -v $DBSERVER_DATA:/var/lib/arangodb3 \
             --name=dbserver$PORT_DBSERVER ${DOCKER_IMAGE_NAME} \
              arangod --cluster.agency-endpoint tcp://${SERVERS_INTERNAL_ARR[0]}:4001 \
              --cluster.my-address tcp://${SERVERS_INTERNAL_ARR[$i]}:$PORT_DBSERVER \
              --cluster.my-local-info dbserver:${SERVERS_INTERNAL_ARR[$i]}:$PORT_DBSERVER \
              --cluster.my-role PRIMARY \
              --scheduler.threads 3 \
              --server.threads 5 \
              --javascript.v8-contexts 6 \
              $DBSERVER_ARGS
        do
            echo "Error in remote docker run, retrying..."
        done
    }

    start_coordinator () {
        i=$1
        echo Starting Coordinator on ${SERVERS_EXTERNAL_ARR[$i]}:$PORT_COORDINATOR

        until $SSH_CMD "${SSH_ARGS}" ${SSH_USER}@${SERVERS_EXTERNAL_ARR[$i]} $SSH_SUFFIX \
            docker run -p $PORT_COORDINATOR:8529 --detach=true -e ARANGO_NO_AUTH=1 -v $COORDINATOR_DATA:/var/lib/arangodb3 \
                --name=coordinator$PORT_COORDINATOR \
                ${DOCKER_IMAGE_NAME} \
              arangod --cluster.agency-endpoint tcp://${SERVERS_INTERNAL_ARR[0]}:4001 \
               --cluster.my-address tcp://${SERVERS_INTERNAL_ARR[$i]}:$PORT_COORDINATOR \
               --cluster.my-local-info \
                         coordinator:${SERVERS_INTERNAL_ARR[$i]}:$PORT_COORDINATOR \
               --cluster.my-role COORDINATOR \
               --scheduler.threads 4 \
               --javascript.v8-contexts 11 \
               --server.threads 10 \
               $COORDINATOR_ARGS
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
    
    DBSERVER_IDS=()
    for i in `seq 0 $LASTDBSERVER` ; do
        testServer ${SERVERS_EXTERNAL_ARR[$i]}:$PORT_DBSERVER
        DBSERVER_IDS[$i]=$(curl http://"${SERVERS_EXTERNAL_ARR[$i]}:$PORT_DBSERVER"/_admin/server/id)
    done

    for i in $COORDINATOR_MACHINES ; do
        testServer ${SERVERS_EXTERNAL_ARR[$i]}:$PORT_COORDINATOR
    done
    
    if [ ! -z "$REPLICAS" ] ; then
        start_replica () {
            i=$1
            j=`expr $i + 1`
            ID="Secondary$j"
            if [ $j -gt $LASTDBSERVER ] ; then
                j=0
            fi
            echo Starting asynchronous replica for
            echo "  ${SERVERS_EXTERNAL_ARR[$i]}:$PORT_DBSERVER on ${SERVERS_EXTERNAL_ARR[$j]}:$PORT_REPLICA"
            
            while true; do
              curl -f -X PUT --data "{\"primary\": \"${DBSERVER_IDS[$i]}\", \"oldSecondary\": \"none\", \"newSecondary\": \"${ID}\"}" -H "Content-Type: application/json" "${SERVERS_EXTERNAL_ARR[$i]}:$PORT_COORDINATOR"/_admin/cluster/replaceSecondary
              if [ "$?" == "0" ]; then
                break
              fi
              echo "Failed registering secondary...Retrying..."
              sleep 1
            done

            until $SSH_CMD "${SSH_ARGS}" ${SSH_USER}@${SERVERS_EXTERNAL_ARR[$j]} $SSH_SUFFIX \
                docker run -p 8529:$PORT_REPLICA --detach=true -e ARANGO_NO_AUTH=1 -v $REPLICA_DATA:/var/lib/arangodb3 \
                 --name=replica$PORT_REPLICA ${DOCKER_IMAGE_NAME} \
                  arangod \
                  --cluster.my-id "$ID" \
                  --cluster.my-role SECONDARY \
                  --scheduler.threads 3 \
                  --server.threads 5 \
                  --javascript.v8-contexts 6 \
                  $REPLICA_ARGS
            do
                echo "Error in remote docker run, retrying..."
            done
        }

        for i in `seq 0 $LASTDBSERVER` ; do
            start_replica $i
        done

        echo Waiting 10 seconds till replicas are up and running...
        sleep 10
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
#   SIZE    : size/machine-type of the instance (e.g. -m n1-standard-2)
#   NUMBER  : count of machines to create (e.g. -n 3)
#   OUTPUT  : local output log folder (e.g. -d /my/directory)

trap "kill 0" SIGINT

MACHINE_TYPE="t1.medium"
NUMBER="3"
OUTPUT="aws"
SSH_KEY_PATH=""

function deleteMachine () {
  echo "deleting machine $PREFIX$1"
  id=${SERVERS_IDS_ARR[`expr $1 - 1`]}

  aws ec2 terminate-instances --instance-ids "$id"

  if [ $? -eq 0 ]; then
    echo "OK: Deleted instance $id"
  else
    echo "ERROR: instance $id could not be deleted."
  fi
}

AmazonWebServicesDestroyMachines() {

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

    for i in `seq $NUMBER`; do
      deleteMachine $i &
    done

    wait

    echo "Removing old Security Group: ${PREFIX}security"
    sleep 45
    aws ec2 delete-security-group --group-name "${PREFIX}security"

    echo "Removing old SSH-Keys: ${PREFIX}aws-ssh-key"
    aws ec2 delete-key-pair --key-name "${PREFIX}aws-ssh-key"
    rm -f "$HOME/.ssh/${PREFIX}aws-ssh-key"*

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

while getopts ":m:n:d:s:hr" opt; do
  case $opt in
    h)
       cat <<EOT
This starts multiple coreos instances using amazon web services and then
starts an ArangoDB cluster on them.

Use -r to permanently remove an existing cluster and all machine instances.

Optional prerequisites:
The following environment variables are used:

  SIZE    : size/machine-type of the instance (e.g. -m n1-standard-2)
  NUMBER  : count of machines to create (e.g. -n 3)
  OUTPUT  : local output log folder (e.g. -d /my/directory)
EOT
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
echo "OUTPUT DIRECTORY: $OUTPUT"
echo "ZONE: $zone"
echo "PROJECT: $PROJECT"

DEFAULT_KEY_PATH="$HOME/.ssh/${PREFIX}aws-ssh-key"

#check if project is already set
zone=`cat $HOME/.aws/config | grep region |awk {'print $3'}`

if test -z "$zone";  then
  echo "AWS zone is not configured. Please run: aws configure"
  exit 1
else
  ZONE=$zone
fi

# Function to get latest core os ami ids (stable channel)
# URL: https://coreos.com/dist/aws/aws-stable.json

echo "Your aws zone is: $ZONE"
echo "Searching ami id of latest core os version..."

function jsonval {
  temp=`echo $json | sed 's/\\\\\//\//g' | sed 's/[{}]//g' | awk -v k="text" '{n=split($0,a,","); for (i=1; i<=n; i++) print a[i]}' | sed 's/\"\:\"/\|/g' | sed 's/[\,]/ /g' | sed 's/\"//g' | grep -w $ZONE`
  echo ${temp##*|}
}

json=`curl -s -X GET https://coreos.com/dist/aws/aws-stable.json`
amiid=`jsonval`
IMAGE=`echo $amiid | awk {'print $3'}`
echo "Found image. ID is: $IMAGE"

if test -e "$OUTPUT";  then
  if [ "$REMOVE" == "1" ] ; then
    AmazonWebServicesDestroyMachines
    exit 0
  fi

  echo "$0: refusing to use existing directory '$OUTPUT'"
  exit 1
fi

if [ "$REMOVE" == "1" ] ; then
  echo "$0: did not find an existing directory '$OUTPUT'"
  exit 1
fi

echo "MACHINE_TYPE: $MACHINE_TYPE"
echo "NUMBER OF MACHINES: $NUMBER"
echo "MACHINE PREFIX: $PREFIX"

mkdir -p "$OUTPUT/temp"

if [[ -s "$HOME/.ssh/${PREFIX}aws-ssh-key" ]] ; then
  echo "AWS SSH-Key existing."
else
  echo "No AWS SSH-Key existing. Creating a new SSH-Key."

  ssh-keygen -t rsa -C "${PREFIX}aws-ssh-key" -f "$OUTPUT"/${PREFIX}aws-ssh-key

  if [ $? -eq 0 ]; then
    echo OK
  else
    echo Failed to create SSH-Key. Exiting.
    exit 1
  fi

  cp "$OUTPUT/${PREFIX}aws-ssh-key"* "$HOME/.ssh/"
  chmod 400 "$HOME"/.ssh/${PREFIX}aws-ssh-key
  aws ec2 import-key-pair --key-name "${PREFIX}aws-ssh-key" --public-key-material file://$HOME/.ssh/${PREFIX}aws-ssh-key.pub

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

#echo "Creating VPC"
#a=`aws ec2 create-vpc --cidr-block 10.0.0.0/16`
#
#echo $a
#echo ========
#echo
#vpcid=`echo a | python -mjson.tool | grep VpcId | awk {'print $9'} | cut -c 2- | rev | cut -c 3- | rev`

#echo $vpcid 
#exit 1 
#echo $vpcid > $OUTPUT/vpcid

#echo "Creating Subnet"
#aws ec2 create-subnet --vpc-id "$vpcid" --cidr-block 10.0.1.0/24 --availability-zone "$ZONE"
#subnetid=`echo a | python -mjson.tool | grep SubnetId | awk {'print $2'} | cut -c 2- | rev | cut -c 3- | rev`
#echo $subnetid > $OUTPUT/subnetid

#exit 1


echo "Creating Security Group"
#secureid=`aws ec2 describe-security-groups --output json --group-names ${PREFIX}security |python -mjson.tool|grep GroupId| awk {'print $2'}| cut -c 2- | rev | cut -c 3- | rev`
aws ec2 create-security-group \
    --group-name "${PREFIX}security" \
    --description "Open SSH and needed ArangoDB Ports"

wait
aws ec2 authorize-security-group-ingress \
    --group-name "${PREFIX}security" \
    --cidr 0.0.0.0/0 \
    --protocol tcp --port 22

wait
aws ec2 authorize-security-group-ingress \
    --group-name "${PREFIX}security" \
    --cidr 0.0.0.0/0 \
    --protocol tcp --port 8529

wait
aws ec2 authorize-security-group-ingress \
    --group-name "${PREFIX}security" \
    --cidr 0.0.0.0/0 \
    --protocol tcp --port 8629

wait
aws ec2 authorize-security-group-ingress \
    --group-name "${PREFIX}security" \
    --cidr 0.0.0.0/0 \
    --protocol tcp --port 7001

wait
aws ec2 authorize-security-group-ingress \
    --group-name "${PREFIX}security" \
    --cidr 0.0.0.0/0 \
    --protocol tcp --port 4001

    #--source-group "$secureid" \
wait

function getMachine () {
  currentid=`cat $OUTPUT/temp/IDS$1`
  public=`aws ec2 describe-instances --output json --instance-ids $currentid | grep PublicIpAddress | awk '{print $2}' | cut -c 2- | rev | cut -c 3- | rev`

  state=0
  while [ "$state" == 0 ]; do
    if test -z "$public";  then
     echo "Machine $PREFIX$1 not ready yet."
     sleep 3
    else
     echo "Machine $PREFIX$1 ready."
     state=1
    fi
  done

  echo $public > "$OUTPUT/temp/EXTERNAL$1"
}

function createMachine () {
  echo "creating machine $PREFIX$1"

  INSTANCE=`aws ec2 run-instances --output json --image-id "$IMAGE" --count 1 --instance-type t2.medium \
  --key-name "${PREFIX}aws-ssh-key" --associate-public-ip-address --subnet-id "$subnetid"`

  id=`echo $INSTANCE | python -mjson.tool | grep InstanceId | awk '{print $2}' | cut -c 2- | rev | cut -c 3- | rev`
  priv=`echo $INSTANCE | python -mjson.tool | grep PrivateIpAddress | awk '{print $2}' | head -n 1 | cut -c 2- | rev | cut -c 3- | rev`

  echo $priv > "$OUTPUT/temp/INTERNAL$1"
  echo $id > "$OUTPUT/temp/IDS$1"
}

function setMachineName () {
  echo "Setting up machine names."
  id=`cat "$OUTPUT/temp/IDS$i"`
  aws ec2 create-tags --resources $id --tags Key=Name,Value=$PREFIX$1
}

function setMachineSecurity () {
  echo "Adding security groups."
  id=`cat "$OUTPUT/temp/IDS$i"`
  secureid=$(aws ec2 describe-security-groups --output json --group-names ${PREFIX}security | grep GroupId | sed -e 's/.*: "\([^"]*\)"/\1/g')
  aws ec2 modify-instance-attribute --instance-id "$id" --groups "$secureid"
}

#CoreOS PARAMS
declare -a SERVERS_EXTERNAL_AWS
declare -a SERVERS_INTERNAL_AWS
declare -a SERVERS_IDS_AWS

SSH_USER="core"
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

for i in `seq $NUMBER`; do
  setMachineName $i &
done

wait

for i in `seq $NUMBER`; do
  setMachineSecurity $i &
done

wait

while :
do

  FINISHED=0

  for i in `seq $NUMBER`; do

    if [ -s "$OUTPUT/temp/INTERNAL$i" ] ; then
      SERVERS_INTERNAL_AWS[`expr $i - 1`]=`cat "$OUTPUT/temp/INTERNAL$i"`
      SERVERS_EXTERNAL_AWS[`expr $i - 1`]=`cat "$OUTPUT/temp/EXTERNAL$i"`
      SERVERS_IDS_AWS[`expr $i - 1`]=`cat "$OUTPUT/temp/IDS$i"`
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

echo Internal IPs: ${SERVERS_INTERNAL_AWS[@]}
echo External IPs: ${SERVERS_EXTERNAL_AWS[@]}
echo IDs         : ${SERVERS_IDS_AWS[@]}

echo Remove host key entries in ~/.ssh/known_hosts...
for ip in ${SERVERS_EXTERNAL_AWS[@]} ; do
  ssh-keygen -f ~/.ssh/known_hosts -R $ip
done

SERVERS_INTERNAL="${SERVERS_INTERNAL_AWS[@]}"
SERVERS_EXTERNAL="${SERVERS_EXTERNAL_AWS[@]}"
SERVERS_IDS="${SERVERS_IDS_AWS[@]}"

# Write data to file:
echo > $OUTPUT/clusterinfo.sh "SERVERS_INTERNAL=\"$SERVERS_INTERNAL\""
echo >>$OUTPUT/clusterinfo.sh "SERVERS_EXTERNAL=\"$SERVERS_EXTERNAL\""
echo >>$OUTPUT/clusterinfo.sh "SERVERS_IDS=\"$SERVERS_IDS\""
echo >>$OUTPUT/clusterinfo.sh "SSH_USER=\"$SSH_USER\""
echo >>$OUTPUT/clusterinfo.sh "SSH_CMD=\"$SSH_CMD\""
echo >>$OUTPUT/clusterinfo.sh "SSH_SUFFIX=\"$SSH_SUFFIX\""
echo >>$OUTPUT/clusterinfo.sh "PREFIX=\"$PREFIX\""
echo >>$OUTPUT/clusterinfo.sh "ZONE=\"$ZONE\""

# Export needed variables
export SERVERS_INTERNAL
export SERVERS_EXTERNAL
export SERVERS_IDS
export SSH_USER="core"
export SSH_CMD="ssh"
export SSH_SUFFIX="-i $DEFAULT_KEY_PATH -l $SSH_USER"
export ZONE

sleep 5

startArangoDBClusterWithDocker

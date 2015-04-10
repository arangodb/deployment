all: DigitalOcean_ArangoDB_Cluster.sh

DigitalOcean_ArangoDB_Cluster.sh: Makefile platformDO/DigitalOcean_ArangoDB_Cluster.sh Docker/ArangoDBClusterWithDocker.sh
	echo "#!/bin/bash" > $@
	cat Docker/ArangoDBClusterWithDocker.sh >> $@
	cat platformDO/DigitalOcean_ArangoDB_Cluster.sh >> $@
	chmod 755 $@

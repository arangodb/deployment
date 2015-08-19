all: DigitalOcean_ArangoDB_Cluster.sh GoogleComputeEngine_ArangoDB_Cluster.sh Azure_ArangoDB_Cluster.sh AmazonWebServices_ArangoDB_Cluster.sh GoogleComputeEngine_Mesos_Cluster.sh

DigitalOcean_ArangoDB_Cluster.sh: Makefile platformDO/DigitalOcean_ArangoDB_Cluster.sh Docker/ArangoDBClusterWithDocker.sh
	echo "#!/bin/bash" > $@
	cat Docker/ArangoDBClusterWithDocker.sh >> $@
	cat platformDO/DigitalOcean_ArangoDB_Cluster.sh >> $@
	chmod 755 $@

GoogleComputeEngine_ArangoDB_Cluster.sh: Makefile platformGCE/GoogleComputeEngine_ArangoDB_Cluster.sh Docker/ArangoDBClusterWithDocker.sh
	echo "#!/bin/bash" > $@
	cat Docker/ArangoDBClusterWithDocker.sh >> $@
	cat platformGCE/GoogleComputeEngine_ArangoDB_Cluster.sh >> $@
	chmod 755 $@

Azure_ArangoDB_Cluster.sh: Makefile platformAZURE/Azure_ArangoDB_Cluster.sh Docker/ArangoDBClusterWithDocker.sh
	echo "#!/bin/bash" > $@
	cat Docker/ArangoDBClusterWithDocker.sh >> $@
	cat platformAZURE/Azure_ArangoDB_Cluster.sh >> $@
	chmod 755 $@

AmazonWebServices_ArangoDB_Cluster.sh: Makefile platformAWS/AmazonWebServices_ArangoDB_Cluster.sh Docker/ArangoDBClusterWithDocker.sh
	echo "#!/bin/bash" > $@
	cat Docker/ArangoDBClusterWithDocker.sh >> $@
	cat platformAWS/AmazonWebServices_ArangoDB_Cluster.sh >> $@
	chmod 755 $@

GoogleComputeEngine_Mesos_Cluster.sh: Makefile platformGCE/GoogleComputeEngine_Mesos_Cluster.sh Ubuntu/MesosClusterOnUbuntu.sh
	echo "#!/bin/bash" > $@
	cat Ubuntu/MesosClusterOnUbuntu.sh >> $@
	cat platformGCE/GoogleComputeEngine_Mesos_Cluster.sh >> $@
	chmod 755 $@

clean:
	rm -f DigitalOcean_ArangoDB_Cluster.sh GoogleComputeEngine_ArangoDB_Cluster.sh Azure_ArangoDB_Cluster.sh AmazonWebServices_ArangoDB_Cluster.sh GoogleComputeEngine_Mesos_Cluster

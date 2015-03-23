# deployment

### GCE (Google Compute Engine)
For deployment at google computing engine cloud you need the gcloud Tool Guide:
  - https://cloud.google.com/sdk/gcloud/

Create a three-instance cluster (GCE project id: cluster-0001):
```sh
$ ./create_gce_machines.sh -p cluster-0001 -n 3
```

### DO (Digital Ocean)
For deployment at digital ocean you need a basic version of python installed:

Create a three-instance cluster:
```sh
$ ./create_do_machines.sh -t $TOKEN -n 3
```

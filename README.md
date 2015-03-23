# deployment

### GCE
For deployment at google computing engine cloud you need the gcloud Tool Guide:
  - https://cloud.google.com/sdk/gcloud/

Create a three-instance cluster (GCE project id: cluster-0001):
```sh
$ ./create_machines.sh -p cluster-0001 -n 3
```

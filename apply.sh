#!/bin/bash
#
source /home/ubuntu/actions-runner/_work/workshop-architecture/workshop-architecture/bash/avi/avi_api.sh
#
yq -c -r /home/ubuntu/actions-runner/_work/workshop-architecture/workshop-architecture/vars.yml | tee /home/ubuntu/vars.json
jsonFile="/home/ubuntu/vars.json"
#
if [[ $(jq -c -r '.zone' $jsonFile | tr '[:upper:]' [:lower:]) != "emea" && \
      $(jq -c -r '.zone' $jsonFile | tr '[:upper:]' [:lower:]) != "us" && \
      $(jq -c -r '.zone' $jsonFile | tr '[:upper:]' [:lower:]) != "apj" ]] ; then
  echo "   +++ .zone should equal to one of the following: 'emea, us, apj'"
  exit 255
fi

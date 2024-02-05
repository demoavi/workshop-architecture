#!/bin/bash
#
source bash/avi_api.sh
#
yq -c -r vars.yml | tee vars.json
jsonFile="vars.json"
#
if [[ $(jq -c -r '.zone' $jsonFile | tr '[:upper:]' [:lower:]) != "emea" && \
      $(jq -c -r '.zone' $jsonFile | tr '[:upper:]' [:lower:]) != "us" && \
      $(jq -c -r '.zone' $jsonFile | tr '[:upper:]' [:lower:]) != "apj" ]] ; then
  echo "   +++ .zone should equal to one of the following: 'emea, us, apj'"
  exit 255
fi

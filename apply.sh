#!/bin/bash
#
source /home/ubuntu/actions-runner/_work/workshop-architecture/workshop-architecture/bash/avi/avi_api.sh
#
yq -c -r . /home/ubuntu/actions-runner/_work/workshop-architecture/workshop-architecture/vars.yml | tee /home/ubuntu/vars.json
jsonFile="/home/ubuntu/vars.json"
#
if [[ $(jq -c -r '.zone' $jsonFile | tr '[:upper:]' [:lower:]) != "emea" && \
      $(jq -c -r '.zone' $jsonFile | tr '[:upper:]' [:lower:]) != "us" && \
      $(jq -c -r '.zone' $jsonFile | tr '[:upper:]' [:lower:]) != "apj" ]] ; then
  echo "   +++ .zone should equal to one of the following: 'emea, us, apj'"
  exit 255
fi
#
zone=$(jq -c -r '.zone' $jsonFile | tr '[:upper:]' [:lower:])
avi_auth_file="/home/ubuntu/.avicreds-${zone}.json"
avi_cookie_file="/home/ubuntu/avi_cookie_${zone}.txt"
rm -f ${avi_cookie_file}
#
avi_username=$(jq -c -r .avi_credentials.username $avi_auth_file)
avi_password=$(jq -c -r .avi_credentials.password $avi_auth_file)
avi_controller=$(jq -c -r .avi_credentials.controller $avi_auth_file)
avi_version=$(jq -c -r .avi_credentials.api_version $avi_auth_file)
#
curl_login=$(curl -s -k -X POST -H "Content-Type: application/json" \
                                -d "{\"username\": \"${avi_username}\", \"password\": \"${avi_password}\"}" \
                                -c ${avi_cookie_file} https://${avi_controller}/login)

#!/bin/bash
#
source /home/ubuntu/actions-runner/_work/workshop-architecture/workshop-architecture/bash/avi/avi_api.sh
#
jsonFile="/home/ubuntu/vars.json"
yq -c -r . /home/ubuntu/actions-runner/_work/workshop-architecture/workshop-architecture/vars.yml | tee ${jsonFile}
#
avi_settings_file="/home/ubuntu/actions-runner/_work/workshop-architecture/workshop-architecture/settings.json"
#
if [[ $(jq -c -r '.zone' $jsonFile | tr '[:upper:]' [:lower:]) != "europe" && \
      $(jq -c -r '.zone' $jsonFile | tr '[:upper:]' [:lower:]) != "us" && \
      $(jq -c -r '.zone' $jsonFile | tr '[:upper:]' [:lower:]) != "asia" ]] ; then
  echo "+++ .zone should equal to one of the following: 'europe, us, asia'"
  exit 255
fi
#
zone=$(jq -c -r '.zone' $jsonFile | tr '[:upper:]' [:lower:])
#
avi_auth_file="/home/ubuntu/.avicreds-${zone}.json"
avi_cookie_file="/home/ubuntu/avi_cookie_${zone}.txt"
rm -f ${avi_cookie_file}
#
#
avi_username=$(jq -c -r .avi_credentials.username $avi_auth_file)
avi_password=$(jq -c -r .avi_credentials.password $avi_auth_file)
avi_controller=$(jq -c -r .avi_credentials.controller $avi_auth_file)
avi_version=$(jq -c -r .avi_credentials.api_version $avi_auth_file)
#
curl_login=$(curl -s -k -X POST -H "Content-Type: application/json" \
                                -d "{\"username\": \"${avi_username}\", \"password\": \"${avi_password}\"}" \
                                -c ${avi_cookie_file} https://${avi_controller}/login)
#
csrftoken=$(cat ${avi_cookie_file} | grep csrftoken | awk '{print $7}')
#
alb_api 2 1 "GET" "${avi_cookie_file}" "${csrftoken}" "admin" "${avi_version}" "" "${avi_controller}" "api/tenant?page_size=-1"
tenant_results=$(echo $response_body | jq -c -r '.results')
#
echo ${tenant_results} | jq -c -r '.[]' | while read tenant
do
  if [[ ${tenant_name} != "admin" ]] ; then
    tenant_name=$(echo ${tenant} | jq -c -r '.name')
    alb_api 2 1 "GET" "${avi_cookie_file}" "${csrftoken}" "${tenant_name}" "${avi_version}" "" "${avi_controller}" "api/pool?page_size=-1"
    for item in $(echo ${response_body} | jq -c -r '.results[]')
    do
      item_name=$(echo ${item} | jq -c -r '.name')
      item_url=$(echo ${item} | jq -c -r '.url')
      echo "+++ pool update"
      json_data='
      {
        "cloud_ref": "/api/cloud/?name='$(jq -c -r '.cloud.name' ${avi_settings_file})'",
        "name": "'${item_name}'",
        "servers": '$(jq -c -r '.pool.'${zone}'.servers' ${avi_settings_file})'
      }'
      alb_api 2 1 "PATCH" "${avi_cookie_file}" "${csrftoken}" "${tenant_name}" "${avi_version}" "${json_data}" "${avi_controller}" "$(echo ${item_url} | grep / | cut -d/ -f4-)"
    done
  fi
done
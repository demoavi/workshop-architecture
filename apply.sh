#!/bin/bash
#
source /home/ubuntu/actions-runner/_work/workshop-architecture/workshop-architecture/bash/avi/avi_api.sh
#
yq -c -r . /home/ubuntu/actions-runner/_work/workshop-architecture/workshop-architecture/vars.yml | tee /home/ubuntu/vars.json
jsonFile="/home/ubuntu/vars.json"
avi_settings_file="/home/ubuntu/actions-runner/_work/workshop-architecture/workshop-architecture/settings.json"
#
if [[ $(jq -c -r '.zone' $jsonFile | tr '[:upper:]' [:lower:]) != "emea" && \
      $(jq -c -r '.zone' $jsonFile | tr '[:upper:]' [:lower:]) != "us" && \
      $(jq -c -r '.zone' $jsonFile | tr '[:upper:]' [:lower:]) != "apj" ]] ; then
  echo "+++ .zone should equal to one of the following: 'emea, us, apj'"
  exit 255
fi
#
if [[ $(jq -c -r '.create' $jsonFile | tr '[:upper:]' [:lower:]) != "true" && \
      $(jq -c -r '.create' $jsonFile | tr '[:upper:]' [:lower:]) != "false" ]] ; then
  echo "+++ .create should equal to one of the following: 'true, false'"
  exit 255
fi
#
zone=$(jq -c -r '.zone' $jsonFile | tr '[:upper:]' [:lower:])
create=$(jq -c -r '.create' $jsonFile | tr '[:upper:]' [:lower:])
#
avi_auth_file="/home/ubuntu/.avicreds-${zone}.json"
avi_attendees_file="/home/ubuntu/attendees-${zone}.json"
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
#
csrftoken=$(cat ${avi_cookie_file} | grep csrftoken | awk '{print $7}')
#
alb_api 2 1 "GET" "${avi_cookie_file}" "${csrftoken}" "admin" "${avi_version}" "" "${avi_controller}" "api/tenant"
tenant_count=$(echo $response_body | jq -c -r '.count')
tenant_results=$(echo $response_body | jq -c -r '.results')
#
alb_api 2 1 "GET" "${avi_cookie_file}" "${csrftoken}" "admin" "${avi_version}" "" "${avi_controller}" "api/user"
user_count=$(echo $response_body | jq -c -r '.count')
user_results=$(echo $response_body | jq -c -r '.results')
#
# create // tenants already exist 
if [[ ${tenant_count} != 1 && ${create} == "true" ]] ; then
  echo "+++ script will exist because tenants already exist, please clean-up"
  exit
fi
#
# create // users already exist 
if [[ ${user_count} != 1 && ${create} == "true" ]] ; then
  echo "+++ script will exist because users already exist, please clean-up"
  exit
fi
#
# create // tenants and users don't exist
if [[ ${tenant_count} == 1 && ${user_count} != 1 && ${create} == "true" ]] ; then
  echo "+++ tenants creation"
  count=1
  jq -c -r .[] $avi_attendees_file | while read attendee
  do
    echo "++++ creation of tenant: $(jq -c -r '.tenant.basename' ${avi_settings_file})${count}"
    json_data='
    {
      "name": "'$(jq -c -r '.tenant.basename' ${avi_settings_file})${count}'",
      "config_settings": {
        "tenant_vrf": '$(jq -c -r '.tenant.config_settings.tenant_vrf' ${avi_settings_file})',
        "se_in_provider_context": '$(jq -c -r '.tenant.config_settings.se_in_provider_context' ${avi_settings_file})',
        "tenant_access_to_provider_se": '$(jq -c -r '.tenant.config_settings.tenant_access_to_provider_se' ${avi_settings_file})'
      }
    }'
    alb_api 2 1 "POST" "${avi_cookie_file}" "${csrftoken}" "admin" "${avi_version}" "${json_data}" "${avi_controller}" "api/tenant"
    echo "+++ users creation"
    json_data='
    {
      "access": [
        {
          "role_ref": "api/tenant/admin/role/role-4cc32293-2006-4468-ac1c-16ca9ccb3f03",
          "tenant_ref": "api/tenant/tenant-066df56f-9835-4cdd-86b4-4cbe5a394429",
          "all_tenants": false
        }
      ],
      "password": "",
      "username": "nicolas.bayle@broadcom.com",
      "name": "nicolas.bayle@broadcom.com",
      "full_name": "nicolas.bayle@broadcom.com",
      "email": "nicolas.bayle@broadcom.com",
      "is_superuser": false,
      "is_active": true,
      "default_tenant_ref": "api/tenant/tenant-066df56f-9835-4cdd-86b4-4cbe5a394429",
      "user_profile_ref": "api/useraccountprofile/useraccountprofile-edb044b0-4b43-4bef-9231-7e391fecb102",
    }'
    #alb_api 2 1 "POST" "${avi_cookie_file}" "${csrftoken}" "admin" "${avi_version}" "${json_data}" "${avi_controller}" "api/user"
    ((count++))
  done
fi
#
# destroy // delete all the tenants except admin tenant
if [[ ${tenant_count} != 1 && ${create} == "false" ]] ; then
  echo "+++ tenants deletion"
  echo ${tenant_results} | jq -c -r '.[]' | while read tenant
  do
    tenant_name=$(echo ${tenant} | jq -c -r '.name')
    tenant_url=$(echo ${tenant} | jq -c -r '.url')
    echo ${tenant_url}
    if [[ ${tenant_name} != "admin" ]] ; then
      echo "++++ deletion of tenant: ${tenant_name}, url ${tenant_url}"
      alb_api 3 5 "DELETE" "${avi_cookie_file}" "${csrftoken}" "admin" "${avi_version}" "" "${avi_controller}" "$(echo ${tenant_url} | grep / | cut -d/ -f4-)"
    fi
  done
fi
#

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
avi_attendee_password=$(jq -c -r '.default_attendee_password' /home/ubuntu/.avi_attendee_password.json)
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
if [[ ${tenant_count} == 1 && ${user_count} == 1 && ${create} == "true" ]] ; then
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
    tenant_ref=$(echo $response_body | jq -c -r '.url')
    echo "+++ users creation"
    json_data='
    {
      "access": [
        {
          "role_ref": "/api/role/?name='$(jq -c -r '.user.role_ref' ${avi_settings_file})'",
          "tenant_ref": "/api/tenant/?name='$(jq -c -r '.tenant.basename' ${avi_settings_file})${count}'",
          "all_tenants": false
        }
      ],
      "password": "'${avi_attendee_password}'",
      "username": "'${attendee}'",
      "name": "'${attendee}'",
      "full_name": "'${attendee}'",
      "email": "'${attendee}'",
      "is_superuser": false,
      "is_active": true,
      "default_tenant_ref": "/api/tenant/?name='$(jq -c -r '.tenant.basename' ${avi_settings_file})${count}'",
      "user_profile_ref": "/api/useraccountprofile/?name='$(jq -c -r '.user.user_profile_ref' ${avi_settings_file})'"
    }'
    alb_api 2 1 "POST" "${avi_cookie_file}" "${csrftoken}" "admin" "${avi_version}" "${json_data}" "${avi_controller}" "api/user"
    echo "+++ hms creation"
    json_data='
    {
      "name": "'$(jq -c -r '.tenant.basename' ${avi_settings_file})${count}''$(jq -c -r '.healthmonitor.basename' ${avi_settings_file})'",
      "type": "'$(jq -c -r '.healthmonitor.type' ${avi_settings_file})'",
      "receive_timeout": "'$(jq -c -r '.healthmonitor.receive_timeout' ${avi_settings_file})'",
      "failed_checks": "'$(jq -c -r '.healthmonitor.failed_checks' ${avi_settings_file})'",
      "send_interval": "'$(jq -c -r '.healthmonitor.send_interval' ${avi_settings_file})'",
      "successful_checks": "'$(jq -c -r '.healthmonitor.successful_checks' ${avi_settings_file})'",
      "http_monitor": {
        "http_request": "'$(jq -c -r '.healthmonitor.http_request' ${avi_settings_file})'",
        "http_response_code": '$(jq -c -r '.healthmonitor.http_response_code' ${avi_settings_file})'
      }  
    }'
    echo ${json_data} | jq -c -r '.'    
    alb_api 2 1 "POST" "${avi_cookie_file}" "${csrftoken}" "$(jq -c -r '.tenant.basename' ${avi_settings_file})${count}" "${avi_version}" "${json_data}" "${avi_controller}" "api/healthmonitor"
    echo "+++ pools creation"
    json_data='
    {
      "cloud_ref": "/api/cloud/?name='$(jq -c -r '.cloud.name' ${avi_settings_file})'",
      "name": "'$(jq -c -r '.tenant.basename' ${avi_settings_file})${count}''$(jq -c -r '.pool.basename' ${avi_settings_file})'",
      "health_monitor_refs": ["/api/healthmonitor/?name='$(jq -c -r '.tenant.basename' ${avi_settings_file})${count}''$(jq -c -r '.healthmonitor.basename' ${avi_settings_file})'"],
      "servers": '$(jq -c -r '.pool.servers' ${avi_settings_file})'
    }'
    echo ${json_data} | jq -c -r '.'
    alb_api 2 1 "POST" "${avi_cookie_file}" "${csrftoken}" "$(jq -c -r '.tenant.basename' ${avi_settings_file})${count}" "${avi_version}" "${json_data}" "${avi_controller}" "api/pool"
    echo "+++ vsvip creation"
    json_data='
    {
       "cloud_ref": "/api/cloud/?name='$(jq -c -r '.cloud.name' ${avi_settings_file})'",
       "tenant_ref": "/api/tenant/?name='$(jq -c -r '.tenant.basename' ${avi_settings_file})${count}'",
       "name": "'$(jq -c -r '.tenant.basename' ${avi_settings_file})${count}''$(jq -c -r '.vsvip.basename' ${avi_settings_file})'",
       "vip":
       [
         {
           "auto_allocate_ip": true,
           "auto_allocate_floating_ip": true,
           "availability_zone": "'$(jq -c -r '.vsvip.availability_zone' ${avi_settings_file})'",
           "ipam_network_subnet":
           {
             "subnet":
             {
               "mask": '$(jq -c -r '.vsvip.mask' ${avi_settings_file})',
               "ip_addr":
               {
                 "type": "'$(jq -c -r '.vsvip.type' ${avi_settings_file})'",
                 "addr": "'$(jq -c -r '.vsvip.addr' ${avi_settings_file})'"
               }
             }
           }
         }
       ],
       "dns_info":
       [
         {
           "fqdn": "'$(jq -c -r '.tenant.basename' ${avi_settings_file})${count}''$(jq -c -r '.vs.basename' ${avi_settings_file})'.'$(jq -c -r '.vsvip.domain' ${avi_settings_file})'"
         }
       ]
    }'
    echo ${json_data} | jq -c -r '.'
    alb_api 2 1 "POST" "${avi_cookie_file}" "${csrftoken}" "$(jq -c -r '.tenant.basename' ${avi_settings_file})${count}" "${avi_version}" "${json_data}" "${avi_controller}" "api/vsvip"    
    echo "+++ VSs creation"
    json_data='
    {
      "cloud_ref": "/api/cloud/?name='$(jq -c -r '.cloud.name' ${avi_settings_file})'",
      "name": "'$(jq -c -r '.tenant.basename' ${avi_settings_file})${count}''$(jq -c -r '.vs.basename' ${avi_settings_file})'",
      "pool_ref": "/api/pool/?name='$(jq -c -r '.tenant.basename' ${avi_settings_file})${count}''$(jq -c -r '.pool.basename' ${avi_settings_file})'",
      "application_profile_ref": "/api/applicationprofile/?name='$(jq -c -r '.vs.application_profile_ref' ${avi_settings_file})'",
      "ssl_profile_ref": "/api/sslprofile/?name='$(jq -c -r '.vs.ssl_profile_ref' ${avi_settings_file})'",
      "ssl_key_and_certificate_refs": ["/api/sslkeyandcertificate/?name='$(jq -c -r '.vs.ssl_key_and_certificate_ref' ${avi_settings_file})'"],
      "vsvip_ref": "/api/pool/?name='$(jq -c -r '.tenant.basename' ${avi_settings_file})${count}''$(jq -c -r '.vsvip.basename' ${avi_settings_file})'",
      "services": [
        {
          "port": "'$(jq -c -r '.vs.port' ${avi_settings_file})'",
          "enable_ssl": "'$(jq -c -r '.vs.enable_ssl' ${avi_settings_file})'"
        }
      ]
    }'
    echo ${json_data} | jq -c -r '.'
    alb_api 2 1 "POST" "${avi_cookie_file}" "${csrftoken}" "$(jq -c -r '.tenant.basename' ${avi_settings_file})${count}" "${avi_version}" "${json_data}" "${avi_controller}" "api/virtualservice"
    echo "++++ New Users ++++"
    ((count++))
  done
fi
#
# destroy // delete all the users (except admin user) and the tenants (except admin tenant)
if [[ ${create} == "false" ]] ; then
  alb_api 2 1 "GET" "${avi_cookie_file}" "${csrftoken}" "*" "${avi_version}" "" "${avi_controller}" "api/virtualservice"
  echo $response_body | jq -c -r '.results[]' | while read vs
  do
    vs_name=$(echo ${vs} | jq -c -r '.name')
    vs_url=$(echo ${vs} | jq -c -r '.url')
    vs_tenant_uuid=$(echo ${vs} | jq -c -r '.tenant_ref' | grep / | cut -d/ -f6-)
    vs_tenant_name=$(echo ${tenant_results} | jq -c -r --arg arg "${vs_tenant_uuid}" '.[] | select( .uuid == $arg ) | .name')
    if [[ ${vs_tenant_name} != "admin" ]] ; then
      echo "++++ deletion of vs: ${vs_name}, url ${vs_url}"
      alb_api 3 5 "DELETE" "${avi_cookie_file}" "${csrftoken}" "${vs_tenant_name}" "${avi_version}" "" "${avi_controller}" "$(echo ${vs_url} | grep / | cut -d/ -f4-)"
    fi    
  done
  alb_api 2 1 "GET" "${avi_cookie_file}" "${csrftoken}" "*" "${avi_version}" "" "${avi_controller}" "api/pool"
  echo $response_body | jq -c -r '.results[]' | while read pool
  do
    pool_name=$(echo ${pool} | jq -c -r '.name')
    pool_url=$(echo ${pool} | jq -c -r '.url')
    pool_tenant_uuid=$(echo ${pool} | jq -c -r '.tenant_ref' | grep / | cut -d/ -f6-)
    pool_tenant_name=$(echo ${tenant_results} | jq -c -r --arg arg "${pool_tenant_uuid}" '.[] | select( .uuid == $arg ) | .name')
    if [[ ${pool_tenant_name} != "admin" ]] ; then
      echo "++++ deletion of pool: ${pool_name}, url ${pool_url}"
      alb_api 3 5 "DELETE" "${avi_cookie_file}" "${csrftoken}" "${pool_tenant_name}" "${avi_version}" "" "${avi_controller}" "$(echo ${pool_url} | grep / | cut -d/ -f4-)"
    fi    
  done
  alb_api 2 1 "GET" "${avi_cookie_file}" "${csrftoken}" "*" "${avi_version}" "" "${avi_controller}" "api/healthmonitor"
  IFS=$'\n'
  for hm in $(echo ${response_body} | jq -c -r '.[]')
  do
    hm_name=$(echo ${hm} | jq -c -r '.name')
    echo ${hm_name}
    hm_url=$(echo ${hm} | jq -c -r '.url')
    echo ${hm_url}
    hm_tenant_uuid=$(echo ${hm} | jq -c -r '.tenant_ref' | grep / | cut -d/ -f6-)
    echo ${hm_tenant_uuid}
    hm_tenant_name=$(echo ${tenant_results} | jq -c -r --arg arg "${hm_tenant_uuid}" '.[] | select( .uuid == $arg ) | .name')
    if [[ ${hm_tenant_name} != "admin" ]] ; then
      echo "++++ deletion of health monitor: ${hm_name}, url ${hm_url}"
      alb_api 3 5 "DELETE" "${avi_cookie_file}" "${csrftoken}" "${hm_tenant_name}" "${avi_version}" "" "${avi_controller}" "$(echo ${hm_url} | grep / | cut -d/ -f4-)"
    fi    
  done
  exit  
  IFS=$'\n'
  for user in $(echo ${user_results} | jq -c -r '.[]')
  do
    user_name=$(echo ${user} | jq -c -r '.username')
    user_url=$(echo ${user} | jq -c -r '.url')
    if [[ ${user_name} != "admin" ]] ; then
      echo "++++ deletion of user: ${user_name}, url ${user_url}"
      alb_api 3 5 "DELETE" "${avi_cookie_file}" "${csrftoken}" "admin" "${avi_version}" "" "${avi_controller}" "$(echo ${user_url} | grep / | cut -d/ -f4-)"
    fi    
  done
  #
  echo ${tenant_results} | jq -c -r '.[]' | while read tenant
  do
    tenant_name=$(echo ${tenant} | jq -c -r '.name')
    tenant_url=$(echo ${tenant} | jq -c -r '.url')
    if [[ ${tenant_name} != "admin" ]] ; then
      echo "++++ deletion of tenant: ${tenant_name}, url ${tenant_url}"
      alb_api 3 5 "DELETE" "${avi_cookie_file}" "${csrftoken}" "admin" "${avi_version}" "" "${avi_controller}" "$(echo ${tenant_url} | grep / | cut -d/ -f4-)"
    fi
  done
fi
#

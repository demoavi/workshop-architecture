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
avi_attendee_txt="/home/ubuntu/attendees-${zone}.txt"
avi_cookie_file="/home/ubuntu/avi_cookie_${zone}.txt"
avi_attendee_password=$(jq -c -r '.default_attendee_password' /home/ubuntu/.avi_attendee_password.json)
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
tenant_count=$(echo $response_body | jq -c -r '.count')
tenant_results=$(echo $response_body | jq -c -r '.results')
#
alb_api 2 1 "GET" "${avi_cookie_file}" "${csrftoken}" "admin" "${avi_version}" "" "${avi_controller}" "api/user?page_size=-1"
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
  # create json file from txt file
  rm -f ${avi_attendees_file}
  json_attendees_list="[]"
  while read -r line; do json_attendees_list=$(echo $json_attendees_list | jq '. += ["'${line}'"]') ; done < "${avi_attendee_txt}"
  echo ${json_attendees_list} | tr '[:upper:]' [:lower:] | jq . | tee ${avi_attendees_file}
  #
  echo "+++ tenants creation"
  count=1
  jq -c -r .[] $avi_attendees_file | while read attendee
  do
    echo "++++ tenant creation: $(jq -c -r '.tenant.basename' ${avi_settings_file})${count}"
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
    echo "+++ user creation"
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
    ((count++))
  done
  jq -c -r .[] $avi_attendees_file | while read attendee
  do
    echo "+++ hm creation"
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
    #echo ${json_data} | jq -c -r '.'    
    alb_api 2 1 "POST" "${avi_cookie_file}" "${csrftoken}" "$(jq -c -r '.tenant.basename' ${avi_settings_file})${count}" "${avi_version}" "${json_data}" "${avi_controller}" "api/healthmonitor"
    echo "+++ pool creation"
    json_data='
    {
      "cloud_ref": "/api/cloud/?name='$(jq -c -r '.cloud.name' ${avi_settings_file})'",
      "name": "'$(jq -c -r '.tenant.basename' ${avi_settings_file})${count}''$(jq -c -r '.pool.basename' ${avi_settings_file})'",
      "health_monitor_refs": ["/api/healthmonitor/?name='$(jq -c -r '.tenant.basename' ${avi_settings_file})${count}''$(jq -c -r '.healthmonitor.basename' ${avi_settings_file})'"],
      "servers": '$(jq -c -r '.pool.'${zone}'.servers' ${avi_settings_file})'
    }'
    #echo ${json_data} | jq -c -r '.'
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
    #echo ${json_data} | jq -c -r '.'
    alb_api 2 1 "POST" "${avi_cookie_file}" "${csrftoken}" "$(jq -c -r '.tenant.basename' ${avi_settings_file})${count}" "${avi_version}" "${json_data}" "${avi_controller}" "api/vsvip"    
    echo "+++ vs creation"
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
    #echo ${json_data} | jq -c -r '.'
    alb_api 2 1 "POST" "${avi_cookie_file}" "${csrftoken}" "$(jq -c -r '.tenant.basename' ${avi_settings_file})${count}" "${avi_version}" "${json_data}" "${avi_controller}" "api/virtualservice"
    ((count++))
  done
fi
#
# destroy // delete all vs, pool, hm, vsvip which are not in the admin tenant
#                       the users (except admin user) and the tenants (except admin tenant)
#
if [[ ${create} == "false" ]] ; then
  #
  IFS=$'\n'
  list_object_to_remove='["alertconfig", "actiongroupconfig", "alertemailconfig", "virtualservice", "pool", "healthmonitor", "vsvip", "networksecuritypolicy", "applicationprofile", "serviceengine", "serviceenginegroup", "analyticsprofile", "wafpolicy", "wafpolicypsmgroup", "httppolicyset", "sslprofile", "autoscalelaunchconfig"]'
  for object_to_remove in $(echo $list_object_to_remove | jq -c -r .[])
  do
    if [[ ${object_to_remove} == "serviceenginegroup" && ${se_deletion} == "true" ]] ; then
      echo "++++ wait for 240 secs for the time to remove the SE"
      sleep 240
    fi
    alb_api 2 1 "GET" "${avi_cookie_file}" "${csrftoken}" "*" "${avi_version}" "" "${avi_controller}" "api/${object_to_remove}?page_size=-1"
    for item in $(echo ${response_body} | jq -c -r '.results[]')
    do
      item_name=$(echo ${item} | jq -c -r '.name')
      item_url=$(echo ${item} | jq -c -r '.url')
      item_tenant_uuid=$(echo ${item} | jq -c -r '.tenant_ref' | grep / | cut -d/ -f6-)
      item_tenant_name=$(echo ${tenant_results} | jq -c -r --arg arg "${item_tenant_uuid}" '.[] | select( .uuid == $arg ) | .name')
      echo ${object_to_remove}
      echo ${item_tenant_name}
      if [[ ${object_to_remove} == "serviceengine" ]] ; then
        if $(echo $item | jq -e '.vs_refs' > /dev/null) ; then
          echo "++++ se ${item_name} is busy with vs"
        else
          se_deletion="true"
          alb_api 3 5 "DELETE" "${avi_cookie_file}" "${csrftoken}" "${item_tenant_name}" "${avi_version}" "" "${avi_controller}" "$(echo ${item_url} | grep / | cut -d/ -f4-)"
        fi
      fi
      if [[ ${item_tenant_name} != "admin" && ${object_to_remove} != "serviceengine" ]] ; then
        if [[ ${object_to_remove} == "serviceenginegroup" && ${item_name} != "Default-Group" ]] ; then
          echo "++++ deletion of ${object_to_remove}: ${item_name}, url ${item_url}"
          alb_api 3 5 "DELETE" "${avi_cookie_file}" "${csrftoken}" "${item_tenant_name}" "${avi_version}" "" "${avi_controller}" "$(echo ${item_url} | grep / | cut -d/ -f4-)"  
        fi
        if [[ ${object_to_remove} == "analyticsprofile" && ${item_name} != "System-Analytics-Profile" ]] ; then
          echo "++++ deletion of ${object_to_remove}: ${item_name}, url ${item_url}"
          alb_api 3 5 "DELETE" "${avi_cookie_file}" "${csrftoken}" "${item_tenant_name}" "${avi_version}" "" "${avi_controller}" "$(echo ${item_url} | grep / | cut -d/ -f4-)"  
        fi
        if [[ ${object_to_remove} == "wafpolicy" ]] ; then
          if [[ ${item_name} != "System-WAF-Policy" || ${item_name} != "System-WAF-Policy-VDI" ]] ; then
            echo "++++ deletion of ${object_to_remove}: ${item_name}, url ${item_url}"
            alb_api 3 5 "DELETE" "${avi_cookie_file}" "${csrftoken}" "${item_tenant_name}" "${avi_version}" "" "${avi_controller}" "$(echo ${item_url} | grep / | cut -d/ -f4-)"  
          fi  
        fi        
        if [[ ${object_to_remove} != "serviceenginegroup" && ${object_to_remove} != "analyticsprofile" && ${object_to_remove} != "wafpolicy" ]] ; then 
          echo "++++ deletion of ${object_to_remove}: ${item_name}, url ${item_url}"
          alb_api 3 5 "DELETE" "${avi_cookie_file}" "${csrftoken}" "${item_tenant_name}" "${avi_version}" "" "${avi_controller}" "$(echo ${item_url} | grep / | cut -d/ -f4-)"
        fi 
      fi
    done
  done
  #
  alb_api 2 1 "GET" "${avi_cookie_file}" "${csrftoken}" "admin" "${avi_version}" "" "${avi_controller}" "api/useractivity?page_size=-1"
  #useractivity_count=$(echo $response_body | jq -c -r '.count')
  useractivity_results=$(echo $response_body | jq -c -r '.results')
  date_index=$(date '+%Y%m%d%H%M%S')
  echo ${useractivity_results} | jq -c -r '.[]' | while read useractivity
  do
    useractivity_name=$(echo ${useractivity} | jq -c -r '.name')
    if $(echo ${useractivity} | jq -e '.last_login_ip' > /dev/null); then
      if [[ ${useractivity_name} != "admin" ]] ; then
        echo "++++ record of user: ${useractivity_name} which had activity"
        echo ${useractivity_name} | tee -a /home/ubuntu/useractivity-${date_index}-${zone}.json
      fi
    fi
  done
  #
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
  count=1
  echo ${tenant_results} | jq -c -r '.[]' | while read tenant
  do
    tenant_name=$(echo ${tenant} | jq -c -r '.name')
    tenant_url=$(echo ${tenant} | jq -c -r '.url')
    if [[ ${tenant_name} != "admin" ]] ; then
      echo "++++ deletion of tenant: ${tenant_name}, url ${tenant_url}"
      alb_api 3 5 "DELETE" "${avi_cookie_file}" "${csrftoken}" "admin" "${avi_version}" "" "${avi_controller}" "$(echo ${tenant_url} | grep / | cut -d/ -f4-)"
      ((count++))
    fi
  done
fi

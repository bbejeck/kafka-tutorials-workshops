#! /bin/sh

cp stack-configs/java-service* docker-compose-ccloud-vars.env

perl -pi -e 's/bootstrap\.servers/bootstrap_servers/g' docker-compose-ccloud-vars.env
perl -pi -e 's/sasl\.jaas\.config/sasl_jaas_config/g' docker-compose-ccloud-vars.env
perl -pi -e 's/schema\.registry\.url/schema_registry_url/g' docker-compose-ccloud-vars.env
perl -pi -e 's/schema\.registry\.basic\.auth\.user\.info/schema_registry_basic_auth_user_info/g' docker-compose-ccloud-vars.env
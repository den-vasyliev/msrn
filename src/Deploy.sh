#!/bin/bash
#+x
# required settings
NODE_NAME="$(curl --silent --show-error --retry 3 http://169.254.169.254/latest/meta-data/instance-id)" # this uses the EC2 instance ID as the node name
REGION="eu-west-1" # use one of us-east-1, us-west-2, eu-west-1
CHEF_SERVER_NAME="chef-server" # The name of your Chef Server
CHEF_SERVER_ENDPOINT="api.chef.io" # The FQDN of your Chef Server

# optional
CHEF_ORGANIZATION="joinup"    # AWS OpsWorks for Chef Server always creates the organization "default"
NODE_ENVIRONMENT=""            # E.g. development, staging, onebox ...
CHEF_CLIENT_VERSION="12.20.3" # latest if empty
VALIDATION_PEM="${CHEF_ORGANIZATION}-validator.pem"
# recommended: upload the chef-client cookbook from the chef supermarket  https://supermarket.chef.io/cookbooks/chef-client
# Use this to apply sensible default settings for your chef-client config like logrotate and running as a service
# you can add more cookbooks in the run list, based on your needs
RUN_LIST="role[msrn_deploy]" # e.g. "recipe[chef-client],recipe[apache2]"

# ---------------------------
set -e -o pipefail
AWS_CLI_TMP_FOLDER=$(mktemp --directory "/tmp/awscli_XXXX")
CHEF_CA_PATH="/etc/chef/opsworks-cm-ca-2016-root.pem"

write_chef_config() {
	mkdir -p /etc/chef
  (
    echo "chef_server_url   'https://${CHEF_SERVER_ENDPOINT}/organizations/${CHEF_ORGANIZATION}'"
    echo "node_name         '${NODE_NAME}'"
	echo "validation_client_name '${CHEF_ORGANIZATION}-validator'"
	echo "validation_key '/etc/chef/${VALIDATION_PEM}'"
  #  echo "ssl_ca_file       '${CHEF_CA_PATH}'"
  ) >> /etc/chef/client.rb
}

download_validator() {
	aws configure set s3.signature_version s3v4
	aws s3 cp s3://msrn-dev/${VALIDATION_PEM} /etc/chef/ --region=${REGION}
	chown root:root /etc/chef/${VALIDATION_PEM}
	chmod 644 /etc/chef/${VALIDATION_PEM}
}

install_chef_client() {
  # see: https://docs.chef.io/install_omnibus.html
  curl --silent --show-error --retry 3 --location https://omnitruck.chef.io/install.sh | bash -s -- -v "${CHEF_CLIENT_VERSION}"
}

install_chef_client
write_chef_config
download_validator

if [ -z "${NODE_ENVIRONMENT}" ]; then
 sudo chef-client -r "${RUN_LIST}"
else
 sudo chef-client -r "${RUN_LIST}" -E "${NODE_ENVIRONMENT}"
fi
sleep 10
rm /etc/chef/${VALIDATION_PEM}
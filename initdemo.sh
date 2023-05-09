#!/bin/bash

if ! which docker
then
  echo "You must install Docker: https://docs.docker.com/get-docker/"
  exit 1
fi

if ! which octo
then
  echo "You must install the Octopus client from https://octopus.com/downloads/octopuscli"
  exit 1
fi

if ! which curl
then
  echo "You must install curl"
  exit 1
fi

if ! which terraform
then
  echo "You must install terraform: https://developer.hashicorp.com/terraform/downloads"
  exit 1
fi

if ! which minikube
then
  echo "You must install minikube"
  exit 1
fi

if ! which openssl
then
  echo "You must install openssl"
  exit 1
fi

if ! which jq
then
  echo "You must install jq"
  exit 1
fi

if [[ -z "${OCTOPUS_SERVER_BASE64_LICENSE}" ]]
then
  echo "You must set the OCTOPUS_SERVER_BASE64_LICENSE environment variable to the base 64 encoded representation of an Octopus license."
  exit 1
fi

if [[ -z "${TF_VAR_docker_username}" ]]
then
  echo "You must set the TF_VAR_docker_username environment variable to the DockerHub username."
  exit 1
fi

if [[ -z "${TF_VAR_docker_password}" ]]
then
  echo "You must set the TF_VAR_docker_password environment variable to the DockerHub password."
  exit 1
fi

# Use the default values for the individual tenants if there are no specific values defined
if [[ -z "${TF_VAR_america_docker_username}" ]]
then
  export TF_VAR_america_docker_username=$TF_VAR_docker_username
  export TF_VAR_america_docker_password=$TF_VAR_docker_password
fi

if [[ -z "${TF_VAR_europe_docker_username}" ]]
then
  export TF_VAR_europe_docker_username=$TF_VAR_docker_username
  export TF_VAR_europe_docker_password=$TF_VAR_docker_password
fi

if [[ -z "${TF_VAR_azure_application_id}" ]]
then
  echo "You must set the TF_VAR_azure_application_id environment variable to the Azure application ID."
  exit 1
fi

if [[ -z "${TF_VAR_azure_subscription_id}" ]]
then
  echo "You must set the TF_VAR_azure_subscription_id environment variable to the Azure subscription ID."
  exit 1
fi

if [[ -z "${TF_VAR_azure_password}" ]]
then
  echo "You must set the TF_VAR_azure_password environment variable to the Azure password."
  exit 1
fi

if [[ -z "${TF_VAR_azure_tenant_id}" ]]
then
  echo "You must set the TF_VAR_azure_tenant_id environment variable to the Azure tenant ID."
  exit 1
fi

# It is possible to have unique values per tenant, but most demos will simply reuse the main credentials
if [[ -z "${TF_VAR_america_azure_application_id}" ]]
then
  export TF_VAR_america_azure_application_id=$TF_VAR_america_azure_application_id
  export TF_VAR_america_azure_subscription_id=TF_VAR_azure_subscription_id
  export TF_VAR_america_azure_password=TF_VAR_azure_password
  export TF_VAR_america_azure_tenant_id=TF_VAR_azure_tenant_id
fi

if [[ -z "${TF_VAR_europe_azure_application_id}" ]]
then
  export TF_VAR_europe_azure_application_id=$TF_VAR_europe_azure_application_id
  export TF_VAR_europe_azure_subscription_id=TF_VAR_azure_subscription_id
  export TF_VAR_europe_azure_password=TF_VAR_azure_password
  export TF_VAR_europe_azure_tenant_id=TF_VAR_azure_tenant_id
fi

# Start the Docker Compose stack
pushd docker
docker-compose pull
docker-compose up -d
popd

# Create a new cluster with a custom configuration that binds to all network addresses
if [[ ! -f /tmp/octoconfig.yml ]]
then
  minikube delete
fi

export KUBECONFIG=/tmp/octoconfig.yml

minikube start --container-runtime=containerd --driver=docker

docker network connect minikube octopus

# Extract the cluster URL. This will be a 127.0.0.1 address though, which is not quite what we need.
CLUSTER_URL=$(docker run --rm -v /tmp:/workdir mikefarah/yq '.clusters[0].cluster.server' octoconfig.yml)

# This returns the IP address of the minikube network
DOCKER_HOST_IP=$(minikube ip)

# This is the internal port exposed by minikube
CLUSTER_PORT="8443"

# Extract the client certificate data
CLIENT_CERTIFICATE=$(docker run --rm -v /tmp:/workdir mikefarah/yq '.users[0].user.client-certificate' octoconfig.yml)
CLIENT_KEY=$(docker run --rm -v /tmp:/workdir mikefarah/yq '.users[0].user.client-key' octoconfig.yml)

# Create a self contained PFX certificate
openssl pkcs12 -export -name 'test.com' -password 'pass:Password01!' -out /tmp/kind.pfx -inkey "${CLIENT_KEY}" -in "${CLIENT_CERTIFICATE}"

# Base64 encode the PFX file
COMBINED_CERT=$(cat /tmp/kind.pfx | base64 -w0)
if [[ $? -ne 0 ]]; then
  # Assume we are on a mac, which doesn't have -w
  COMBINED_CERT=$(cat /tmp/kind.pfx | base64)
fi

# Set the initial Gitea user
EXISTING=$(docker exec -it gitea su git bash -c "gitea admin user list")
USER='octopus'
if [[ "$EXISTING" == *"$USER"* ]]; then
  echo "User exists"
else
  echo "We expect to see errors here and so will retry until Gitea is started."
  max_retry=6
  counter=0
  until docker exec -it gitea su git bash -c "gitea admin user create --admin --username octopus --password Password01! --email me@example.com"
  do
     sleep 10
     [[ counter -eq $max_retry ]] && echo "Failed!" && exit 1
     echo "Trying again. Try #$counter"
     ((counter++))
  done
fi

# Create the orgs.
curl \
  --output /dev/null \
  --silent \
  -u "octopus:Password01!" \
  -X POST \
  "http://localhost:3000/api/v1/admin/users/octopus/orgs" \
  -H "Content-Type: application/json" \
  -H "accept: application/json" \
  --data '{"username": "octopuscac"}'

# Create the repos and populate with an initial commit.
for repo in europe_product_service europe_frontend america_product_service america_frontend hello_world_cac azure_web_app_cac k8s_microservice_template
do
  # Create the repo
  curl \
    --output /dev/null \
    --silent \
    -u "octopus:Password01!" \
    -X POST \
    "http://localhost:3000/api/v1/org/octopuscac/repos" \
    -H "content-type: application/json" \
    -H "accept: application/json" \
    --data "{\"name\":\"${repo}\"}"

  # Add the first commit to initialize the repo.
  curl \
    --output /dev/null \
    --silent \
    -u "octopus:Password01!" \
    -X POST "http://localhost:3000/api/v1/repos/octopuscac/${repo}/contents/README.md" \
    -H "accept: application/json" \
    -H "Content-Type: application/json" \
    -d "{ \"author\": { \"email\": \"user@example.com\", \"name\": \"Octopus\" }, \"branch\": \"main\", \"committer\": { \"email\": \"user@example.com\", \"name\": \"string\" }, \"content\": \"UkVBRE1FCg==\", \"dates\": { \"author\": \"2020-04-06T01:37:35.137Z\", \"committer\": \"2020-04-06T01:37:35.137Z\" }, \"message\": \"Initializing repo\"}"
done

# Install all the tools we'll need to perform deployments
docker-compose -f docker/compose.yml exec octopus sh -c 'apt-get install -y jq git dnsutils zip gnupg software-properties-common'
docker-compose -f docker/compose.yml exec octopus sh -c 'apt update && apt install -y --no-install-recommends gnupg curl ca-certificates apt-transport-https && curl -sSfL https://apt.octopus.com/public.key | apt-key add - && sh -c "echo deb https://apt.octopus.com/ stable main > /etc/apt/sources.list.d/octopus.com.list" && apt update && apt install -y octopuscli'
docker-compose -f docker/compose.yml exec octopus sh -c 'wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor > /usr/share/keyrings/hashicorp-archive-keyring.gpg'
docker-compose -f docker/compose.yml exec octopus sh -c 'echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" > /etc/apt/sources.list.d/hashicorp.list'
docker-compose -f docker/compose.yml exec octopus sh -c 'apt update && apt-get install -y terraform'
docker-compose -f docker/compose.yml exec octopus sh -c 'curl -sL https://aka.ms/InstallAzureCLIDeb | bash'
docker-compose -f docker/compose.yml exec octopus sh -c 'if [ ! -f /usr/local/bin/kubectl ]; then curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"; install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl; fi'

# Wait for the Octopus server.
echo "Waiting for the Octopus server"
until $(curl --output /dev/null --silent --fail http://localhost:18080/api)
do
    printf '.'
    sleep 5
done

echo ""

execute_terraform () {
   PG_DATABASE="${1}"
   TF_MODULE_PATH="${2}"
   WORKSPACE="${3}"

   docker-compose -f docker/compose.yml exec terraformdb sh -c "/usr/bin/psql -v ON_ERROR_STOP=1 --username \"\$POSTGRES_USER\" -c \"CREATE DATABASE $PG_DATABASE\""
   pushd "${TF_MODULE_PATH}" || exit 1
   terraform init -reconfigure -upgrade
   terraform workspace new "${WORKSPACE}"
   terraform workspace select "${WORKSPACE}"
   terraform apply -auto-approve -var=octopus_space_id=Spaces-1 || exit 1
   popd || exit 1
}

execute_terraform_with_project () {
   PG_DATABASE="${1}"
   TF_MODULE_PATH="${2}"
   WORKSPACE="${3}"
   PROJECT="${4}"

   docker-compose -f docker/compose.yml exec terraformdb sh -c "/usr/bin/psql -v ON_ERROR_STOP=1 --username \"\$POSTGRES_USER\" -c \"CREATE DATABASE $PG_DATABASE\""
   pushd "${TF_MODULE_PATH}" || exit 1
   terraform init -reconfigure -upgrade
   terraform workspace new "${WORKSPACE}"
   terraform workspace select "${WORKSPACE}"
   terraform apply -auto-approve -var=octopus_space_id=Spaces-1 "-var=project_name=${PROJECT}" || exit 1
   popd || exit 1
}

execute_terraform 'gitcreds' 'shared/gitcreds/gitea/pgbackend' 'Spaces-1'

execute_terraform 'environments' 'shared/environments/dev_test_prod/pgbackend' 'Spaces-1'

execute_terraform 'sync_environment' 'shared/environments/sync/pgbackend' 'Spaces-1'

execute_terraform 'mavenfeed' 'shared/feeds/maven/pgbackend' 'Spaces-1'

execute_terraform 'dockerhubfeed' 'shared/feeds/dockerhub/pgbackend' 'Spaces-1'

execute_terraform 'project_group_hello_world' 'shared/project_group/hello_world/pgbackend' 'Spaces-1'

execute_terraform 'project_group_azure' 'shared/project_group/azure/pgbackend' 'Spaces-1'

execute_terraform 'project_group_k8s' 'shared/project_group/k8s/pgbackend' 'Spaces-1'

execute_terraform 'lib_var_this_instance' 'shared/variables/this_instance/pgbackend' 'Spaces-1'

execute_terraform 'project_group_client_space' 'management_instance/project_group/client_space/pgbackend' 'Spaces-1'

execute_terraform 'management_tenant_tags' 'management_instance/tenant_tags/regional/pgbackend' 'Spaces-1'

execute_terraform 'account_azure' 'shared/accounts/azure/pgbackend' 'Spaces-1'

execute_terraform 'lib_var_octopus_server' 'shared/variables/octopus_server/pgbackend' 'Spaces-1'

execute_terraform 'lib_var_azure' 'shared/variables/azure/pgbackend' 'Spaces-1'

execute_terraform 'lib_var_docker' 'shared/variables/docker/pgbackend' 'Spaces-1'

execute_terraform 'lib_var_k8s' 'shared/variables/k8s/pgbackend' 'Spaces-1'

execute_terraform 'project_create_client_space' 'management_instance/projects/create_client_space/pgbackend' 'Spaces-1'

execute_terraform 'project_hello_world' 'management_instance/projects/hello_world/pgbackend' 'Spaces-1'

execute_terraform 'project_hello_world_cac' 'management_instance/projects/hello_world_cac/pgbackend' 'Spaces-1'

execute_terraform 'project_azure_web_app_cac' 'management_instance/projects/azure_web_app_cac/pgbackend' 'Spaces-1'

execute_terraform 'project_k8s_microservice' 'management_instance/projects/k8s_microservice/pgbackend' 'Spaces-1'

execute_terraform 'project_azure_space_initialization' 'management_instance/projects/azure_space_initialization/pgbackend' 'Spaces-1'

execute_terraform 'project_k8s_space_initialization' 'management_instance/projects/k8s_space_initialization/pgbackend' 'Spaces-1'

# Setup targets
docker-compose -f docker/compose.yml exec terraformdb sh -c '/usr/bin/psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" -c "CREATE DATABASE target_k8s"'
pushd shared/targets/k8s/pgbackend
terraform init -reconfigure -upgrade
terraform workspace new "Spaces-1"
terraform workspace select "Spaces-1"
terraform apply \
  -auto-approve \
  -var=octopus_space_id=Spaces-1 \
  "-var=k8s_cluster_url=https://${DOCKER_HOST_IP}:${CLUSTER_PORT}" \
  "-var=k8s_client_cert=${COMBINED_CERT}"
popd

# Add the tenants
docker-compose -f docker/compose.yml exec terraformdb sh -c '/usr/bin/psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" -c "CREATE DATABASE management_tenants"'
pushd management_instance/tenants/regional_tenants/pgbackend
terraform init -reconfigure -upgrade
terraform workspace new Spaces-1
terraform workspace select Spaces-1
terraform apply -auto-approve \
  "-var=octopus_space_id=Spaces-1" \
  "-var=america_k8s_cert=${COMBINED_CERT}" \
  "-var=america_k8s_url=https://${DOCKER_HOST_IP}:${CLUSTER_PORT}" \
  "-var=europe_k8s_cert=${COMBINED_CERT}" \
  "-var=europe_k8s_url=https://${DOCKER_HOST_IP}:${CLUSTER_PORT}"
popd

# Add serialize and deploy runbooks to sample projects.
# These runbooks are common across these kinds of projects, but benefit from being able to reference the project they
# are associated with. So they are linked up to each project individually, even though they all come from the same source.
for project in "Hello World" "K8S Microservice Template"
do
  execute_terraform_with_project 'serialize_and_deploy' 'management_instance/runbooks/serialize_and_deploy/pgbackend' "${project//[^[:alnum:]]/_}" "${project}"
  execute_terraform_with_project 'runbooks_list' 'management_instance/runbooks/list/pgbackend' "${project//[^[:alnum:]]/_}" "${project}"
done

# Link up the CaC selection of runbooks. Like above, these runbooks are copied into each CaC project that is to be
# serialized and shared with other spaces.
for project in "Hello World CaC" "Azure Web App CaC"
do
  execute_terraform_with_project 'runbooks_fork' 'management_instance/runbooks/fork/pgbackend' "${project//[^[:alnum:]]/_}" "${project}"
  execute_terraform_with_project 'runbooks_merge' 'management_instance/runbooks/merge/pgbackend' "${project//[^[:alnum:]]/_}" "${project}"
  execute_terraform_with_project 'runbooks_list' 'management_instance/runbooks/list/pgbackend' "${project//[^[:alnum:]]/_}" "${project}"
  execute_terraform_with_project 'runbooks_updates' 'management_instance/runbooks/conflict/pgbackend' "${project//[^[:alnum:]]/_}" "${project}"
done
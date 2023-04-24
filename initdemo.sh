#!/bin/bash

pushd docker
docker-compose up -d
popd

# We expect these first few attempts to fail as Gitae is being setup by Docker
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

# Now go ahead and create the orgs and repos
curl \
  -u "octopus:Password01!" \
  -X POST \
  "http://localhost:3000/api/v1/admin/users/octopus/orgs" \
  -H "Content-Type: application/json" \
  -H "accept: application/json" \
  --data '{"username": "octopuscac"}'

curl \
  -u "octopus:Password01!" \
  -X POST \
  "http://localhost:3000/api/v1/org/octopuscac/repos" \
  -H "content-type: application/json" \
  -H "accept: application/json" \
  --data '{"name":"europe-product-service"}'

curl \
  -u "octopus:Password01!" \
  -X POST \
  "http://localhost:3000/api/v1/org/octopuscac/repos" \
  -H "content-type: application/json" \
  -H "accept: application/json" \
  --data '{"name":"europe-frontend"}'

curl \
  -u "octopus:Password01!" \
  -X POST \
  "http://localhost:3000/api/v1/org/octopuscac/repos" \
  -H "content-type: application/json" \
  -H "accept: application/json" \
  --data '{"name":"america-product-service"}'

curl \
  -u "octopus:Password01!" \
  -X POST \
  "http://localhost:3000/api/v1/org/octopuscac/repos" \
  -H "content-type: application/json" \
  -H "accept: application/json" \
  --data '{"name":"america-frontend"}'

# Wait for the Octopus server
echo "Waiting for the Octopus server"
until $(curl --output /dev/null --silent --fail http://localhost:18080/api)
do
    printf '.'
    sleep 5
done

pushd shared/gitcreds/gitea/pgbackend
terraform init -reconfigure
terraform apply -auto-approve
popd

pushd shared/environments/dev_test_prod/pgbackend
terraform init -reconfigure
terraform apply -auto-approve
popd

pushd shared/feeds/maven/pgbackend
terraform init -reconfigure
terraform apply -auto-approve
popd

pushd shared/feeds/dockerhub/pgbackend
terraform init -reconfigure
terraform apply -auto-approve
popd
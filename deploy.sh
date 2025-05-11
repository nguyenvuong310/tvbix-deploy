#!/bin/bash
set -e

nginx_service_name="webserver"
service_name="frontend"

# Function to reload Nginx
reload_nginx() {
  nginx_id=$(docker ps -f name=$nginx_service_name -q | tail -n1)
  docker exec $nginx_id nginx -s reload
}

# Function to handle failures
handle_failure() {
  echo -e "\nDeployment failed. Routing requests to the old container."
  //reload_nginx
  exit 111
}

deploy() {

  version=$1
  export VERSION=$version

  echo "Start deploy frontend version $version...."
  old_container_id=$(docker ps -f name=$service_name -q | tail -n1)

  echo "Create new container"
  docker compose up -d --no-deps --scale $service_name=2 --no-recreate $service_name

  echo "Health check new container"
  new_container_id=$(docker ps -f name=$service_name -q | head -n1)
  new_container_ip=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $new_container_id)

  curl --silent --include --retry-connrefused --retry 30 --retry-delay 1 --fail http://$new_container_ip:8080 || {
    echo "Deploy failed. Cannot start container."
    docker stop $new_container_id
    docker rm $new_container_id
    docker compose up -d --no-deps --scale $service_name=1 --no-recreate $service_name
    handle_failure  
  }

  echo -e "\nStart routing requests to the new container"
  reload_nginx

  echo "Removing old container $old_container_id"
  docker stop $old_container_id
  docker rm $old_container_id
  echo "Old container removed"

  echo "Setting scale to 1"
  docker compose up -d --no-deps --scale $service_name=1 --no-recreate $service_name

  echo "Final Nginx reload"
  reload_nginx
  echo "Deploy  version $version successfully!!!"

  echo "Cleaning up unused images"
  docker image prune -a -f
}

deploy $1
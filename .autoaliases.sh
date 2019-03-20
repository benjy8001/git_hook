#!/bin/sh

function dotenv () {
  set -a
  [ -f .env ] && source .env
  set +a
}

function composer () {
   dotenv
   if [[ -f docker-compose.yml ]]; then
       docker-compose exec -u foo:bar php composer $@
   fi
}

function console () {
   dotenv
   if [[ -f docker-compose.yml ]]; then
       docker-compose exec -u foo:bar php bin/console $@
   fi
}

function php () {
   dotenv
   if [[ -f docker-compose.yml ]]; then
       docker-compose exec -u foo:bar php php $@
   fi
}

function phpunit () {
   dotenv
   if [[ -f docker-compose.yml ]]; then
       docker-compose exec -u foo:bar php bin/phpunit $@
   fi
}

function yarn () {
   dotenv
   if [[ -f docker-compose.yml ]]; then
       docker-compose exec -u foo:bar node yarn $@
   fi
}

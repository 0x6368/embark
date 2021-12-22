#!/bin/bash
# EMBArk - The firmware security scanning environment
#
# Copyright 2020-2021 Siemens Energy AG
# Copyright 2020-2021 Siemens AG
#
# EMBArk comes with ABSOLUTELY NO WARRANTY.
#
# EMBArk is licensed under MIT
#
# Author(s): Benedikt Kuehne

# Description: Starts the Django-Server(s) on host

GREEN='\033[0;32m'
ORANGE='\033[0;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # no color

export PIPENV_DOTENV_LOCATION=/app/www/.env
export DJANGO_SETTINGS_MODULE=embark.settings.deploy
# export EMBARK_DEBUG=True
export HTTP_PORT=80
export HTTPS_PORT=443

cleaner() {
  fuser -k 80/tcp
  killall -9 -q "*daphne*"
  fuser -k 8001/tcp
  docker container stop embark_db
  docker container stop embark_redis
  docker network rm embark
  docker container prune
  echo "\n$ORANGE""Consider reseting ownership of the project manually, else git wont work correctly""$NC\n"
  exit 1
}
#main
set -a
trap cleaner INT

cd "$(dirname "$0")" || exit 1

if ! [[ $EUID -eq 0 ]] ; then
  echo -e "\\n$RED""Run EMBArk installation script with root permissions!""$NC\\n"
  exit 1
fi

#start venv
source ./.venv/bin/activate || exit 1

# Start container
echo -e "\n$GREEN""$BOLD""Setup mysql and redis docker images""$NC"
docker-compose -f ./docker-compose.yml up -d
DU_RETURN=$?
if [[ $DU_RETURN -eq 0 ]] ; then
  echo -e "$GREEN""$BOLD""Finished setup mysql and redis docker images""$NC"
else
  echo -e "$ORANGE""$BOLD""Failed setup mysql and redis docker images""$NC"
fi

if ! [[ -d /app/www/logs ]]; then
  mkdir /app/www/logs
fi


  mkdir /app/www/conf
fi

# container-logs (2 jobs)
echo -e "\n[""$BLUE JOB""$NC""] Redis logs are copied to ./embark/logs/redis_dev.log" 
docker container logs embark_redis -f &> /app/www/logs/redis.log & 
echo -e "\n[""$BLUE JOB""$NC""] DB logs are copied to ./embark/logs/mysql_dev.log"
docker container logs embark_db -f &> /app/www/logs/mysql.log &

# copy django server
if ! [[ -d /app/www/embark ]]; then
  rm -R /app/www/embark
fi
cp -Ru ./embark/ /app/www/embark/

# config apache
# add all modules we want (mod_ssl mod_auth_basic etc)
# post_max_size increase
{
  echo ' '
} > /app/www/conf/embark.conf

# !DIRECTORY-CHANGE!
cd /app/www/embark/ || exit 1

# db_init
echo -e "\n[""$BLUE JOB""$NC""] Starting migrations - log to embark/logs/migration.log"
pipenv run ./manage.py makemigrations users uploader | tee -a /app/www/logs/migration.log
pipenv run ./manage.py migrate | tee -a /app/www/logs/migration.log


# collect staticfiles and make accesable for server
echo -e "\n[""$BLUE JOB""$NC""] Collecting static files"
pipenv run ./manage.py collectstatic --no-input
chown www-embark /app/www/ -R
chown www-embark /app/emba -R
chmod 770 /app/www/media/ -R

echo -e "\n[""$BLUE JOB""$NC""] Starting runapscheduler"
pipenv run ./manage.py runapscheduler | tee -a /app/www/logs/scheduler.log &
sleep 5

echo -e "\n[""$BLUE JOB""$NC""] Starting Apache"
pipenv run ./manage.py runmodwsgi --port="$HTTP_PORT" --user www-embark --group sudo \
--url-alias /static/ /app/www/static/ --url-alias /uploadedFirmwareImages/ /app/www/media/ \
--allow-localhost --working-directory /app/www/embark/ --server-root /app/www/httpd80/ \
--limit-request-body 104857600 --include-file /app/www/conf/embark.conf &
#--https-only --ssl-ca-certificate-file --ssl-certificate FILE-PATH --https-port "$HTTPS_PORT" &
# --enable-debugger
sleep 5

echo -e "\n[""$BLUE JOB""$NC""] Starting daphne(ASGI) - log to /embark/logs/daphne.log"
pipenv run daphne --access-log /app/www/logs/daphne.log -p 8001 -b '0.0.0.0' --root-path=/app/www/embark embark.asgi:application

wait %1
wait %2
#wait %3

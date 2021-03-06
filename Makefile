.PHONY: prepare test clean help

DB_IMAGE = monitoringartist/zabbix-db-mariadb
DB_USER = db-user
DB_PASS = db-password
DB_CONTAINER = test-db
ZABBIX_CONTAINER = test-zabbix

BUILD ?= uyorum/zabbix

## Print all tasks
help:
	make2help -all

## Execute all tasks
all: prepare test clean

## Pull latest images and launch db
prepare:
	docker pull monitoringartist/zabbix-xxl
	docker pull ${DB_IMAGE}
	docker run -d --name ${DB_CONTAINER} -e "MARIADB_USER=${DB_USER}" -e "MARIADB_PASS=${DB_PASS}" ${DB_IMAGE}
	while true; do if docker logs ${DB_CONTAINER} | grep "ready for connections"; then break; else sleep 1; fi done

## Build and test image
test:
	docker rm -f ${ZABBIX_CONTAINER} || true
	docker build -t ${BUILD} .
	docker run -d --name ${ZABBIX_CONTAINER} -p 80 --link ${DB_CONTAINER}:zabbix.db -e "ZS_DBHost=zabbix.db" -e "ZS_DBUser=${DB_USER}" -e "ZS_DBPassword=${DB_PASS}" ${BUILD}
	while true; do if docker logs ${ZABBIX_CONTAINER} | grep "API call:"; then break; else sleep 1; fi done
	## Check Zabbix Web Interface status
	curl -s -L --head http://127.0.0.1:$$(docker inspect --format='{{ (index (index .NetworkSettings.Ports "80/tcp") 0).HostPort }}' ${ZABBIX_CONTAINER}) | grep "HTTP/1.1 200 OK"
	sleep 3
	## Check if slack alertscript is executable
	docker exec ${ZABBIX_CONTAINER} stat -c '%a' /usr/local/share/zabbix/alertscripts/slack
	test $$(docker exec ${ZABBIX_CONTAINER} stat -c '%a' /usr/local/share/zabbix/alertscripts/slack) -eq 755
	## Check if Slack media is registered
	docker logs ${ZABBIX_CONTAINER} | grep "API response" | grep '"description":"Slack"'

## Clean
clean:
	docker rm -f ${DB_CONTAINER} ${ZABBIX_CONTAINER} || true

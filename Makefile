SHELL := /bin/bash

ENV_FILE = .env
include_env = $(wildcard $(ENV_FILE))
ifneq ($(include_env),)
	include .env
endif

CHECK_FILES = cmdb.json ssl.json
DIR_FILES = ./prod_to_dev/internal_data

# --------------- commandes pour make up ---------------- #

init:
	$(MAKE) data_imported
	$(MAKE) docker_setup
	$(MAKE) elasticsearch
	$(MAKE) data_export
	$(MAKE) nosql_into_sql
	$(MAKE) dashboard
	@touch .env_init

up: .env_init
	docker compose up -d
	@ echo "Dashboard is available at http://localhost:8183"

.env_init:
	$(MAKE) init

data_imported:
	@for file in $(CHECK_FILES); do \
		if [ ! -e $(DIR_FILES)/$$file ]; then \
			echo "Les données de test n'ont pas été importées. Merci de vous référer au point 2 du paragraphe *Exécution* dans le README.md du repo."; \
			exit 1; \
		fi; \
	done

docker_setup:
	@mkdir -p volumes/elastic/data volumes/elastic/logs volumes/dashboard

vm-max_map_count:
	@if [ "$$(uname)" = "Linux" ]; then \
		sudo sysctl -w vm.max_map_count=262144 1>/dev/null && echo "vm.max_map_count changed"; \
	fi

elasticsearch:
	$(MAKE) vm-max_map_count
	docker compose up -d elasticsearch

data_export:
	echo "Waiting for elasticsearch to be ready"; \
	while [ "$$(curl -s -o /dev/null -w '%{http_code}' -u ${ELASTICSEARCH_USER}:${ELASTICSEARCH_PASSWORD} -XGET "localhost:9200/")" != "200" ]; do \
	sleep 5; \
	echo "."; \
	done
	@echo "Mapping of cmdb index" && curl -XPUT "http://localhost:9200/cmdb" -k -u ${ELASTICSEARCH_USER}:${ELASTICSEARCH_PASSWORD} -H "Content-Type: application/json" -d @./prod_to_dev/mapping_cmdb.json
	@echo "\nPull elasticdump image" && docker pull elasticdump/elasticsearch-dump
	@echo "Load cmdb index in elasticsearch" && docker run --net=host --rm -ti -v ./prod_to_dev/internal_data:/tmp elasticdump/elasticsearch-dump \
	--input=/tmp/cmdb.json \
	--output=http://${ELASTICSEARCH_USER}:${ELASTICSEARCH_PASSWORD}@localhost:9200/cmdb \
	--type=data
	@echo "Load ssl index in elasticsearch" && docker run --net=host --rm -ti -v ./prod_to_dev/internal_data:/tmp elasticdump/elasticsearch-dump \
	--input=/tmp/ssl.json \
	--output=http://${ELASTICSEARCH_USER}:${ELASTICSEARCH_PASSWORD}@localhost:9200/ssl \
	--type=data
	@curl -XPUT "http://localhost:9200/_settings" -k -u ${ELASTICSEARCH_USER}:${ELASTICSEARCH_PASSWORD} -H "Content-Type: application/json" -d '{"index.max_result_window": 1000000}'

# TODO : tester
nosql_into_sql:
	@ echo "Load data from elasticsearch into sqlite" && docker exec -it cert_dashboard bash -c "Rscript /srv/cert_dashboard/add_cmdb_data.R"

dashboard:
	docker compose up -d cert_dashboard
	@ echo "Dashboard is available at http://localhost:8183"

# --------------- commandes supplementaires ---------------- #

# pour telecharger donnees depuis la prod
data_copy:
	@echo "\nPull elasticdump image" && docker pull elasticdump/elasticsearch-dump
	@echo "Load cmdb index from elasticsearch" && docker run --rm -ti -v ./prod_to_dev/internal_data:/tmp elasticdump/elasticsearch-dump \
	--input=https://${ELASTICSEARCH_USER}:${ELASTICSEARCH_PASSWORD}@${ELASTICSEARCH_HOST}:${ELASTICSEARCH_PORT}/cmdb \
	--output=/tmp/cmdb.json \
	--type=data
	@echo "Load ssl index in elasticsearch" && docker run --rm -ti -v ./prod_to_dev/internal_data:/tmp elasticdump/elasticsearch-dump \
	--input=https://${ELASTICSEARCH_USER}:${ELASTICSEARCH_PASSWORD}@${ELASTICSEARCH_HOST}:${ELASTICSEARCH_PORT}/ssl \
	--output=/tmp/ssl.json \
	--type=data

# pour debug elasticsearch container
elasticsearch_healthy:
	watch -n 0.5 curl -u ${ELASTICSEARCH_USER}:${ELASTICSEARCH_PASSWORD} -X  GET "localhost:9200/_cluster/health?pretty"

# pour acceder a une instance de kibana
kibana:
# TODO : recuperer le token uniquement si pas deja dans fichier
	$(MAKE) token
	docker compose up -d kibana

# pour connecter kibana a elasticsearch
token:
	echo "Waiting for elasticsearch to be ready"; \
	while [ "$$(curl -s -o /dev/null -w '%{http_code}' -u ${ELASTICSEARCH_USER}:${ELASTICSEARCH_PASSWORD} -XGET "localhost:9200/_security/_authenticate")" != "200" ]; do \
	sleep 5; \
	echo "..."; \
	done
	echo -e -n "ELASTICSEARCH_TOKEN=" >> .env && \
	curl -X POST -u ${ELASTICSEARCH_USER}:${ELASTICSEARCH_PASSWORD} "localhost:9200/_security/service/elastic/kibana/credential/token/token1?pretty" | jq '.token'.'value' >> .env

# pour reformater les fichiers contenant les donnees de test
reformat_ssl_json:
	chmod +x ./prod_to_dev/reformat_json.bash
	./prod_to_dev/reformat_json.bash
	rm ./prod_to_dev/ssl.json
	rm ./prod_to_dev/temp_ssl.json
	mv ./prod_to_dev/formated_ssl.json ./prod_to_dev/ssl.json

# --------------- commandes de nettoyage ---------------- #

clean:
	docker compose stop
	sed -i '/ELASTICSEARCH_TOKEN/d' .env
	rm -rf ./volumes
	rm -f .env_init

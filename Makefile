# FIXME : verifier que fichier avec variables d'env respecte les regles pour Makefile car sourcé par lui

SHELL := /bin/bash

ENV_FILE = .env
include_env = $(wildcard $(ENV_FILE))
ifneq ($(include_env),)
	include .env
endif

up: setup
	$(MAKE) data_copy
	$(MAKE) dashboard
	@touch .env_started

# FIXME : toujours necessaire ? si oui pourquoi ?
setup:
	@mkdir -p volumes/elastic/data volumes/elastic/logs volumes/shiny volumes/sqlite

# FIXME : version de chargement des donnes avec data.json envoye par email
data_copy: .elasticsearch_started
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
	$(MAKE) nosql_into_sql

# TODO : version pour les deux methodes selon var d'env a tester
data: .elasticsearch_started
# FIXME : mapping necessaire ou non pour cmdb ?
	@echo "Mapping of cmdb index" && curl -XPUT "http://localhost:9200/cmdb" -k -u ${ELASTICSEARCH_USER}:${ELASTICSEARCH_PASSWORD} -H "Content-Type: application/json" -d @./prod_to_dev/mapping_cmdb.json
	@echo "\nPull elasticdump image" && docker pull elasticdump/elasticsearch-dump
	@echo "Load cmdb index in elasticsearch" && docker run --net=host --rm -ti -v ./prod_to_dev/internal_data:/tmp elasticdump/elasticsearch-dump \
	--input=${SOURCE_CMDB} \
	--output=http://${ELASTICSEARCH_USER}:${ELASTICSEARCH_PASSWORD}@localhost:9200/cmdb \
	--type=data
	@echo "Load ssl index in elasticsearch" && docker run --net=host --rm -ti -v ./prod_to_dev/internal_data:/tmp elasticdump/elasticsearch-dump \
	--input=${SOURCE_SSL} \
	--output=http://${ELASTICSEARCH_USER}:${ELASTICSEARCH_PASSWORD}@localhost:9200/ssl \
	--type=data
	@curl -XPUT "http://localhost:9200/_settings" -k -u ${ELASTICSEARCH_USER}:${ELASTICSEARCH_PASSWORD} -H "Content-Type: application/json" -d '{"index.max_result_window": 1000000}'
	$(MAKE) nosql_into_sql

nosql_into_sql:
	cp cmdb_schema.sqlite ./volumes/sqlite/cmdb.sqlite
	@ echo "Install 'here' R package" && R -e "install.packages(\"here\")"
# FIXME : comment voir l'execution du script ?
	@ echo "Load data from elasticsearch into sqlite" && Rscript add_cmdb_data.R

dashboard:
	docker compose up -d cert_dashboard
	docker compose logs -f cert_dashboard
# FIXME : but est de lancer script dans Makefile ou dans docker avec docker compose ?

.elasticsearch_started:
	$(MAKE) elasticsearch
# FIXME : generation du fichier que quand elasticsearch ready (boucle tant que pas fichier ?)
	echo "Waiting for elasticsearch to be ready"; \
	while [ "$$(curl -s -o /dev/null -w '%{http_code}' -u ${ELASTICSEARCH_USER}:${ELASTICSEARCH_PASSWORD} -XGET "localhost:9200/")" != "200" ]; do \
	sleep 5; \
	echo "."; \
	done
	@touch .elasticsearch_started

elasticsearch: vm-max_map_count
	@docker compose up -d elasticsearch
	docker compose logs -f elasticsearch
# FIXME : fichier genere uniquement quand elasticsearch est dispo, pas avant

# FIXME : toujours necessaire (lancement du container de elasticsearch ko sinon chez moi) ?
vm-max_map_count:
	@if [ "$$(uname)" = "Linux" ]; then \
		sudo sysctl -w vm.max_map_count=262144 1>/dev/null && echo "vm.max_map_count changed"; \
	fi

logs:
	docker compose logs -f

# FIXME : utile ou non (plus si bug fixe) ?
elasticsearch_healthy:
	watch -n 0.5 curl -u ${ELASTICSEARCH_USER}:${ELASTICSEARCH_PASSWORD} -X  GET "localhost:9200/_cluster/health?pretty"

kibana: .elasticsearch_started .kibana_token_available
	docker compose up -d kibana
	docker compose logs -f kibana

.kibana_token_available:
	$(MAKE) token
	@touch .kibana_token_available

token:
	echo "Waiting for elasticsearch to be ready"; \
	while [ "$$(curl -s -o /dev/null -w '%{http_code}' -u ${ELASTICSEARCH_USER}:${ELASTICSEARCH_PASSWORD} -XGET "localhost:9200/_security/_authenticate")" != "200" ]; do \
	sleep 5; \
	echo "..."; \
	done
	echo -e -n "ELASTICSEARCH_TOKEN=" >> .env && \
	curl -X POST -u ${ELASTICSEARCH_USER}:${ELASTICSEARCH_PASSWORD} "localhost:9200/_security/service/elastic/kibana/credential/token/token1?pretty" | jq '.token'.'value' >> .env

# FIXME : .env ko si generation du token plusieurs fois...
clean:
	docker compose stop
	sed -i '/ELASTICSEARCH_TOKEN/d' .env
	rm -rf ./volumes
	rm -f .env_started .elasticsearch_started .kibana_token_available

# FIXME : toujours necessaire ?
reformat_ssl_json:
	chmod +x ./prod_to_dev/reformat_json.bash
	./prod_to_dev/reformat_json.bash
	rm ./prod_to_dev/ssl.json
	rm ./prod_to_dev/temp_ssl.json
	mv ./prod_to_dev/formated_ssl.json ./prod_to_dev/ssl.json

# FIXME : besoin de tester le dashboard en dehors du docker pendant dev ?
# OK visualisation du dashboard ici mais pas via lancement dans docker, pourquoi ?
test_dashboard:
	Rscript new_dashboard.R

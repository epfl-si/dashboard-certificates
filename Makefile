SHELL := /bin/bash

ENV_FILE = .env
include_env = $(wildcard $(ENV_FILE))
ifneq ($(include_env),)
	include .env
endif

reformat_ssl_json:
	chmod +x ./prod_to_dev/reformat_json.bash
	./prod_to_dev/reformat_json.bash
	rm ./prod_to_dev/ssl.json
	rm ./prod_to_dev/temp_ssl.json
	mv ./prod_to_dev/formated_ssl.json ./prod_to_dev/ssl.json

# FIXME : toujours necessaire ?
setup:
	@mkdir -p volumes/elastic/data volumes/elastic/logs volumes/shiny volumes/sqlite

# FIXME : toujours necessaire ?
vm-max_map_count:
	@if [ "$$(uname)" = "Linux" ]; then \
		sudo sysctl -w vm.max_map_count=262144 1>/dev/null && echo "vm.max_map_count changed"; \
	fi

secure:
	echo "Waiting for elasticsearch to be ready"; \
	while [ "$$(curl -s -o /dev/null -w '%{http_code}' -u ${ELASTICSEARCH_USER}:${ELASTICSEARCH_PASSWORD} -XGET "localhost:9200/_security/_authenticate")" != "200" ]; do \
	sleep 5; \
	echo "..."; \
	done
	echo -e "ELASTICSEARCH_TOKEN = \c" >> .env && \
	curl -X POST -u ${ELASTICSEARCH_USER}:${ELASTICSEARCH_PASSWORD} "localhost:9200/_security/service/elastic/kibana/credential/token/token1?pretty" | jq '.token'.'value' >> .env

init: setup vm-max_map_count
	docker run -d \
	--name elasticsearch \
	-p 9200:9200 \
	-v ${pwd}/volumes/elastic/data:/usr/share/elasticsearch/data \
	-v ${pwd}/volumes/elastic/logs:/usr/share/elasticsearch/logs \
	-e "discovery.type=single-node" \
	-e "cluster.name=cluster_name" \
	-e "network.host=0.0.0.0" \
	-e "ELASTIC_PASSWORD=${ELASTICSEARCH_PASSWORD}" \
	-e "xpack.security.enabled=true" \
	docker.elastic.co/elasticsearch/elasticsearch:8.13.2
	$(MAKE) secure
	docker rm -f elasticsearch
	docker compose up -d
	touch .env_started

# FIXME : a ameliorer...
elasticsearch_healthy:
	watch -n 0.5 curl -u ${ELASTICSEARCH_USER}:${ELASTICSEARCH_PASSWORD} -X  GET "localhost:9200/_cluster/health?pretty"

.env_started:
	$(MAKE) init

data: .env_started
	@echo "Mapping of cmdb index" && curl -XPUT "http://localhost:9200/cmdb" -k -u ${ELASTICSEARCH_USER}:${ELASTICSEARCH_PASSWORD} -H "Content-Type: application/json" -d @./prod_to_dev/mapping_cmdb.json
	@echo "Pull elasticdump image" && docker pull elasticdump/elasticsearch-dump
	@echo "Load cmdb index in elasticsearch" && docker run --net=host --rm -ti -v ./prod_to_dev/internal_data:/tmp elasticdump/elasticsearch-dump \
	--input=/tmp/cmdb.json \
	--output=http://${ELASTICSEARCH_USER}:${ELASTICSEARCH_PASSWORD}@localhost:9200/cmdb \
	--type=data
	@echo "Load ssl index in elasticsearch" && docker run --net=host --rm -ti -v ./prod_to_dev/internal_data:/tmp elasticdump/elasticsearch-dump \
	--input=/tmp/ssl.json \
	--output=http://${ELASTICSEARCH_USER}:${ELASTICSEARCH_PASSWORD}@localhost:9200/ssl \
	--type=data
	@curl -XPUT "http://localhost:9200/_settings" -k -u ${ELASTICSEARCH_USER}:${ELASTICSEARCH_PASSWORD} -H "Content-Type: application/json" -d '{"index.max_result_window": 1000000}'
	$(MAKE) data_from_elasticsearch_to_sqlite
	touch .data_loaded

# FIXME : installer package ici ?
data_from_elasticsearch_to_sqlite:
	R -e "install.packages(\"here\")"
	docker compose exec cert_dashboard Rscript "/srv/cert_dashboard/R/start_files/add_cmdb_data.R"

.data_loaded:
	$(MAKE) data

up: .data_loaded vm-max_map_count
	@docker compose up -d
	docker compose exec -d cert_dashboard Rscript "/srv/cert_dashboard/R/start_files/dashboard.R"
	$(MAKE) logs

logs:
	docker compose logs -f 

# FIXME : .env ko si plusieurs make up a la suite...
clean:
	docker compose stop
	sed -i '/ELASTICSEARCH_TOKEN/d' .env
	rm -rf ./volumes
	rm .env_started
	rm .data_loaded

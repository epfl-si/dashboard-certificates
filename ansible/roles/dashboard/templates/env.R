source("lib.R")

db_path <- "{{ dashboard_install_path }}/cmdb_temp.sqlite"
host_elasticsearch <- "{{ dashboard_secrets.elastic_db.hostname }}"
port_elasticsearch <- "{{ dashboard_secrets.elastic_db.port }}"
user_elasticsearch <- "{{ dashboard_secrets.elastic_db.username }}"
password_elasticsearch <- "{{ dashboard_secrets.elastic_db.password }}"
transport_schema <- "https"
shiny_host <- "0.0.0.0"

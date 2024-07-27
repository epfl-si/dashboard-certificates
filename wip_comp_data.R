# packages activation
library(here)

here::i_am("lib.R")

source(here("lib.R"))
source(here("env.R"))

library(dplyr)
library(elastic)
library(jsonlite)
library(RSQLite)

# open connection with elasticsearch
con_elasticsearch <- connect(host = host_elasticsearch, user = user_elasticsearch, pwd = password_elasticsearch, port = port_elasticsearch, transport_schema  = "http")
# open connection with sqlite
con_sqlite <- dbConnect(RSQLite::SQLite(), db_path)

# import data from cmdb index
cmdb_data <- fromJSON(Search(con_elasticsearch, index = "cmdb", size = 100000, raw = TRUE))$hits$hits$"_source"
# import data from ssl index
ssl_data <- fromJSON(Search(con_elasticsearch, index = "ssl", size = 100000, raw = TRUE))$hits$hits$"_source" %>% mutate(ipv4 = as.character(ipv4))

# FIXME !!!
# comparaison entre fqdn (cmdb) et hostname (ssl)
fqdn <- cmdb_data[, c("fqdn", "ip")] %>% arrange("fqdn")
hostname <- ssl_data[, c("hostname", "ipv4")] %>% arrange("hostname")
all_in <- fqdn %>% inner_join(hostname, by = c("fqdn" = "hostname", "ip" = "ipv4")) # 479 lignes < ~ 2500 lignes
all_left <- hostname %>% left_join(fqdn, by = c("ipv4" = "ip")) # 2556 lignes (ok) mais besoin de comparer difference entre hostname et fqdn en rajoutant colonne
all_left <- all_left %>% mutate(comp = ifelse(hostname == fqdn, 1, 0)) # qu'est-ce qu'on peut en deduire ?

library(stringr)
fqdn <- cmdb_data[, c("fqdn", "ip")] %>% arrange("fqdn")
hostname <- ssl_data[, c("hostname", "ipv4")] %>% arrange("hostname")
check_join <- fqdn %>% right_join(hostname, by = c("fqdn" = "hostname")) %>% rename(hostname_ssl = fqdn, ip_cmdb = ip, ip_ssl = ipv4)
cmdb_filter_1 <- cmdb_data %>% filter(str_detect(fqdn, "cmp2app")) # aucun resultat mais trouve dans epnet
cmdb_filter_2 <- cmdb_data %>% filter(str_detect(fqdn, "enacit2dir")) # aucun resultat et pas trouve dans epnet

# ssl_data et cmdb_data correspondent a toutes les donnees du dump (comme d'hab)
# musical-wiki.epfl.ch trouve dans epnet
ssl_filtered_fqdn <- ssl_data %>% filter(str_detect(hostname, "musical-wiki")) # present
cmdb_filtered_fqdn <- cmdb_data %>% filter(str_detect(fqdn, "musical-wiki")) # absent
# test avec ip
ssl_filtred_ip <- ssl_data %>% filter(ipv4 == "128.178.209.183") # present (plusieurs dont lui)
cmdb_filtered_ip <- cmdb_data %>% filter(ip == "128.178.209.183") # present mais pas ce serveur

# TODO : traiter wildcard

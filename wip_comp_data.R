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

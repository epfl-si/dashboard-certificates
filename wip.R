# package install
packages <- c("elastic", "RSQLite", "jsonlite", "dplyr")

for (p in packages) {
  if (!require(p, character.only = TRUE)) {
    install.packages(p)
    library(p, character.only = TRUE)
  }
}

# open connection with elasticsearch
con_elasticsearch <- connect(host = "localhost", path = "", user="", pwd = "", port = 9200, transport_schema  = "http")
# open connection with sqlite
con_sqlite <- dbConnect(RSQLite::SQLite(), "./volumes//sqlite/cmdb.sqlite")

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

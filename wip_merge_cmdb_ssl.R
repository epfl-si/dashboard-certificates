# packages activation
library(here)

here::i_am("lib.R")

source(here("lib.R"))
source(here("env.R"))

library(DBI)
library(dplyr)
library(elastic)
library(httr)
library(jsonlite)
library(RSQLite)

# open connection with elasticsearch
con_elasticsearch <- connect(host = host_elasticsearch, user = user_elasticsearch, pwd = password_elasticsearch, port = port_elasticsearch, transport_schema  = "http")

# open connection with sqlite
con_sqlite <- dbConnect(RSQLite::SQLite(), db_path)

# import ssl data from elasticsearch
ssl_data <- fromJSON(Search(con_elasticsearch, index = "ssl", size = 10000, raw = TRUE))$hits$hits$"_source" %>% mutate(ipv4 = as.character(ipv4))

# request to determine certificates depending on a sciper -> sciper dans Personne puis lier a Serveur_Personne pour recuperer fqdn et finalement obtenir details avec index ssl dans elasticsearch
sciper_from <- dbGetQuery(con_sqlite, "SELECT <sciper> FROM Personne;") %>% distinct()
query_fqdn <- sprintf("SELECT fqdn FROM Serveur_Personne WHERE sciper = %s;", sciper_from)
fqdn_to <- distinct(dbGetQuery(con_sqlite, query_fqdn))
colnames(fqdn_to) <- c("hostname")
ssl_details <- right_join(ssl_data, fqdn_to, by = "hostname")

# request to determine scipers depending on certificate -> hostname dans index ssl sur elasticsearch puis lier a Serveur_Personne pour recuperer sciper et finalement obtenir details avec Personne
hostname_from <- data.frame(fromJSON(Search(con_elasticsearch, index = "ssl", size = 10000, raw = TRUE))$hits$hits$"_source"$"hostname", stringsAsFactors = FALSE)
query_sciper <- sprintf("SELECT sciper FROM Serveur_Personne WHERE fqdn = %s;", hostname_from)
sciper_to <- dbGetQuery(con_sqlite, "SELECT sciper FROM Serveur_Personne WHERE fqdn = \"<fqdn>\";") %>% mutate(sciper = as.integer(sciper)) %>% distinct()
list_scipers <- paste(sciper_to$sciper, collapse = ", ")
query_personne <- sprintf("SELECT * FROM Personne WHERE sciper IN (%s);", list_scipers)
personne_details <- dbGetQuery(con_sqlite, query_personne)

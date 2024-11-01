# packages activation
library(here)

here::i_am("lib.R")

source(here::here("lib.R"))
source(here::here("env.R"))

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

# request to determine certificates depending on a sciper -> sciper dans User puis lier a Server_User sur id_user pour recuperer id_ip et finalement lier a Server pour recuperer ip. Parcourir ssl avec liste des ips pour obtenir details sur certificats
users_from <- dbGetQuery(con_sqlite, "SELECT id_user, sciper FROM User;")
one_user <- users_from[1,] # tableau avec un id_user et un sciper
ips_from <- dbGetQuery(con_sqlite, sprintf("SELECT Server.id_ip, Server.ip FROM Server_User LEFT JOIN Server ON Server_User.id_ip = Server.id_ip WHERE Server_User.id_user = %d;", one_user$id_user))
infos_cert_to <- ssl_data %>% filter(ipv4 %in% ips_from$ip)

# request to determine scipers depending on certificate -> hostname et ip dans ssl puis lier a Server sur ip et lier a Server_User sur id_ip et finalement recuperer infos utilisateurs dans User sur id_user
hostname_from <- ssl_data %>% select(hostname, ipv4)
one_hostname <- hostname_from[1,] # tableau avec un hostname et une ip
id_user_from <- dbGetQuery(con_sqlite, sprintf("SELECT Server.id_ip, ip, id_user, rifs_flag, adminit_flag FROM Server LEFT JOIN Server_User ON Server.id_ip = Server_User.id_ip WHERE Server.ip = '%s';", one_hostname$ipv4))
infos_user_to <- dbGetQuery(con_sqlite, sprintf("SELECT * FROM User WHERE id_user IN (%s);", paste(id_user_from$id_user, collapse = ",")))

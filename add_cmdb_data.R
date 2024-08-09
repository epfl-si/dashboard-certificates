library(here)
here::i_am("lib.R")
source(here("lib.R"))
source(here("env.R"))

library(elastic)
library(RSQLite)
library(jsonlite)
library(dplyr)
library(stringr)

# open connection with elasticsearch
con_elasticsearch <- connect(host = host_elasticsearch, user=user_elasticsearch, pwd = password_elasticsearch, port = port_elasticsearch, transport_schema  = "http")
# open connection with sqlite
con_sqlite <- dbConnect(RSQLite::SQLite(), db_path)

# import data from cmdb index
cmdb_data <- fromJSON(Search(con_elasticsearch, index = "cmdb", size = 100000, raw = TRUE))$hits$hits$"_source"
# import data from ssl index
ssl_data <- fromJSON(Search(con_elasticsearch, index = "ssl", size = 10000, raw = TRUE))$hits$hits$"_source" %>% mutate(ipv4 = as.character(ipv4))

# modify cmdb data
# delete useless columns
cmdb_data_clean <- cmdb_data %>% select(ip, unit)
# take only ips also in ssl
cmdb_data_filtred <- cmdb_data_clean %>% filter(ip %in% ssl_data$ipv4) # 656

# TODO : ajouter ips absentes dans cmdb plus tard car sinon table Server_user KO puisqu'aucun sciper lie...
# add ips only in ssl
#ip_ssl <- ssl_data %>% select(ipv4) %>% unique() # 671
#ip_not_cmdb <- ip_ssl %>% filter(ipv4 %ni% cmdb_data_filtred$ip) # 15
#for (i in ip_not_cmdb) {
#  cmdb_data_filtred <- rbind(cmdb_data_filtred, data.frame(ip = i, unit = NA)) # 671
#}

# TODO : pour l'instant, ne pas prendre en compte les ips quand ssl$subject$CN contient "*" car responsables ne sont pas les memes -> plus tard ajouter en dur responsables pour chaque white card
# liste des white cards : "ssl_whitecard <- (ssl_data %>% filter(str_detect(subject$CN, "\\*")))$subject %>% select(CN) %>% unique()"

# delete ips if white cards
ips_whitecard <- ssl_data %>% filter(str_detect(subject$CN, "\\*")) %>% select(ipv4) %>% unique()
cmdb_data_filtred <- cmdb_data_filtred %>% filter(ip %ni% ips_whitecard$ipv4)

# insert cmdb data filtred into SQLite scheme
# TODO (plus tard) : ajouter aussi donnees de ssl

# Server table
for (i in 1:nrow(cmdb_data_filtred)) {
  insert_query <- sprintf("INSERT INTO Server (id_ip, ip) VALUES (NULL, '%s')", cmdb_data_filtred$ip[i])
  dbExecute(con_sqlite, insert_query)
}

# User table
rifs <- cmdb_data_filtred$unit$rifs
adminit <- cmdb_data_filtred$unit$adminit
rifs_df <- distinct(do.call(rbind, rifs))
adminit_df <- distinct(do.call(rbind, adminit))
mix_rifs_adminit <- distinct(rbind(rifs_df, adminit_df))
for (i in 1:nrow(mix_rifs_adminit)) {
    sciper <- as.integer(mix_rifs_adminit$sciper[i])
    cn <- mix_rifs_adminit$cn[i]
    email <- mix_rifs_adminit$mail[i]
    insert_query <- sprintf("INSERT INTO User (sciper, cn, email) VALUES ('%d', '%s', '%s')", sciper, cn, email)
    dbExecute(con_sqlite, insert_query)
}

# Server_User table
ips_key <- dbGetQuery(con_sqlite, "SELECT * FROM Server") %>% select(id_ip, ip)
server_user <- data.frame(id_ip = numeric(), sciper = numeric(), rifs_flag = numeric(), adminit_flag = numeric(), stringsAsFactors = FALSE)
for(i in 1:nrow(cmdb_data_filtred)) {
  id <- which(ips_key$ip == cmdb_data_filtred$ip[i])
  rifs <- data.frame(cmdb_data_filtred$unit$rifs[[i]], stringsAsFactors = FALSE)
  if (nrow(rifs) > 0) {
    for (j in 1:nrow(rifs)) {
      new_row <- data.frame(id_ip = id, sciper = rifs$sciper[j], rifs_flag = 1, adminit_flag = 0, stringsAsFactors = FALSE)
      server_user <- rbind(server_user, new_row)
    }
  }
  adminit <- data.frame(cmdb_data_filtred$unit$adminit[[i]], stringsAsFactors = FALSE)
  if (nrow(adminit) > 0) {
    for (k in 1:nrow(adminit)) {
      if (adminit$sciper[k] %in% server_user$sciper) {
        server_user[server_user$sciper == adminit$sciper[k], "adminit_flag"] <- 1
      } else {
        new_row <- data.frame(id_ip = id, sciper = adminit$sciper[k], rifs_flag = 0, adminit_flag = 1, stringsAsFactors = FALSE)
        server_user <- rbind(server_user, new_row)
      }
    }
  }
}

server_user_clean <- server_user %>% distinct()
for (d in 1:nrow(server_user_clean)) {
  id_ip <- server_user_clean$id_ip[d]
  sciper <- server_user_clean$sciper[d]
  rifs <- server_user_clean$rifs_flag[d]
  adminit <- server_user_clean$adminit_flag[d]
  insert_query <- sprintf("INSERT INTO Server_User (id_server_user, id_ip, sciper, rifs_flag, adminit_flag) VALUES (NULL, '%d', '%d','%d', '%d')", id_ip, sciper, rifs, adminit)
  dbExecute(con_sqlite, insert_query)
}

# close connection with sqlite
dbDisconnect(con_sqlite)

library(here)
here::i_am("lib.R")
source(here("lib.R"))
source(here("env.R"))

library(elastic)
library(RSQLite)
library(jsonlite)
library(dplyr)

# open connection with elasticsearch
con_elasticsearch <- connect(host = host_elasticsearch, user=user_elasticsearch, pwd = password_elasticsearch, port = port_elasticsearch, transport_schema  = "http")
# open connection with sqlite
con_sqlite <- dbConnect(RSQLite::SQLite(), db_path)

# import data from cmdb index
cmdb_data <- fromJSON(Search(con_elasticsearch, index = "cmdb", size = 100000, raw = TRUE))$hits$hits$"_source"

# import data from ssl index
ssl_data <- fromJSON(Search(con_elasticsearch, index = "ssl", size = 10000, raw = TRUE))$hits$hits$"_source" %>% mutate(ipv4 = as.character(ipv4))

# FIXME !!!
# but est de filtrer l'index cmdb pour ensuite alimenter les tables dans sqlite (avant filtre sur ip mais certificat rattache a fqdn/hostname et pas a ip)
# semi pour ne garder que colonnes de cmdb et que lignes similaires entre cmdb et ssl sur fqdn = hostname
cmdb_data_filtred_semi <- semi_join(cmdb_data, ssl_data, by = c("fqdn" = "hostname")) # pourquoi uniquement 557 lignes ?
# tentative de filtrer avec right
cmdb_data_filtred_right <- right_join(cmdb_data, ssl_data, by = c("fqdn" = "hostname")) # centaine de lignes en trop (2628) car doublons
# recherche des doublons
doublons_ssl <- ssl_data$hostname %>% unique() # pas de doublon dans ssl
doubons_cmdb <- cmdb_data$fqdn %>% unique() # doublons dans cmdb -> 88209 a 87557
cmdb_data_unique <- cmdb_data %>% distinct() # toujours 88209 donc pas vraiment des doublons ?
# trouver 652 doublons de fqdn dans cmdb
fqdn_nb_doublons <- cmdb_data %>% group_by(fqdn) %>% tally() %>% filter(n > 1) # 638 doublons et pas 652...
fqdn_doublons <- fqdn_nb_doublons %>% ungroup() %>% select(fqdn) # liste des doublons
# pourquoi pas le meme nombre de doublons ?
cmdb_data_filtred <- cmdb_data_filtred_semi

# import data into database

# Serveur table
for (i in 1:nrow(cmdb_data_filtred)) {
    ip_adr <- cmdb_data_filtred$ip[i]
    fqdn <- cmdb_data_filtred$fqdn[i]
    insert_query <- sprintf("INSERT INTO Serveur (id_ip_adr, fqdn, ip) VALUES (NULL, '%s', '%s')", fqdn, ip_adr)
    dbExecute(con_sqlite, insert_query)
}

# Personne table
rifs <- cmdb_data_filtred$unit$rifs
adminit <- cmdb_data_filtred$unit$adminit
rifs_df <- distinct(do.call(rbind, rifs))
adminit_df <- distinct(do.call(rbind, adminit))
mix_rifs_adminit <- distinct(rbind(rifs_df, adminit_df))
for (i in 1:nrow(mix_rifs_adminit)) {
    sciper <- mix_rifs_adminit$sciper[i]
    cn <- mix_rifs_adminit$cn[i]
    email <- mix_rifs_adminit$mail[i]
    insert_pers_query <- sprintf("INSERT INTO Personne (sciper, cn, email) VALUES ('%s', '%s', '%s')", sciper, cn, email)
    dbExecute(con_sqlite, insert_pers_query)
}

# Serveur_Personne table -> old
#for (i in 1:nrow(cmdb_data_filtred)) {
#    fqdn <- cmdb_data_filtred$fqdn[i]
#    for (j in 1:nrow(mix_rifs_adminit)) {
#        sciper <- mix_rifs_adminit$sciper[j]
#        insert_serv_pers_query <- sprintf("INSERT INTO Serveur_Personne (id_serv_pers, fqdn, sciper) VALUES (NULL, '%s', '%s')", fqdn, sciper)
#        dbExecute(con_sqlite, insert_serv_pers_query)
#    }
#}

# Serveur_Personne table -> new

# FIXME : pourquoi doublons lors de creation de serveur_personne (1276 lignes et 1097 sans doublons) ?
serveur_personne <- data.frame(fqdn = character(), sciper = numeric(), rifs_flag = numeric(), adminit_flag = numeric(), stringsAsFactors = FALSE)
for(i in 1:nrow(cmdb_data_filtred)) {
  fqdn <- cmdb_data_filtred$fqdn[i]
  rifs <- data.frame(cmdb_data_filtred$unit$rifs[[i]], stringsAsFactors = FALSE)
  if (nrow(rifs) > 0) {
    for (j in 1:nrow(rifs)) {
      new_row <- data.frame(fqdn = fqdn, sciper = rifs$sciper[j], rifs_flag = 1, adminit_flag = 0, stringsAsFactors = FALSE)
      serveur_personne <- rbind(serveur_personne, new_row)
    }
  }
  adminit <- data.frame(cmdb_data_filtred$unit$adminit[[i]], stringsAsFactors = FALSE)
  if (nrow(adminit) > 0) {
    for (k in 1:nrow(adminit)) {
      if (adminit$sciper[k] %in% serveur_personne$sciper) {
        serveur_personne[serveur_personne$sciper == adminit$sciper[k], "adminit_flag"] <- 1
      } else {
        new_row <- data.frame(fqdn = fqdn, sciper = adminit$sciper[k], rifs_flag = 0, adminit_flag = 1, stringsAsFactors = FALSE)
        serveur_personne <- rbind(serveur_personne, new_row)
      }
    }
  }
}
serveur_personne_clean <- serveur_personne %>% distinct()
for (d in 1:nrow(serveur_personne_clean)) {
  fqdn <- serveur_personne_clean$fqdn[d]
  sciper <- serveur_personne_clean$sciper[d]
  rifs <- serveur_personne_clean$rifs_flag[d]
  adminit <- serveur_personne_clean$adminit_flag[d]
  insert_serv_pers_query <- sprintf("INSERT INTO Serveur_Personne (id_serv_pers, fqdn, sciper, rifs_flag, adminit_flag) VALUES (NULL, '%s', '%s','%s', '%s')", fqdn, sciper, rifs, adminit)
  dbExecute(con_sqlite, insert_serv_pers_query)
}

# close connection with sqlite
dbDisconnect(con_sqlite)

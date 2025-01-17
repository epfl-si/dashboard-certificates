library(here)
here::i_am("lib.R")
source(here::here("lib.R"))
source(here::here("env.R"))
source(here::here("clean_data.R"))
source(here::here("create_schema.R"))

library(RSQLite)
library(jsonlite)
library(dplyr)
library(stringr)

# open connection with sqlite
con_sqlite <- dbConnect(RSQLite::SQLite(), db_path)

# delete useless columns
cmdb_data_clean <- cmdb_data %>% select(ip, unit)

# insert cmdb data into SQLite scheme

# Server table
for (i in 1:nrow(cmdb_data_clean)) {
  insert_query <- sprintf("INSERT INTO Server (id_ip, ip) VALUES (NULL, '%s')", cmdb_data_clean$ip[i])
  dbExecute(con_sqlite, insert_query)
}

# User table
rifs <- cmdb_data_clean$unit$rifs
adminit <- cmdb_data_clean$unit$adminit
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
users_key <- dbGetQuery(con_sqlite, "SELECT * FROM User") %>% select(id_user, sciper)
server_user <- data.frame(id_ip = numeric(), id_user = numeric(), rifs_flag = numeric(), adminit_flag = numeric(), stringsAsFactors = FALSE)
for(i in 1:nrow(cmdb_data_clean)) {
  id_ser <- ips_key %>% filter(ip == cmdb_data_clean$ip[i]) %>% select(id_ip)
  rifs <- data.frame(cmdb_data_clean$unit$rifs[[i]], stringsAsFactors = FALSE)
  if (nrow(rifs) > 0) {
    for (j in 1:nrow(rifs)) {
      id_us <- users_key %>% filter(sciper == rifs$sciper[j]) %>% select(id_user)
      new_row <- data.frame(id_ip = id_ser, id_user = id_us, rifs_flag = 1, adminit_flag = 0, stringsAsFactors = FALSE)
      server_user <- rbind(server_user, new_row)
    }
  }
  adminit <- data.frame(cmdb_data_clean$unit$adminit[[i]], stringsAsFactors = FALSE)
  if (nrow(adminit) > 0) {
    for (k in 1:nrow(adminit)) {
      id_us <- users_key %>% filter(sciper == adminit$sciper[k]) %>% select(id_user)
      if (id_us %in% server_user$id_user) {
        server_user[server_user$id_user == id_us, "adminit_flag"] <- 1
      } else {
        new_row <- data.frame(id_ip = id_ser, id_user = id_us, rifs_flag = 0, adminit_flag = 1, stringsAsFactors = FALSE)
        server_user <- rbind(server_user, new_row)
      }
    }
  }
}

for (d in 1:nrow(server_user)) {
  id_ip <- server_user$id_ip[d]
  id_user <- server_user$id_user[d]
  rifs <- server_user$rifs_flag[d]
  adminit <- server_user$adminit_flag[d]
  insert_query <- sprintf("INSERT INTO Server_User (id_server_user, id_ip, id_user, rifs_flag, adminit_flag) VALUES (NULL, '%d', '%d','%d', '%d')", id_ip, id_user, rifs, adminit)
  dbExecute(con_sqlite, insert_query)
}

# close connection with sqlite
dbDisconnect(con_sqlite)

library(here)
here::i_am("lib.R")
source(here("lib.R"))
source(here("env.R"))

library(shiny)
library(DT)
library(elastic)
library(RSQLite)
library(dplyr)
library(jsonlite)
library(roperators)

options(shiny.host = "0.0.0.0")
options(shiny.port = 8180)

# open connection with elasticsearch
con_elasticsearch <- connect(host = host_elasticsearch, user = user_elasticsearch, pwd = password_elasticsearch, port = port_elasticsearch, transport_schema  = "http")
# open connection with sqlite
con_sqlite <- dbConnect(RSQLite::SQLite(), db_path)

# import ssl data from elasticsearch
ssl_data <- fromJSON(Search(con_elasticsearch, index = "ssl", size = 10000, raw = TRUE))$hits$hits$"_source" %>% mutate(ipv4 = as.character(ipv4)) %>% mutate(validFrom = as.Date(validFrom), validTo = as.Date(validTo))
# import cmdb data from sqlite
cmdb_data_personne <- dbGetQuery(con_sqlite, "SELECT * FROM Personne")
cmdb_data_serveur <- dbGetQuery(con_sqlite, "SELECT * FROM Serveur")
cmdb_data_serveur_personne <- dbGetQuery(con_sqlite, "SELECT * FROM Serveur_Personne")

# FIXME : creation de la table (choix infos ok ou ko ?) a faire ici ou ailleurs ?
# tableau avec fqdn, ip, rifs, date_debut, date_fin
rifs <- ssl_data %>% select(hostname) %>% left_join(cmdb_data_serveur_personne %>% dplyr::filter(rifs_flag == 1) %>% select(fqdn, sciper), by = c("hostname" = "fqdn"))
prenom_nom_rifs <- cmdb_data_personne %>% select(sciper, cn) %>% right_join(rifs, by = "sciper") %>% select(sciper, cn, hostname)
tableau <- ssl_data %>% select(hostname, ipv4, validFrom, validTo) %>% mutate(validFrom = format(validFrom, "%d.%m.%Y"), validTo = format(validTo, "%d.%m.%Y"), ip = ipv4) %>% left_join(prenom_nom_rifs %>% select(hostname, cn), by = "hostname") %>% rename(rifs = cn) %>% group_by(hostname, ip, validFrom, validTo) %>% summarise(rifs = list(rifs), .groups = 'drop') %>% relocate(rifs, .before = validFrom)
# details avec adminit, details_ssl
adminit <- ssl_data %>% select(hostname) %>% left_join(cmdb_data_serveur_personne %>% dplyr::filter(adminit_flag == 1) %>% select(fqdn, sciper), by = c("hostname" = "fqdn"))
prenom_nom_adminit <- cmdb_data_personne %>% select(sciper, cn) %>% right_join(adminit, by = "sciper") %>% select(sciper, cn, hostname)
colonnes_exclues <- c("@timestamp", "ipv4", "validFrom", "validTo")
tableau_details <- ssl_data %>% left_join(prenom_nom_adminit %>% select(hostname, cn), by = "hostname") %>% mutate(adminit = cn) %>% group_by(hostname) %>% summarise(adminit = list(adminit)) %>% ungroup() %>% select(hostname, adminit, -any_of(colonnes_exclues))
# FIXME : besoin des donnees de ces sous-tableaux pour afficher en detail ?
subject <- ssl_data$subject
issuer <- ssl_data$issuer
proto <- ssl_data$proto

ui <- fluidPage(
  titlePanel("Certificats SSL"),
  DTOutput("table"),
  DTOutput("details")
)

server <- function(input, output) {
  output$table <- renderDT({
    datatable(tableau, selection = 'single')
  })

  output$details <- renderDT({
    req(input$table_rows_selected)
    selected_row <- input$table_rows_selected
    details <- tableau_details[selected_row, ]
    datatable(details)
  })
}

shinyApp(ui = ui, server = server)


# code pour sciper specifique

# # FIXME : authentification avec tequila renvoie un unique sciper
# scipers <- cmdb_data_personne
# user_sciper <- ...
# 
# # aller dans table serveur_personne pour prendre tous les ips en fonction du sciper
# user_ips <- cmdb_data_serveur_personne %>% filter(sciper == user_sciper) %>% pull(ip_adr) %>% unique()
# # recuperer infos de data_ssl pour certificats -> tout sauf timestamp, subject, issuer et proto
# ssl_infos <- ssl_data %>% filter(ipv4 %in% user_ips) %>% select(-c("@timestamp", "subject", "issuer", "proto")) %>% distinct()
# # recuperer infos de cmdb_data_serveur pour fqdn
# user_fqdns <- cmdb_data_serveur %>% filter(ip %in% user_ips) %>% select(ip, fqdn) %>% distinct()
# # recuperer infos de cmdb_data_personne pour autres responsables -> sciper, cn et email
# autres_resp_sciper <- cmdb_data_serveur_personne %>% filter(ip_adr %in% user_ips) %>% pull(sciper) %>% unique()
# autres_resp_infos <- cmdb_data_personne %>% filter(sciper %in% autres_resp_sciper) %>% select(sciper, cn, email) %>% distinct()
# # mettre en forme table avec colonnes dans bon ordre
# table_1 <- ssl_infos %>% select(validFrom, validTo, ipv4) %>% distinct()
# table_2 <- user_fqdns %>% distinct()
# table_3 <- autres_resp_infos %>% distinct()
# table_4 <- ssl_infos %>% select(-c(ipv4, validFrom, validTo)) %>% distinct()
# merged_table <- merge(table_1, table_2, by.x = "ipv4", by.y = "ip", all.x = TRUE)
# merged_table <- merge(merged_table, table_4, by = "ipv4", all.x = TRUE)
# merged_table <- merge(merged_table, table_3, by = "sciper", all.x = TRUE)
# # supprimer details et n'afficher que essentiel

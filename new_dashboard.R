library(here)
here::i_am("lib.R")
source(here("lib.R"))
source(here("env.R"))

library(shiny)
library(shinydashboard)
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
tableau_details <- ssl_data %>% left_join(prenom_nom_adminit %>% select(hostname, cn), by = "hostname") %>% mutate(adminit = cn)
group_cols <- setdiff(names(tableau_details), colonnes_exclues)
tableau_details <- tableau_details %>% group_by(across(all_of(group_cols))) %>% summarise(adminit = list(adminit), .groups = 'drop') %>% select(hostname, adminit, everything(), -any_of(colonnes_exclues))
# FIXME : besoin des donnees de ces sous-tableaux pour afficher en detail ?
subject <- ssl_data$subject
issuer <- ssl_data$issuer
proto <- ssl_data$proto

# TODO : notifier quand echeance proche
text_notification <- "TODO"

ui <- dashboardPage(skin = "red",
  dashboardHeader(title = "Certificats SSL", dropdownMenuOutput("notifOutput")),
  dashboardSidebar(
    sidebarMenu(
      menuItem("Listing", tabName = "listing", icon = icon("list")),
      menuItem("Détails", tabName = "details", icon = icon("info-circle")),
      menuItem("Vue d'ensemble", tabName = "plots", icon = icon("chart-bar")),
      conditionalPanel(
                  condition = 'input.sidebar == "details"',
                  # FIXME : pas de champ de recherche pour filtrer sur hostname
                  selectInput("hostname", "Choix de l'hostname pour obtenir les détails:", choices = tableau$hostname, selected = tableau$hostname[1])
                )
    )
  ),
  dashboardBody(
    tabItems(
      tabItem(tabName = "listing",
              fluidPage(
                DTOutput("df_all")
              )),
      tabItem(tabName = "details",
              # FIXME: ajouter un champ de recherche pour filtrer sur hostname
              # FIXME: afficher tableau avec details
              fluidPage(
                DTOutput("df_details")
              )),
      tabItem(tabName = "plots"
      # TODO : afficher nombre de certificats avec echeance dans semaine, mois, annee, ... selon histogramme
      )
    )
  )
)

server <- function(input, output) {
  output$notifOutput <- renderMenu({
    notif <- notificationItem(text_notification, icon = icon("warning"))
    dropdownMenu(type = "notifications", notif)
  })

  output$df_all <- renderDT({
    datatable(tableau)
  })

  # FIXME
  output$df_details <- renderDT({
    datatable(tableau_details %>% dplyr::filter(hostname == input$hostname))
  })
}

shinyApp(ui, server)

#header <- dashboardHeader()
#sidebar <- dashboardSidebar()
#body <- dashboardBody()
#dashboardPage(header, sidebar, body)

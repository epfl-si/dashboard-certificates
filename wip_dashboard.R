# TODO : mettre tout sur un onglet
# TODO : changer type d'input pour troisieme onglet
# TODO : ajouter onglet avec diagramme pour visualiser combien de certificats avec echeance dans 1 semaine, 1 mois, 1 annee, ...
# MAYBE : info cert + resp sur meme onglet ou en ouvrant nouvel onglet quand clic sur ligne (https://stackoverflow.com/questions/45151436/shiny-datatable-popup-data-about-selected-row-in-a-new-window)

library(here)
here::i_am("lib.R")
source(here("lib.R"))
source(here("env.R"))

library(shiny)
library(shinydashboard)
library(shiny.fluent)
library(DT)
library(elastic)
library(RSQLite)
library(dplyr)
library(jsonlite)
library(roperators)
library(log4r)

options(shiny.host = "0.0.0.0")
options(shiny.port = 8180)

# open connection with elasticsearch
con_elasticsearch <- connect(host = host_elasticsearch, user = user_elasticsearch, pwd = password_elasticsearch, port = port_elasticsearch, transport_schema  = "http")
# open connection with sqlite
con_sqlite <- dbConnect(RSQLite::SQLite(), db_path)

# import ssl data from elasticsearch
ssl_data <- fromJSON(Search(con_elasticsearch, index = "ssl", size = 10000, raw = TRUE))$hits$hits$"_source" %>% mutate(ipv4 = as.character(ipv4)) %>% mutate(validFrom = as.Date(validFrom), validTo = as.Date(validTo)) %>% rename(ip = ipv4, date_debut = validFrom, date_fin = validTo)

# tableau avec hostname, ip, date_debut, date_fin
# FIXME : comment trier les donnees a la base (pour l'instant sur hostname partout) ?
table <- ssl_data %>% select(hostname, ip, date_debut, date_fin) %>% arrange(hostname)

# tableau avec tout de ssl
# TODO : formater les donnees de ssl et de cmdb pour donner la possibilite d'afficher toutes les colonnes utiles dans premier onglet
table_all <- ssl_data
# FIXME : besoin des donnees de ces sous-tableaux pour afficher les details ?
subject <- ssl_data$subject
issuer <- ssl_data$issuer
proto <- ssl_data$proto
# cmdb$iaas utile ?

# noms des colonnes
column_default <- c("hostname", "ip", "date_debut", "date_fin")
column_choices <- names(table_all)

# FIXME : trouver un moyen pour afficher les dates autrement mais garder le tri dynamique possible

# TODO : notifier quand echeance proche
text_notification <- "TODO"

# necessaire si filtre dans menu sinon erreur
convertMenuItem <- function(mi,tabName) {
  mi$children[[1]]$attribs['data-toggle'] = "tab"
  mi$children[[1]]$attribs['data-value'] = tabName
  mi
}

header <- dashboardHeader(title = "Certificats SSL", dropdownMenuOutput("notifOutput"))

sidebar <- dashboardSidebar(
  sidebarMenu(
    convertMenuItem(menuItem("Vue globale", tabName = "listing", icon = icon("list"), checkboxGroupInput("columns", "Choisissez les colonnes à afficher :", choices = column_choices, selected = column_default)), tabName = "listing"),
    convertMenuItem(menuItem("Echéances", tabName = "date_filter", icon = icon("circle-exclamation"), dateRangeInput("date_fin_plage", label = "Choisir la période comprenant la date d'échéance :", start = Sys.Date(), end = Sys.Date(), separator = " à ", format = "yyyy-mm-dd")), tabName = "date_filter"),
    convertMenuItem(menuItem("Responsables", tabName = "user_filter", icon = icon("info-circle"), textInput("sciper", "Choisir le sciper d'un responsable :", value = ""), textInput("hostname", "Choisir le hostname d'un certificat :", value = "")), tabName = "user_filter")
  )
)

body <- dashboardBody(
  tabItems(
    tabItem(tabName = "listing",
      fluidPage(
        DTOutput("df_all")
      )),
    tabItem(tabName = "date_filter",
      fluidPage(
        DTOutput("df_date")
      )),
    tabItem(tabName = "user_filter",
      fluidPage(
        DTOutput("df_user"),
        # TODO : ajouter ligne et titre uniquement si ligne selectionnee
        hr(style = "border-color: black;"),
        h2("Détails des responsables", style = "text-align: center;"),
        DTOutput("df_resp")
      ))
  )
)

ui <- dashboardPage(skin = "red",
  header,
  sidebar,
  body
)

server <- function(input, output) {
  output$notifOutput <- renderMenu({
    notif <- notificationItem(text_notification, icon = icon("warning"))
    dropdownMenu(type = "notifications", notif)
  })

  output$df_all <- renderDT({
    if (length(input$columns) > 0) {
        selected_columns <- input$columns
        data <- table_all[, selected_columns, drop = FALSE]
        datatable(data, options = list(searching = FALSE), class = 'stripe hover')
    } else {
        datatable(data.frame(Message = "Aucune colonne sélectionnée !"), options = list(searching = FALSE), class = 'stripe hover', rownames = FALSE)
    }
  })

  output$df_date <- renderDT({
    date_fin_min <- input$date_fin_plage[1]
    date_fin_max <- input$date_fin_plage[2]
    info_cert <- table %>% filter(date_fin >= date_fin_min & date_fin <= date_fin_max)
    datatable(info_cert, options = list(searching = FALSE), class = 'stripe hover')
  })

  output$df_user <- renderDT({
    sciper <- input$sciper
    hn <- input$hostname
    if (grepl("^[0-9]*$", sciper)) {
      sciper <- as.integer(sciper)
    } else {
      sciper <- NA
    }
    if (is.na(sciper) && hn == "") {
      info_cert <- table
    } else if (!is.na(sciper) && hn == "") {
      ips <- dbGetQuery(con_sqlite, sprintf("SELECT User.id_user, User.sciper, Server.id_ip, Server.ip FROM User LEFT JOIN Server_User ON User.id_user = Server_User.id_user LEFT JOIN Server ON Server_User.id_ip = Server.id_ip WHERE sciper = %s;", sciper))
      info_cert <- table %>% filter(ip %in% ips$ip)
     } else if (is.na(sciper) && hn != "") {
      info_cert <- table %>% filter(hostname == hn)
     } else {
      ips <- dbGetQuery(con_sqlite, sprintf("SELECT User.id_user, User.sciper, Server.id_ip, Server.ip FROM User LEFT JOIN Server_User ON User.id_user = Server_User.id_user LEFT JOIN Server ON Server_User.id_ip = Server.id_ip WHERE sciper = %s;", sciper))
      info_cert <- table %>% filter(ip %in% ips$ip) %>% filter(hostname == hn)
     }
     # TODO : simplifier ci-dessus
    datatable(info_cert, selection = 'single', options = list(searching = FALSE), class = 'stripe hover')
  })

  output$df_resp <- renderDT({
    # FIXME : trouver un moyen pour ne pas dupliquer le code
    sciper <- input$sciper
    if (grepl("^[0-9]*$", sciper)) {
      sciper <- as.integer(sciper)
    } else {
      sciper <- NA
    }
    if (is.na(sciper)) {
      info_cert <- table
    } else {
      ips <- dbGetQuery(con_sqlite, sprintf("SELECT User.id_user, User.sciper, Server.id_ip, Server.ip FROM User LEFT JOIN Server_User ON User.id_user = Server_User.id_user LEFT JOIN Server ON Server_User.id_ip = Server.id_ip WHERE sciper = %s;", sciper))
      info_cert <- table %>% filter(ip %in% ips$ip)
     }
    
    req(input$df_user_rows_selected) # affichage uniquement si ligne selectionnee
    selected_row <- input$df_user_rows_selected # index de la ligne selectionnee
    ip <- info_cert[selected_row, ]$ip
    info_user <- dbGetQuery(con_sqlite, sprintf("SELECT sciper, cn, email, rifs_flag, adminit_flag FROM Server LEFT JOIN Server_User ON Server.id_ip = Server_User.id_ip LEFT JOIN User ON Server_User.id_user = User.id_user WHERE Server.ip = '%s';", ip))
    info_user <- info_user %>% rename(nom = cn, rifs = rifs_flag, adminit = adminit_flag) %>% mutate(rifs = ifelse(rifs == 1, "x", ""), adminit = ifelse(adminit == 1, "x", ""))
    # TODO : filtrer sur nom de famille ?
    # TODO : changer le style de l'affichage
    datatable(info_user, options = list(searching = FALSE), class = 'stripe hover')
  })
}

shinyApp(ui, server)

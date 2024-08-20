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

# tableau avec hostname, ip, date_debut et date_fin
# FIXME : comment trier les donnees a la base (pour l'instant sur hostname partout) et quelles colonnes afficher a la base ?
ssl_specific <- ssl_data %>% select(hostname, ip, date_debut, date_fin) %>% arrange(hostname)

# tableau avec tout de ssl
# TODO : formater les donnees de ssl et de cmdb pour donner la possibilite d'afficher toutes les colonnes utiles dans premier onglet
ssl_all <- ssl_data
# FIXME : besoin des donnees de ces sous-tableaux pour afficher les details ?
subject <- ssl_data$subject
issuer <- ssl_data$issuer
proto <- ssl_data$proto
# cmdb$iaas utile ?

# noms des colonnes
column_default <- c("hostname", "ip", "date_debut", "date_fin")
column_choices <- names(ssl_all)

# noms des filtres
filter_choices <- c("Période", "Responsable", "Hostname")

# FIXME : trouver un moyen pour afficher les dates autrement mais garder le tri dynamique possible

# TODO : notifier quand echeance proche
text_notification <- "..."

# necessaire si filtre dans menu sinon erreur
convertMenuItem <- function(mi,tabName) {
  mi$children[[1]]$attribs['data-toggle'] <- "tab"
  mi$children[[1]]$attribs['data-value'] <- tabName
  mi
}

header <- dashboardHeader(title = "Certificats SSL", dropdownMenuOutput("notifOutput"))

sidebar <- dashboardSidebar(
  sidebarMenu(
    convertMenuItem(
      menuItem("Vue globale",
        tabName = "table",
        icon = icon("list"),
        dateRangeInput("date_fin_plage", label = "Choisir la période comprenant la date d'échéance :", start = Sys.Date(), end = Sys.Date(), separator = " à ", format = "yyyy-mm-dd"),
        textInput("sciper", "Choisir le sciper d'un responsable :", value = ""),
        textInput("hostname", "Choisir le hostname d'un certificat :", value = ""),
        checkboxGroupInput("columns_current", "Choisir les colonnes à afficher :", choices = column_choices, selected = column_default)),
      tabName = "table")
  )
)

body <- dashboardBody(
  tabItems(
    tabItem(tabName = "table",
      fluidPage(
        checkboxInput("expired_filter", "Afficher les certificats échus ?", FALSE),
        # TODO : finir choix pour activation des filtres
        checkboxGroupInput("filter", "Choisissez les filtres à activer :", choices = filter_choices, selected = NULL),
        DTOutput("df_all"),
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

server <- function(input, output, session) {
  output$notifOutput <- renderMenu({
    notif <- notificationItem(text_notification, icon = icon("warning"))
    dropdownMenu(type = "notifications", notif)
  })

  filtered_data <- reactive({
    if (length(input$columns_current) > 0) {
      data <- ssl_all[, input$columns_current, drop = FALSE]
      # time
      date_fin_min <- input$date_fin_plage[1]
      date_fin_max <- input$date_fin_plage[2]
      if (input$expired_filter) {
        data <- data %>% filter(date_fin >= date_fin_min & date_fin <= date_fin_max)
      } else {
        data <- data %>% filter(date_fin >= Sys.Date() & date_fin >= date_fin_min & date_fin <= date_fin_max)
      }
      # sciper
      sciper <- input$sciper
      if (grepl("^[0-9]*$", sciper) && sciper != "") {
        sciper <- as.integer(sciper)
        ips <- dbGetQuery(con_sqlite, sprintf("SELECT User.id_user, User.sciper, Server.id_ip, Server.ip FROM User LEFT JOIN Server_User ON User.id_user = Server_User.id_user LEFT JOIN Server ON Server_User.id_ip = Server.id_ip WHERE sciper = %s;", sciper))
        data <- data %>% filter(ip %in% ips$ip)
      }
      # hostname
      hn <- input$hostname
      if (hn != "") {
        data <- data %>% filter(hostname == hn)
      }
      return(data)
    } else {
      return(NULL)
    }
  })

  output$df_all <- renderDT({
    data_used <- filtered_data()
    if (!is.null(data)) {
      datatable(data_used, selection = 'single', options = list(searching = FALSE, pageLength = 20), class = 'stripe hover')
    } else {
      datatable(data.frame(Message = "Aucune colonne sélectionnée !"), selection = 'single', options = list(searching = FALSE, pageLength = 20), class = 'stripe hover', rownames = FALSE)
    }
  })

  output$df_resp <- renderDT({
    req(input$df_all_rows_selected) # affichage uniquement si ligne selectionnee
    selected_row <- input$df_all_rows_selected # index de la ligne selectionnee
    selected_data <- filtered_data()[selected_row, , drop = FALSE]
    ip <- selected_data$ip
    info_user <- dbGetQuery(con_sqlite, sprintf("SELECT sciper, cn, email, rifs_flag, adminit_flag FROM Server LEFT JOIN Server_User ON Server.id_ip = Server_User.id_ip LEFT JOIN User ON Server_User.id_user = User.id_user WHERE Server.ip = '%s';", ip))
    info_user <- info_user %>% rename(nom = cn, rifs = rifs_flag, adminit = adminit_flag) %>% mutate(rifs = ifelse(rifs == 1, "x", ""), adminit = ifelse(adminit == 1, "x", "")) %>% arrange (nom)
    # FIXME : filtrer sur quelle colonne a la base ?
    datatable(info_user, options = list(searching = FALSE, pageLength = 20), class = 'stripe hover')
  })

  # TODO : afficher les details du certificat (prendre exemple sur vrai)
  observeEvent(input$df_all_rows_selected, { showModal(modalDialog(title = "Informations du certificat", filtered_data()[input$df_all_rows_selected,], footer = modalButton("Fermer"))) })
}

shinyApp(ui, server)

# TODO : ajouter un onglet avec graphiques selon echeances courtes, moyennes, longues, ... et autres

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
ssl_data <- fromJSON(Search(con_elasticsearch, index = "ssl", size = 10000, raw = TRUE))$hits$hits$"_source" %>% mutate(ipv4 = as.character(ipv4)) %>% mutate(validFrom = as.Date(validFrom), validTo = as.Date(validTo))

# tableau global avec hostname, ip, date_debut, date_fin
tableau <- ssl_data %>% select(hostname, ipv4, validFrom, validTo) %>% rename(ip = ipv4, date_debut = validFrom, date_fin = validTo)

# FIXME : besoin des donnees de ces sous-tableaux pour afficher les details ?
subject <- ssl_data$subject
issuer <- ssl_data$issuer
proto <- ssl_data$proto

# TODO : notifier quand echeance proche
text_notification <- "TODO"

# necessaire si filtre dans menu sinon erreur
convertMenuItem <- function(mi,tabName) {
  mi$children[[1]]$attribs['data-toggle'] = "tab"
  mi$children[[1]]$attribs['data-value'] = tabName
  mi
}

sidebar <- dashboardSidebar(
  sidebarMenu(
    menuItem("Vue globale", tabName = "listing", icon = icon("list")),
    # TODO : date de debut et de fin pour periode d'echeance et affichage du label
    convertMenuItem(menuItem("Echéances", tabName = "date_filter", icon = icon("circle-exclamation"), DatePicker.shinyInput("date_fin_max", label = "Choisir la date d'échéance maximale :", value = NULL)), tabName = "date_filter"),
    convertMenuItem(menuItem("Responsables", tabName = "user_filter", icon = icon("info-circle"), numericInput("sciper", "Choisir le sciper d'un responsable :", value = NULL)), tabName = "user_filter")
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
  dashboardHeader(title = "Certificats SSL", dropdownMenuOutput("notifOutput")),
  sidebar,
  body
)

server <- function(input, output) {
  output$notifOutput <- renderMenu({
    notif <- notificationItem(text_notification, icon = icon("warning"))
    dropdownMenu(type = "notifications", notif)
  })

  # TODO : afficher details des certificats
  output$df_all <- renderDT({
    datatable(tableau, options = list(searching = FALSE), class = 'stripe hover')
  })

  output$df_date <- renderDT({
    if (is.null(input$date_fin_max)) {
      info_cert <- tableau
    } else {
      info_cert <- tableau %>% filter(date_fin <= input$date_fin_max)
    }
    datatable(info_cert, options = list(searching = FALSE), class = 'stripe hover')
  })

  output$df_user <- renderDT({
    sciper <- input$sciper
    # TODO : trouver un autre type pour sciper car si numeric alors nombre negatif autorise + fleches pour faire +/- 2, 3, ... mais pas de lettres sauf e
    if (is.na(sciper)) {
      info_cert <- tableau
    } else {
      ips <- dbGetQuery(con_sqlite, sprintf("SELECT User.id_user, User.sciper, Server.id_ip, Server.ip FROM User LEFT JOIN Server_User ON User.id_user = Server_User.id_user LEFT JOIN Server ON Server_User.id_ip = Server.id_ip WHERE sciper = %s;", sciper))
      info_cert <- tableau %>% filter(ip %in% ips$ip)
     }
    datatable(info_cert, selection = 'single', options = list(searching = FALSE), class = 'stripe hover')
  })

  output$df_resp <- renderDT({
    req(input$df_user_rows_selected) # affichage uniquement si ligne selectionnee
    selected_row <- input$df_user_rows_selected # index de la ligne selectionnee
    ip <- tableau[selected_row, ]$ip
    info_user <- dbGetQuery(con_sqlite, sprintf("SELECT sciper, cn, email, rifs_flag, adminit_flag FROM Server LEFT JOIN Server_User ON Server.id_ip = Server_User.id_ip LEFT JOIN User ON Server_User.id_user = User.id_user WHERE Server.ip = '%s';", ip))
    info_user <- info_user %>% rename(nom = cn, rifs = rifs_flag, adminit = adminit_flag) %>% mutate(rifs = ifelse(rifs == 1, "x", ""), adminit = ifelse(adminit == 1, "x", ""))
    # TODO : changer le sytle de l'affichage
    datatable(info_user, options = list(searching = FALSE), class = 'stripe hover')
  })

}

shinyApp(ui, server)

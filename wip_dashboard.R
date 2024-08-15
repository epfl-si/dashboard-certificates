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

# tableau global avec hostname, ip, date_debut, date_fin
tableau <- ssl_data %>% select(hostname, ipv4, validFrom, validTo) %>% mutate(validFrom = format(validFrom, "%d.%m.%Y"), validTo = format(validTo, "%d.%m.%Y")) %>% rename(ip = ipv4, date_debut = validFrom, date_fin = validTo)

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
      menuItem("Vue globale", tabName = "listing", icon = icon("list")),
      menuItem("Echéances", tabName = "date_filter", icon = icon("circle-exclamation")),
      menuItem("Responsables", tabName = "user_filter", icon = icon("info-circle"))
    )
  ),
  dashboardBody(
    tabItems(
      tabItem(tabName = "listing",
              fluidPage(
                DTOutput("df_all")
              )),
      tabItem(tabName = "date_filter",
              # TODO : ajouter un champ de recherche pour filtrer sur periode d'echeance
              fluidPage(
                DTOutput("df_date")
              )),
      tabItem(tabName = "user_filter",
              # TODO : ajouter un champ de recherche pour filtrer sur responsables
              fluidPage(
                DTOutput("df_user"),
                DTOutput("df_resp")
              ))
    )
  )
)

server <- function(input, output) {
  output$notifOutput <- renderMenu({
    notif <- notificationItem(text_notification, icon = icon("warning"))
    dropdownMenu(type = "notifications", notif)
  })

  output$df_all <- renderDT({
    datatable(tableau, options = list(searching = FALSE), class = 'stripe hover')
  })

  output$df_date <- renderDT({
    datatable(tableau, options = list(searching = FALSE), class = 'stripe hover')
  })

  output$df_user <- renderDT({
    datatable(tableau, selection = 'single', options = list(searching = FALSE), class = 'stripe hover')
  })

  output$df_resp <- renderDT({
    req(input$df_user_rows_selected) # affichage uniquement si ligne selectionnee
    selected_row <- input$df_user_rows_selected # index de la ligne selectionnee
    ip <- tableau[selected_row, ]$ip
    info_user <- dbGetQuery(con_sqlite, sprintf("SELECT sciper, cn, email, rifs_flag, adminit_flag FROM Server LEFT JOIN Server_User ON Server.id_ip = Server_User.id_ip LEFT JOIN User ON Server_User.id_user = User.id_user WHERE Server.ip = '%s';", ip))
    info_user <- info_user %>% rename(nom = cn, rifs = rifs_flag, adminit = adminit_flag) %>% mutate(rifs = ifelse(rifs == 1, "x", ""), adminit = ifelse(adminit == 1, "x", ""))
    # TODO : changer le sytle de l'affichage (autre tableau)
    datatable(info_user, options = list(searching = FALSE), class = 'stripe hover')
  })

}

shinyApp(ui, server)

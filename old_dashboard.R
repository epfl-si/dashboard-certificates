library(here)
here::i_am("lib.R")
source(here::here("lib.R"))
source(here::here("env.R"))

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
library(tidyr)
library(kableExtra)
library(knitr)

options(shiny.host = shiny_host)
options(shiny.port = 8180)

# open connection with elasticsearch
con_elasticsearch <- connect(host = host_elasticsearch, user = user_elasticsearch, pwd = password_elasticsearch, port = port_elasticsearch, transport_schema = "http")
# open connection with sqlite
con_sqlite <- dbConnect(RSQLite::SQLite(), db_path)

# import ssl data from elasticsearch
ssl_data <- fromJSON(Search(con_elasticsearch, index = "ssl", size = 10000, raw = TRUE))$hits$hits$"_source" %>%
  mutate(ipv4 = as.character(ipv4)) %>%
  mutate(validFrom = as.Date(validFrom), validTo = as.Date(validTo)) %>%
  dplyr::rename(ip = ipv4, date_debut = validFrom, date_fin = validTo)

# clean ssl data (hostname, ip, date_debut et date_fin)
ssl_specific <- ssl_data %>%
  select(hostname, ip, date_debut, date_fin) %>%
  arrange(hostname)

# table with all ssl data
ssl_all <- ssl_data

# selection of columns from ssl to display (sans ip et hostname car rajoutes plus tard)
column_default <- c("date_debut", "date_fin")
column_choices <- names(ssl_all)
column_choices <- column_choices[column_choices != "ip" & column_choices != "hostname"]

# notification
text_notification <- "..."

# necessaire si filtre dans menu sinon erreur
convertMenuItem <- function(mi, tabName) {
  mi$children[[1]]$attribs["data-toggle"] <- "tab"
  mi$children[[1]]$attribs["data-value"] <- tabName
  mi
}

# title + notifications
header <- dashboardHeader(title = "Certificats SSL", dropdownMenuOutput("notifOutput"))

# sidebar (column selection)
sidebar <- dashboardSidebar(
  collapsed = TRUE,
  sidebarMenu(
    convertMenuItem(
      menuItem("Choix des colonnes",
        tabName = "table",
        icon = icon("list"),
        checkboxGroupInput("columns_current", label = NULL, choices = column_choices, selected = column_default)
      ),
      tabName = "table"
    )
  )
)

# body (filters (expired cert, period, resp, hostname and cert without resp) + tables (ssl, resp with roles and info cert))
body <- dashboardBody(
  tabItems(
    tabItem(
      tabName = "table",
      fluidPage(
        fluidRow(
          column(
            width = 3,
            box(
              width = NULL,
              h4(strong("Choix des filtres :"), style = "text-align: center;"),
              checkboxInput("expired_filter", "Afficher les certificats échus ?", TRUE),
              hr(style = "border-color: black;"),
              checkboxInput("periode_filter", "Filtrer selon la période ?", FALSE),
              conditionalPanel(
                condition = "input.periode_filter == true", dateRangeInput("date_fin_plage", label = "Période comprenant la date d'échéance :", start = Sys.Date(), end = Sys.Date(), separator = " à ", format = "yyyy-mm-dd")
              ),
              hr(style = "border-color: black;"),
              checkboxInput("resp_filter", "Filtrer selon le responsable ?", FALSE),
              conditionalPanel(
                condition = "input.resp_filter == true", textInput("sciper", "Sciper d'un responsable :", value = "")
              ),
              hr(style = "border-color: black;"),
              checkboxInput("hostname_filter", "Filtrer selon le hostname ?", FALSE),
              conditionalPanel(
                condition = "input.hostname_filter == true", textInput("hostname", "Hostname d'un certificat :", value = "")
              ),
              hr(style = "border-color: black; border-width: 3px;"),
              checkboxInput("no_resp_filter", "Afficher uniquement les certificats sans responsable ?", FALSE)
            )
          ),
          column(
            width = 9,
            h4(strong("Affichage des échéances des certificats :"), style = "text-align: center;"),
            DTOutput("df_all")
          )
        ),
        fluidRow(
          hr(style = "border-color: black;"),
          conditionalPanel(
            condition = "input.df_all_rows_selected.length > 0", h4(strong("Affichage des responsables du certificat sélectionné :"), style = "text-align: center;")
          ),
          DTOutput("df_resp")
        )
      )
    )
  )
)

# user interface
ui <- dashboardPage(
  skin = "red",
  header,
  sidebar,
  body
)

# server
server <- function(input, output, session) {
  output$notifOutput <- renderMenu({
    notif <- notificationItem(text_notification, icon = icon("warning"))
    dropdownMenu(type = "notifications", notif)
  })

  # function to filter ssl data
  filtered_data <- reactive({
    data_filtred <- ssl_all

    # time
    date_fin_min <- input$date_fin_plage[1]
    date_fin_max <- input$date_fin_plage[2]
    if (!input$expired_filter) {
      data_filtred <- data_filtred %>% filter(date_fin >= Sys.Date())
    }
    if (input$periode_filter && date_fin_min <= date_fin_max) {
      data_filtred <- data_filtred %>% filter(date_fin >= date_fin_min & date_fin <= date_fin_max)
    }

    # sciper
    if (input$resp_filter) {
      sciper <- input$sciper
      if (grepl("^[0-9]*$", sciper) && sciper != "") {
        sciper <- as.integer(sciper)
        ips <- dbGetQuery(con_sqlite, sprintf("SELECT User.id_user, User.sciper, Server.id_ip, Server.ip FROM User LEFT JOIN Server_User ON User.id_user = Server_User.id_user LEFT JOIN Server ON Server_User.id_ip = Server.id_ip WHERE sciper = %s;", sciper))
        data_filtred <- data_filtred %>% filter(ip %in% ips$ip)
      }
    }

    # hostname
    if (input$hostname_filter) {
      hn <- input$hostname
      if (hn != "") {
        data_filtred <- data_filtred %>% filter(hostname == hn)
      }
    }

    # filter to control cert without resp
    if (input$no_resp_filter) {
      ips_cmdb <- dbGetQuery(con_sqlite, "SELECT Server.ip FROM Server")
      data_filtred <- ssl_all %>% filter(ip %ni% ips_cmdb$ip)
    }

    # choice of columns
    data <- data_filtred[, input$columns_current, drop = FALSE]

    if (nrow(data) > 0) {
      # add column with ip
      data$ip <- data_filtred$ip
      data <- data %>% select(ip, everything())

      # add column with hostname
      data$hostname <- data_filtred$hostname
      data <- data %>% select(hostname, everything())

      # add column to display pop up with certificate information
      data$info <- '<i class=\"fa fa-info-circle\"></i>'
      data <- data %>% select(info, everything())
    } else {
      data <- NULL
    }
    return(data)
  })

  # main table with ssl data and selected columns
  output$df_all <- renderDT({
    data_used <- filtered_data()
    if (!is.null(data_used)) {
      # hostname with link
      data_used$hostname <- sprintf("<a href='https://%s' target='_blank'>%s</a>", data_used$hostname, data_used$hostname)
      datatable(data_used, escape = FALSE, selection = "single", options = list(scrollX = TRUE, dom = "frtip", pageLength = 10), class = "stripe hover", rownames = FALSE)
    } else {
      datatable(data.frame(Message = "Aucun certificat ne correspond..."), selection = "single", options = list(dom = "rt", pageLength = 10), class = "stripe hover", rownames = FALSE)
    }
  })

  # table of resp dependent on selected line in main table
  output$df_resp <- renderDT({
    req(input$df_all_rows_selected) # affichage uniquement si ligne selectionnee
    selected_row <- input$df_all_rows_selected # index de la ligne selectionnee
    selected_data <- filtered_data()[selected_row, , drop = FALSE]
    ip <- selected_data$ip
    info_user <- dbGetQuery(con_sqlite, sprintf("SELECT sciper, cn, email, rifs_flag, adminit_flag FROM Server LEFT JOIN Server_User ON Server.id_ip = Server_User.id_ip LEFT JOIN User ON Server_User.id_user = User.id_user WHERE Server.ip = '%s';", ip))
    info_user <- info_user %>%
      dplyr::rename(nom = cn, rifs = rifs_flag, adminit = adminit_flag) %>%
      mutate(rifs = ifelse(rifs == 1, "x", ""), adminit = ifelse(adminit == 1, "x", "")) %>%
      arrange(nom)
    if (nrow(info_user) > 0) {
      datatable(info_user, options = list(searching = TRUE, pageLength = 10), class = "stripe hover", rownames = FALSE)
    } else {
      datatable(data.frame(Message = "Aucun responsable assigné !"), selection = "single", options = list(dom = "rt", pageLength = 10), class = "stripe hover", rownames = FALSE)
    }
  })

  # pop up when click on column "info" in main table to display cert info
  observeEvent(input$df_all_cell_clicked, {
    if (!is.null(input$df_all_cell_clicked$value)) {
      if (input$df_all_cell_clicked$col == 0) {
        selected_row <- filtered_data()[input$df_all_cell_clicked$row, , drop = FALSE]
        cert_data <- ssl_all[selected_row$ip == ssl_all$ip & selected_row$hostname == ssl_all$hostname, ]

        # subject name
        output$subject_name <- renderTable({
          cert_data$subject %>%
            select(CN) %>%
            dplyr::rename("Common Name" = CN)
        })

        # issuer name
        output$issuer_name <- renderTable({
          cert_data$issuer %>%
            select(C, ST, L, O, CN) %>%
            dplyr::rename("Country" = C, "State/Province" = ST, "Locality" = L, "Organization" = O, "Common Name" = CN)
        })

        # validity
        output$validity <- renderUI({
          cert_data %>%
            select(date_debut, date_fin) %>%
            dplyr::rename("Not Before" = date_debut, "Not After" = date_fin) %>%
            kable(format = "html", row.names = FALSE) %>%
            kable_styling() %>%
            HTML()
        })

        # subject alt names
        output$subject_alt_names <- renderTable({
          san <- cert_data %>% select(san)
          as.data.frame(lapply(san, function(col) {
            if (is.list(col)) {
              sapply(col, paste, collapse = ", ")
            } else {
              col
            }
          })) %>% dplyr::rename("DNS Name" = san)
        })

        showModal(modalDialog(title = "Informations du certificat", easyClose = TRUE, "Subject Name", tableOutput("subject_name"), tags$hr(style = "border-top: 1px solid #000;"), "Issuer Name", tableOutput("issuer_name"), tags$hr(style = "border-top: 1px solid #000;"), "Validity", uiOutput("validity"), tags$hr(style = "border-top: 1px solid #000;"), "Subject Alt Names", tableOutput("subject_alt_names"), footer = modalButton("Fermer")))
      }
    }
  })
}

shinyApp(ui, server)

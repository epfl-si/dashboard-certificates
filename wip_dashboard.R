library(here)
here::i_am("lib.R")
source(here::here("lib.R"))
source(here::here("env.R"))
source(here::here("clean_data.R"))

# TODO : packages actives a jour ? + mettre a jour fichier lib.R
library(shiny)
library(shinydashboard)
library(shiny.fluent)
library(DT)
library(RSQLite)
library(ggplot2)

options(shiny.host = shiny_host)
options(shiny.port = 8180)

# open connection with sqlite
con_sqlite <- dbConnect(RSQLite::SQLite(), db_path)

# ssl with all columns
ssl_all <- ssl_data

# necessaire si filtre dans menu sinon erreur
convertMenuItem <- function(mi, tabName) {
  mi$children[[1]]$attribs["data-toggle"] <- "tab"
  mi$children[[1]]$attribs["data-value"] <- tabName
  mi
}

# title
header <- dashboardHeader(title = "Certificats SSL")

# filters
sidebar <- dashboardSidebar(
  collapsed = TRUE,
  sidebarMenu(
    convertMenuItem(
      menuItem("Filtres",
        tabName = "table",
        icon = icon("list"),
        checkboxInput("expired_filter", "Afficher les certificats échus ?", TRUE),

        # TODO / FIXME : en attente de reponse
        # h4(("Afficher les certificats...")),
        # checkboxInput("echus", "Expirés", FALSE),
        # checkboxInput("echus", "Récemment expirés", FALSE),
        # checkboxInput("echus", "0-30 jours", FALSE),
        # checkboxInput("echus", "31-60 jours", FALSE),
        # checkboxInput("echus", "61-90 jours", FALSE),
        # checkboxInput("echus", "> 90 jours", FALSE),
        # FIXME / TODO : periode reprend filtre selon categorie puis filtrer plus precis avec filtre sur periode mais pas possible de filtrer moins precis ou sinon casse premier filtre sur categorie

        hr(style = "border-color: black;"),
        checkboxInput("periode_filter", "Filtrer selon la période ?", FALSE),
        conditionalPanel(
          condition = "input.periode_filter == true", dateRangeInput("date_fin_plage", label = "Période comprenant la date d'échéance :", start = Sys.Date(), end = Sys.Date(), separator = " à ", format = "yyyy-mm-dd")
        ),
        hr(style = "border-color: black;")
      ),
      tabName = "table"
    )
  )
)

# body (plot + table)
body <- dashboardBody(
  tabItem(
    tabName = "table",
    fluidPage(
      fluidRow(
        plotOutput("plot")
      ),
      fluidRow(hr(style = "border-color: black;")),
      fluidRow(
        h4(strong("Détails des certificats"), style = "text-align: center;"),
        div(style = "text-align: center; margin-top: 20px; margin-bottom: 10px;", downloadButton("download_data", "Téléchargement des données", style = "align: left;")),
        div(style = "text-align: center;", actionButton(inputId = "update_cert", label = "Renouveller un certificat", icon = icon("repeat"), onclick = "window.open('https://rauth.epfl.ch/', '_blank')")),
        DTOutput("df")
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
  # function to filter ssl data
  filtered_data <- reactive({
    data <- ssl_all

    # time
    date_fin_min <- input$date_fin_plage[1]
    date_fin_max <- input$date_fin_plage[2]
    if (!input$expired_filter) {
      data <- data %>% filter(date_fin >= Sys.Date())
    }
    if (input$periode_filter && date_fin_min <= date_fin_max) {
      data <- data %>% filter(date_fin >= date_fin_min & date_fin <= date_fin_max)
    }

    if (nrow(data) > 0) {
      # add column to display pop up with certificate information
      data <- data %>% mutate(info = '<i class=\"fa fa-info-circle\"></i>')
    } else {
      data <- NULL
    }
    return(data)
  })

  # plot depending on due date
  output$plot <- renderPlot({
    data_due_date <- ssl_all %>%
      mutate(cat_exp = case_when(
        date_fin < Sys.Date() - 7 ~ "Expirés",
        date_fin < Sys.Date() ~ "Récemment expirés",
        date_fin < Sys.Date() + 30 ~ "0-30 jours",
        date_fin < Sys.Date() + 60 ~ "31-60 jours",
        date_fin < Sys.Date() + 90 ~ "61-90 jours",
        TRUE ~ "> 91 jours"
      ))

    max_count <- data_due_date %>%
      dplyr::count(cat_exp) %>%
      summarise(max_count = max(n)) %>%
      pull(max_count)
    max_count_round <- round_any(max_count, 100, f = ceiling)

    ggplot(data = data_due_date, aes(x = factor(cat_exp, levels = c("Expirés", "Récemment expirés", "0-30 jours", "31-60 jours", "61-90 jours", "> 91 jours")), fill = factor(cat_exp, levels = c("Expirés", "Récemment expirés", "0-30 jours", "31-60 jours", "61-90 jours", "> 91 jours")))) +
      geom_hline(yintercept = seq(0, max_count_round, by = 50), linetype = "solid", linewidth = 0.5, color = "lightgrey") +
      geom_bar(show.legend = FALSE) +
      scale_fill_manual(values = c("black", "red", "orange", "yellow", "green", "blue")) +
      labs(
        title = "Echéances des certificats",
        x = "",
        y = ""
      ) +
      theme(
        plot.title = element_text(hjust = 0.5, size = 20, margin = margin(b = 10)),
        axis.title.x = element_text(size = 16, margin = margin(t = 20)),
        axis.text.x = element_text(size = 16, margin = margin(t = 0)),
        axis.title.y = element_text(size = 16, margin = margin(r = 20)),
        axis.text.y = element_text(size = 16, margin = margin(r = 5)),
        panel.grid.major = element_blank(),
        panel.grid.minor = element_blank(),
        panel.background = element_blank()
      ) +
      geom_text(stat = "count", aes(label = after_stat(count)), vjust = -0.5, size = 6) +
      scale_y_continuous(limits = c(0, max_count_round), breaks = seq(0, max_count_round, by = 50))
  })

  # TODO : filtrer selon clic sur colonne -> https://stackoverflow.com/questions/41654801/r-shiny-plot-click-with-geom-bar-and-facets
  # table with selected data
  output$df <- renderDT({
    data_used <- filtered_data()
    if (!is.null(data_used)) {
      data_used <- data_used %>% select(info, date_fin, ip, hostname, san)
      datatable(data_used, escape = FALSE, selection = "single", options = list(scrollX = TRUE, dom = "frtip", pageLength = 10), class = "stripe hover", rownames = FALSE)
    } else {
      datatable(data.frame(Message = "Aucun certificat ne correspond..."), selection = "single", options = list(dom = "rt", pageLength = 10), class = "stripe hover", rownames = FALSE)
    }
  })

  # button to download data
  output$download_data <- downloadHandler(
    filename = "data.csv", content = function(file) {
      data <- filtered_data()
      data <- data %>% select(date_fin, ip, hostname, san)
      write.csv(data, file, row.names = FALSE)
    }
  )

  # pop up when click on column "info" in table to display certificate info
  observeEvent(input$df_cell_clicked, {
    if (!is.null(input$df_cell_clicked$value)) {
      if (input$df_cell_clicked$col == 0) {
        selected_row <- filtered_data()[input$df_cell_clicked$row, , drop = FALSE]
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
            select(C, O, CN) %>%
            dplyr::rename("Country" = C, "Organization" = O, "Common Name" = CN)
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
          san <- cert_data %>%
            select(san) %>%
            dplyr::rename("DNS Name" = san)
        })

        # serial number
        output$serial_number <- renderTable({
          serial_number <- cert_data %>%
            select(serialNumberHex) %>%
            dplyr::rename("Serial Number" = serialNumberHex)
        })

        showModal(modalDialog(title = "Informations du certificat", easyClose = TRUE, "Subject Name", tableOutput("subject_name"), tags$hr(style = "border-top: 1px solid #000;"), "Issuer Name", tableOutput("issuer_name"), tags$hr(style = "border-top: 1px solid #000;"), "Validity", uiOutput("validity"), tags$hr(style = "border-top: 1px solid #000;"), "Subject Alt Names", tableOutput("subject_alt_names"), tags$hr(style = "border-top: 1px solid #000;"), "Serial Number", tableOutput("serial_number"), footer = modalButton("Fermer")))
      }
    }
  })
}

shinyApp(ui, server)

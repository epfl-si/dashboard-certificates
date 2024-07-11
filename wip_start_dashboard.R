# FIXME : installation et activation dans autre script selon env
library(ggplot2)
library(shiny)
library(DT)


# FIXME : selon env si container ou local
options(shiny.host = "0.0.0.0")
options(shiny.port = 8180)



# open connection with elasticsearch
con_elasticsearch <- connect(host = "localhost", path = "", user="", pwd = "", port = 9200, transport_schema  = "http")
# open connection with sqlite
con_sqlite <- dbConnect(RSQLite::SQLite(), "./volumes/sqlite/cmdb.sqlite")

# import ssl data from elasticsearch
ssl_data <- fromJSON(Search(con_elasticsearch, index = "ssl", size = 10000, raw = TRUE))$hits$hits$"_source" %>% mutate(ipv4 = as.character(ipv4))


ui <- fluidPage(
  titlePanel("SSL details"),
  fluidRow(
    column(4,
        selectInput("date_fin",
                    "Date d'échéance:",
                    c("All", unique(as.character(ssl_data$validTo))))
    )
  ),
  DT::dataTableOutput("table")
)

server <- function(input, output) {
  output$table <- DT::renderDataTable(DT::datatable({
    data <- ssl_data
    if (input$date_fin != "All") {
      data <- data[data$validTo == input$date_fin,]
    }
    data
  }))
}

shinyApp(ui = ui, server = server)

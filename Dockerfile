FROM rocker/shiny

RUN apt-get update && \
    apt-get install -y sqlite3 libsqlite3-dev

RUN mkdir /srv/cert_dashboard

WORKDIR /srv/cert_dashboard

RUN R -e "install.packages(\"here\")"

COPY lib.R /srv/cert_dashboard
COPY create_schema.R /srv/cert_dashboard
COPY clean_data.R /srv/cert_dashboard
COPY add_cmdb_data.R /srv/cert_dashboard
COPY dashboard.R /srv/cert_dashboard
COPY shiny-server.conf /etc/shiny-server/shiny-server.conf

ENTRYPOINT ["Rscript", "/srv/cert_dashboard/dashboard.R"]

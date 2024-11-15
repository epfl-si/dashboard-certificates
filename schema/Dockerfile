FROM rocker/shiny

RUN apt-get update && \
    apt-get install -y sqlite3 libsqlite3-dev

RUN mkdir /srv/cert_dashboard

WORKDIR /srv/cert_dashboard

RUN R -e "install.packages(\"here\")"

# FIXME : choisir les fichiers a copier ? (.env dedans)
COPY *.R /srv/cert_dashboard
COPY env-docker.R /srv/cert_dashboard/env.R
COPY shiny-server.conf /etc/shiny-server/shiny-server.conf

CMD [ "Rscript", "/srv/cert_dashboard/add_cmdb_data.R" ]

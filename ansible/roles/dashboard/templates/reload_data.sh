#!/bin/bash
set -e -x
echo START : >> {{ dashboard_install_path }}/logs.txt && date >> {{ dashboard_install_path }}/logs.txt
docker stop cert_dashboard
docker system prune -f
docker run --rm -p "80:8180" -v {{ dashboard_install_path }}/env.R:{{ dashboard_install_path }}/env.R --name {{ container_name }} -d {{ dashboard_image_url_anonymous_pull }} /bin/sh -c "Rscript {{ dashboard_install_path }}/add_cmdb_data.R && mv {{ dashboard_install_path }}/cmdb_temp.sqlite {{ dashboard_install_path }}/cmdb.sqlite && Rscript {{ dashboard_install_path }}/dashboard.R"
echo END : >> {{ dashboard_install_path }}/logs.txt && date >> {{ dashboard_install_path }}/logs.txt

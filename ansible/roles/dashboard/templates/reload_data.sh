#!/bin/bash
docker exec cert_dashboard /bin/bash -c "echo \"START :\" >> /tmp/logs.txt && date >> /tmp/logs.txt"
docker exec cert_dashboard /bin/bash -c "echo \"Update cmdb schema :\" >> /tmp/logs.txt && date >> /tmp/logs.txt"
docker exec cert_dashboard /bin/bash -c "Rscript {{ dashboard_install_path }}/add_cmdb_data.R"
docker exec cert_dashboard /bin/bash -c "mv {{ dashboard_install_path }}/cmdb_temp.sqlite {{ dashboard_install_path }}/cmdb.sqlite"
docker exec cert_dashboard /bin/bash -c "echo \"END :\" >> /tmp/logs.txt && date >> /tmp/logs.txt"

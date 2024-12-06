#!/bin/bash
#!/bin/bash
docker exec cert_dashboard /bin/bash -c "echo \"START (update schema) :\" >> /tmp/logs.txt && date >> /tmp/logs.txt"
docker exec cert_dashboard /bin/bash -c "Rscript /srv/cert_dashboard/add_cmdb_data.R"
docker exec cert_dashboard /bin/bash -c "mv cmdb_temp.sqlite cmdb.sqlite"
docker exec cert_dashboard /bin/bash -c "echo \"Reload dashboard :\" >> /tmp/logs.txt && date >> /tmp/logs.txt"
docker exec cert_dashboard /bin/bash -c "Rscript /srv/cert_dashboard/dashboard.R"
docker exec cert_dashboard /bin/bash -c "echo \"END :\" >> /tmp/logs.txt && date >> /tmp/logs.txt"


#! /bin/bash
# should be executed with postgres super user priviledge
while [ "$(psql market -t -c 'SELECT market.foc_start_vacuum(true)')" -ne 2 ]
do
        sleep 1
done
psql market -t -c 'VACUUM FULL'
psql market -t -c 'SELECT market.foc_start_vacuum(false)'
echo 'VACUUM FULL done'

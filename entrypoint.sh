#!/bin/bash

/etc/init.d/supervisor start

sleep 5

if [[ "$?" -eq "0" ]]; then
    sudo su postgres -c '/usr/local/pgsql/bin/psql -f /data/pgsql/tmp/.user_data.sql'
    if [[ "$?" -eq "0" ]]; then
        sleep 3
    fi
fi
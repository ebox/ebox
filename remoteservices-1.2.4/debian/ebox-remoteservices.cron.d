# /etc/cron.d/ebox-remoteservices: crontab entries for the ebox-remoteservices package

SHELL=/bin/sh
PATH=/usr/bin:/bin

# Get the clients and their eBox assigned to our VPN server each minute
0-59/15 * * * * root /usr/share/ebox/ebox-notify-mon-stats >> /dev/null 2>&1
# Run the cron jobs sent by eBox CC
0-59/10 * * * * root /usr/share/ebox/ebox-cronjob-runner >> /dev/null 2>&1
# Get the new cron jobs from eBox CC
10 3 * * * root /usr/share/ebox/ebox-get-cronjobs >> /dev/null 2>&1
# Run the automatic backup
32 2 * * * root /usr/share/ebox/ebox-automatic-conf-backup > /dev/null 2>&1

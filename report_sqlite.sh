#!/bin/bash
#====================================================================================================#
# Abstract    :   Script to initiate diskreport if mountpoint space utilization is greater than 95%  #
# Usage       :   sendreport.sh                                                                      #
# Description :   Script will check all mountpoint in server and if mountpoint utilization is equal  #
#                 to or more than 95% this script will initiate the actual diskreport script. Script #
#                 will be running every 5 minutes,if the alert is not cleared then then diskreport   #
#                 script will be initiated again after 30 minutes                                    #
# Add. Info   :   Need to be executed using cron or control-M                                        #
# Author      :   SysOps                                                                             #
# Changes     :   19-04-2020, Shenny R S                       v1, Initial version                   #
#                 29-05-2020, Shenny R S                       v2, Added gpfs fileset check          #
#                 04-06-2021, Shenny R S                       v3, Individual threshold settings     #
#====================================================================================================#

set -eo pipefail

# Vars
sysops_partitions="shared|microfocus|company|db2|ctm|pmf|stp|tsm|postfix|bmc|asc|ade|subversion|corefiles"
client_env_file="/etc/profile.d/001_client_env.sh"
current_date="$(date +%d%b%Y)"
current_time="$(date +%s)"
mphr=60 #minutes per hour
tmpdir="/tmp/$current_date"
sqlite_config="$tmpdir/sqliterc.sh"
threshold_prod="90"
threshold_non_prod="90"
logfile="$tmpdir/report.log"
pidfile="/var/run/sendreport.pid"
dbfile="diskinfo.db"

# Script Usage
help() {
    echo -e "Usage:\t$0"
    echo -e "\t$0 -d <mountpoint>"
    echo -e "\t$0 -e <mountpoint>"
    echo -e "\t$0 -t \"<mountpoint> <thresholdvalue>\""
    echo -e "\t$0 -h"
    echo -e "\t$0 -p"
    echo -e "\t$0 -c"
    echo -e "\t$0 -r\n"
    echo -e "Options:"
    echo -e " -d\tDisabling mount point from the mailreport"
    echo -e " -e\tEnabling mount point from the mailreport"
    echo -e " -t\tThreshold percentage to be added along with the partition name.Value should be between 0 & 100. eg: $0 -t \"/shared 90\""
    echo -e " -h\tScript usage"
    echo -e " -p\tPrint alerting database"
    echo -e " -c\tCreate alerting database"
    echo -e " -r\tDelete alerting database"
    exit 0
}

# Check if Server is prod or non-prod and set alerting interval
staging_check() {
    if [ -f "$client_env_file" ];then
        staging="$(awk -F"[=/]" '/SHARED_BASE_DIR/ {print $5}' ${client_env_file})"
        [[ "$staging" == "prod" ]] && echo "prod" && alert_interval=60 #Production will be alerted every 30 minutes
        [[ "$staging" == "test" ]] && echo "test" && alert_interval=120 #Non Prod will be alerted every 2 hours
    else
        alert_interval=120
        echo "test"
    fi
}

# Setting default threshold limit
threshold_limit() {
    [[ $(staging_check) == "prod" ]] && echo "$threshold_prod"
    [[ $(staging_check) == "test" ]] && echo "$threshold_non_prod"
}

# Calling diskreport script
run_diskreport() {
    staging_check >/dev/null
    local mount_points=( "$@" )
    cd "$dbpath" || logger "ERROR:\tNo such File or Directory $dbpath"
    for entry in ${mount_points[@]};do
        [ "${entry: -4}" == "/sec" ] && continue # Skipping guardium mountpoints ending with /sec
        local excluded_mount=$(sqlite3 $dbfile "select MOUNTNAME from mountrecords where ALERTING_STATUS='off' and MOUNTNAME='$entry';")
        local check_file="$tmpdir"/$(echo "$entry" | sed 's/\//_/g')
        [ -n "$excluded_mount" ] && continue
        if [ ! -f "$check_file" ];then
            cd "$tmpdir" || logger "ERROR:\tNo Such File or Directory $tmpdir"
            echo "$current_time" >"$check_file"
            "$SHARED_BASE_DIR"/syswork/scripts/diskreport.sh -d "$entry" -f soap
            logger "INFO:\tDiskreport generated for ${entry}"
        else
            previous_time="$(cat $check_file)"
            time_diff="$(((current_time - previous_time) / mphr))"
            if [[ "$time_diff" -gt "$alert_interval" ]];then
                echo "$current_time" >"$check_file"
                "$SHARED_BASE_DIR"/syswork/scripts/diskreport.sh -d "$entry" -f soap
                logger "INFO:\tDiskreport generated for ${entry}"
            fi
        fi
    done
}

# Enable and disable alert for a mountpoint
alert_on_off() {
    local target="$1"
    local switch="$2"
    cd "$dbpath" || logger "ERROR:\tNo such file or directory: $dbpath"
    [ ! -f "$dbfile" ] && logger "ERROR:\tNo Such File or Directory $dbfile"
    [ ! -d "$target" ] && logger "ERROR:\tNo Such File or Directory $target"
    if mountpoint -q -- "$target";then
        if [[ "$switch" == "on" ]];then
            sqlite3 "$dbfile" "update mountrecords set ALERTING_STATUS='on' where MOUNTNAME='$target';"
            logger "INFO:\tAlerting enabled for $target"
        else
            sqlite3 "$dbfile" "update mountrecords set ALERTING_STATUS='off' where MOUNTNAME='$target';"
            logger "INFO:\tAlerting disabled for $target"
        fi
    else
        logger "ERROR:\tDirectory $target is not a mountpoint"
    fi
}

# Writing logs against each action
logger() {
    msg="$*"
    status=$(awk -F: '{print $1}' <<<"$msg")
    [ ! -d "$tmpdir" ] && mkdir "$tmpdir"
    echo -e "${current_date}:$(date +%X): $msg" | tee -a "$logfile"
    if [[ "$status" == "ERROR" ]];then
        exit 127
    fi
}

# sqlite db which have mountpoint,threshold limit and alerting_status information
alert_db() {
    local option="$1"
    local mount_point="$(echo $2 | awk '{print $1}')"
    local threshold="$(echo $2 | awk '{print $2}')"
    local integer_check='^[1-9][0-9]?$|^100$'
    cd "$dbpath" || logger "ERROR:\tNo Such File or Directory $dbpath"
    case $option in
        create)
            if [ ! -f "$dbfile" ];then
                sqlite3 "$dbfile" "create table mountrecords(MOUNTNAME varchar(100) PRIMARY KEY, THRESHOLD INTEGER, ALERTING_STATUS varchar(10));"
                while IFS= read -r line;do
                    mp="$line"
                    sqlite3 "$dbfile" "insert into mountrecords values('$mp',$(threshold_limit),'on');"
                done < <(df -hP | grep -E $sysops_partitions | awk '$NF ~ /^\// {print $NF}')
                logger "INFO:\tCreated db on $dbfile"
            fi
            ;;
        update)
            # Checking if threshold is a valid integer or not
            if ! [[ "$threshold" =~ $integer_check ]];then
                logger "ERROR:\tThreshold should be an integer [0-100]"
            fi
            # Checking if the input directory is a mountpoint or not
            if mountpoint -q -- "$mount_point";then
                if [ -f "$dbfile" ];then
                    sqlite3 "$dbfile" "update mountrecords set THRESHOLD='$threshold' where MOUNTNAME='$mount_point';"
                    logger "INFO:\tThreshold value:$threshold updated for $mount_point"
                    exit 0
                else
                    logger "ERROR:\tNo Such File or Directory $dbfile"
                fi
            else
                logger "ERROR:\tMentioned mountpoint:$mount_point is not a valid one"
            fi
            ;;
        list)
            if [ -f "$dbfile" ];then
                sqliterc
                sqlite3 -init "$tmpdir/sqliterc.sh" "$dbfile" "select * from mountrecords;" 2>/dev/null
                exit 0
            else
                logger "ERROR:\tNo Such File or Directory $dbfile"
            fi
            ;;
        *)
            logger "ERROR:\tInvalid entry"
            ;;
    esac
}

#sqlite3 meta commands
sqliterc() {
cat <<EOF >"$sqlite_config"
.width 50
.mode column
.headers on
EOF
}

# Cleanup function to check duplicate running process
cleanup() {
    find /var/run/ -type f -name sendreport.pid -delete 2>/dev/null
}


# tempdir creation
[ ! -d "$tmpdir" ] && mkdir "$tmpdir"
[ -f "$client_env_file" ] && source /etc/profile.d/001_client_env.sh
diskreport="$SHARED_BASE_DIR/syswork/scripts/diskreport.sh"
dbpath="$SHARED_BASE_DIR/syswork/diskreport"

while getopts ":d:e:hpcrt:" option;do
    case "$option" in
        e)  if [ "${OPTARG}" != "/" ] && [ "${OPTARG: -1}" == "/" ];then  #Checking if input is not equal to / and if its end with /
                mount_monitor="${OPTARG:0:-1}"  #remove th trailing /
            else
                mount_monitor="${OPTARG}"
            fi
            alert_on_off "$mount_monitor" on
            ;;
        d)  if [ "${OPTARG}" != "/" ] && [ "${OPTARG: -1}" == "/" ];then
                mount_ignore="${OPTARG:0:-1}"
            else
                mount_ignore="${OPTARG}"
            fi
            alert_on_off "$mount_ignore" off
            ;;
        h)  help
            ;;
        p)  alert_db list
            ;;
        c)  alert_db create
            ;;
        t)  mp=$(echo ${OPTARG[@]}| awk '{print $1}')
            th=$(echo ${OPTARG[@]}| awk '{print $2}')
            if [[ -n "$mp" ]] && [[ -n "$th" ]];then
                alert_db update "$mp $th"
            else
                help
            fi
            ;;
        r)  [ -f "$dbpath/$dbfile" ] && find "$(readlink -f $dbpath)" -maxdepth 1 -type f -name "$dbfile" -delete
            logger "INFO:\tDatabase $dbpath/$dbfile deleted" && exit 0
            ;;
        ?)  echo "invalid option"
            ;;
    esac
done

# Getting device list
[ ! -f "$dbfile" ] && alert_db create
[ ! -f "$diskreport" ] && logger "ERROR:\tNo Such File or Directory $diskreport"
for mount_point in $(findmnt -ns --raw --evaluate --output=target | grep -E "$sysops_partitions");do
    excluded_mount=$(sqlite3 $dbfile "select MOUNTNAME from mountrecords where ALERTING_STATUS='off' and MOUNTNAME='$mount_point';")
    threshold=$(sqlite3 $dbfile "select THRESHOLD from mountrecords where MOUNTNAME='$mount_point';")
    [ -n "${excluded_mount}" ] && continue
    filesystem_type="$(stat -f -c %T ${mount_point})"
    if [[ "$filesystem_type" == "gpfs" ]];then
        gpfs_device+="$(findmnt -nl ${mount_point} | awk '{print $2}')"
        for gpfs_fileset in $(mmlsfileset "$gpfs_device" | awk '/shared/ {print $3}');do
            if [[ -n $(df -hP "${gpfs_fileset}" | awk -v limit=$threshold '0+$5 >= limit') ]];then
                gpfs_target_mounts+=( "$gpfs_fileset" )
            fi
        done
    else
        if [[ -n $(df -hP "${mount_point}" | awk -v limit=$threshold '0+$5 >= limit') ]];then
            target_mounts+=( "$mount_point"  )
        fi
    fi
done

# Check if another instance of this script is running or not
if [ -f "$pidfile" ];then
    logger "ERROR:\Another script instance is running with PID:$(cat $pidfile)"
else
    echo "$$">"$pidfile"
fi


[[ -n "${gpfs_target_mounts[@]}" ]] && run_diskreport "${gpfs_target_mounts[@]}"
[[ -n "${target_mounts[@]}" ]] && run_diskreport "${target_mounts[@]}"

trap cleanup EXIT

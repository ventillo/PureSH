#!/bin/sh
set +x

#-------------------------------------------------------------------------------
# Shell script for PURE STORAGE arrays information gather
# Using API calls in v1.8
#
#
# Author: Milan Toman
#-------------------------------------------------------------------------------

# Todo:
#   Error handling
#   Input values check, failsafe
#   New disk add - mapping

VERSION="1.1"
SUBJECT="REST_API_Pure_CLI"

#_PURE_IP=""
#_PURE_USER=""
#_PURE_PASS=""
# Token must be generated in GUI / CLI to use this script
#_PURE_TOKEN=""

USAGE="
    SYNOPSIS:
        $0 -i [-h -P -I -m
               -D [-F <regexp>]] 
           -u <user> | -t <token>
           

    DESCRIPTION:
        Script and formatter to extract information out of the PURE family
        storage boxes.
        Uses Pure REST API v1.8
        In this, initial version, tokens must be manually generated via CLI/GUI
        in order to get a reasonable response from the storage array

        Auth information is stored in session cookies, which must be stored in
        a file in order to get WGET authenticated.
        This file is stored in local directory and is called auth.txt.
        Current session does not expire and poses a security risk as well.

    OPTIONS:

        -h      Help, obviously
        
        -u <username>     
                Username for Pure to interactively type in a password at later 
                stage. This option DOES NOT HAVE TO BE SPECIFIED with -t. 
                
        -t <token>     
                Token, also displayed after successfull auth via user/pass (-u)
                This can be used if you don't want to type your password all the
                time. You can run -u <username> to display the token first, use
                just the token later
        
        -l <snap_pg | vols | msg | info | maps | port | perf>
                Listing details of a spacific part of configuration or hardware
                <snap_pg> 
                    * list snapshots of protection groups, not listing the 
                      volume snapshots
                <vols>
                    * list of volumes created on the system (same as -D)
                    -f <regexp>
                        * optional filter on the results
                <msg>
                    * messages, a.k.a. alerts and info
                <info>
                    * additional information on the storage array (same as -I)
                <maps>
                    *  show host list. When used together with -f it displays 
                       details as well
                    -f <regexp>
                        * optional filter on the results - this has to be used 
                          to see the actual mapping
                        * to display all mapping for all hosts, use -f '.'
                <port>
                    * list of frontend ports
                <perf>
                    * if used with 'perf', values for hostorical timeframes 
                      1h, 3h, 24h, 7d, 30d, 90d, and 1y can be used.
                    
               

        -P      Port information

        -I      Basic array info, including pool occupancy

        -m      Messages, logging and auditing

        -S <protection_group>      
                Create a snapshot from a protection group
                <protection_group> 
                
            -s <suffix>
                The snapshot suffix of the protection group snapshot
                Cannot be just numbers, needs to be chars, at least start with 
                a character. This has to be used in conjunction with -S
        
        -C <pg_name>      
                Clone snapshots
                    
                -n <new_cloned_volumes_prefix_name> 
                    used in conjunction with -C, specifies the 
                
        -r <pg snapshot name>
                Restores a given snapshot to source volumes. e.g. if the PG
                snapshot is SNAPSHOT.FRANZ, it was created from the 
                protection group SNAPSHOT, containing snapshots of the 
                devices (SNAPSHOT.SNAPSHOT_SITE1_0000, 
                SNAPSHOT.FRANZ.SNAPSHOT_SITE1_0001, ...)
                
        -D <protection group name>
                Select a protection group name that you wish to add drives to
                
        -d <count of new devices>
                The number of devices to be added


    ERROR_CODES:
        1: No parameters given
        2: Authentication problem, or Pure array communication error

    EXAMPLES:
        $0 -i 4.2.2.3 -u xyz -t 967adc3d-29ee-1228-6158-7e3ca33fb198 -DF '^ *ora'
        
        Create a new snapshot:
        $0 -t 967adc3c-29be-1118-6158-7e3ca31fb198 -i purehost.it.domain \
           -S CGROUPNAME -s 'snapp'
        $0 -t 967adc3c-29be-1118-6158-7e3ca31fb198 -i purehost.it.domain \
           -l snap_pg
        
        Clone a snapshot set (the whole protection group):
        <-C argument>.<NEW_DISKS_PREFIX_xxxx> -------------->
            <-n argument>_xxxx where xxxx is the seq number read from source
                                  and appended to the new name
        $0 -t 967adc3c-29be-1118-6158-7e3ca31fb198 -i purehost.it.domain \
           -C CGROUP.snapp -n NEW_DISKS_PREFIX
        
        Add drives
        $0 
"

_ERROR_BOX="
--------------------------------------------------------------------------------
|################################  ERROR  #####################################|
--------------------------------------------------------------------------------
"

_DIVIDER="-------------------------------------------------------------------------------"

#-------------------------------------------------------------------------------
# Functions
#-------------------------------------------------------------------------------
########################### GENERIC ############################################
# As authentification uses cookies to store sessions in order to call commands,
# cookies must be written to disk to ./auth.txt
function auth () {
    # Need to store debug output to get the session cookie
    _AUTH_RESULT=`wget --no-check-certificate -dO- \
                       https://$_PURE_IP/api/1.8/auth/session \
                       --post-data='{"api_token":"'$_PURE_TOKEN'"}' \
                       --header="Content-Type: application/json" 2>&1`
    _AUTH_ERROR=`echo "$_AUTH_RESULT" | grep '"msg":'`
    _AUTH_USER=`echo "$_AUTH_RESULT" | grep '^{'`
    _AUTH_COOKIE=`echo "$_AUTH_RESULT" | grep Set- |\
                                         awk -F\; '{print $1}' |\
                                         sed 's/Set-Cookie: //g'`
}

function deAuth () {
    curl -k -X DELETE -b $_AUTH_COOKIE https://$_PURE_IP/api/1.8/auth/session
}

function generateToken () {
    _TOKEN_RESULT=`wget --no-check-certificate -dO- \
                        "https://$_PURE_IP/api/1.8/auth/apitoken" \
                        --header "Content-Type: application/json" \
                        --post-data='{"password": "'"$_PURE_PASS"'",
                                      "username": "'"$_PURE_USER"'"}' 2>&1`
    _TOKEN_ERROR=`echo "$_TOKEN_RESULT" | grep '"msg":'`
}

function wget_get () {
    wget --no-check-certificate -qO- \
    "https://$_PURE_IP/api/1.8/$1" \
    --header "Content-Type: application/json" \
    --header "Cookie: $_AUTH_COOKIE"
}

function wget_post () {
    _PURE_POST_REQUEST=$1
    _PURE_POST_DATA=$2
    wget --no-check-certificate -qO- \
    "https://$_PURE_IP/api/1.8/$_PURE_POST_REQUEST" \
    --header "Content-Type: application/json" \
    --post-data='{'$_PURE_POST_DATA'}' \
    --header "Cookie: $_AUTH_COOKIE"
}

function cleanup () {
    echo "Cleanup"
    if [ -e ./auth.txt ]; then 
        echo "Removing auth cookie file..."
        rm ./auth.txt
        if [ $? == '0' ]; then
            echo "Auth cookie file succesfully deleted"
        else
            echo "Error deleting auth cookie file"
        fi
    else
        echo "Auth cookie not present, not removing"
    fi
}

################################# SPECIFIC #####################################
function json_cleanup () {
    _CLEAN_RESULT=`echo $1 | sed 's/\},/\n\n/g' | sed 's/,/\n/g' | \
                   tr -d '\[\]\{\}\" '`
}

# Obsolete function, prepared for removal
function json_cleanup_oneline(){
    sed 's/\},/\n\n/g' | tr -d '\[\]\{\}\" ' 
}

# Candidate for renaming, replacing the above function
function json_cleanup_oneline_wwn () {
    sed 's/\("[A-F0-9]\{16\}"\),/\1;/g' | \
    sed 's/\},/\n\n/g' | tr -d '\[\]\{\}\" ' | grep -v '^$'
}

# ---------------------------- VOLUMES -----------------------------------------
function awk_port_header () {
    echo "" | awk -F\, '{printf("%8s | %26s | %6s | %7s \n",
                                "name",
                                "wwn", 
                                "portal", 
                                "failover")
                        }'
}

function awk_port_formatter () {
    awk -F\, '{failover=gensub(/[a-z]*:/, "", 1, $2);
               wwn=tolower(gensub(/[a-z]*:/, "", 1, $3));
               portal=gensub(/[a-z]*:/, "", 1, $4);
               name=gensub(/[a-z]*:/, "", 1, $5);
               printf("%8s | %26s | %6s | %7s \n",
                      name, 
                      wwn,
                      portal,
                      failover)
              }'
}

# ---------------------------- VOLUMES -----------------------------------------
function awk_volume_header () {
    echo "" | awk -F\, '{printf("%25s | %26s | %8s | %22s | %s \n",
                                "name",
                                "serial", 
                                "size", 
                                "t_stamp", 
                                "source")
                        }'
}

function awk_volume_formatter () {
    awk -F\, '{source=gensub(/[a-z]*:/, "", 1, $1);
               serial=tolower(gensub(/[a-z]*:/, "", 1, $2));
               t_stamp=gensub(/[a-z]*:/, "", 1, $3);
               name=gensub(/[a-z]*:/, "", 1, $4);
               size=gensub(/[a-z]*:/, "", 1, $5);
               printf("%25s | %26s | %6s G | %22s | %s \n", 
                      name, 
                      serial, 
                      size/1024/1024/1024, 
                      t_stamp, 
                      source)
              }'
}

#------------------------------- HOSTS -----------------------------------------
function awk_host_header () {
    echo "" | awk -F\, '{printf("%68s | %15s | %s \n",
                                "wwn",
                                "name", 
                                "h_group")
                        }'
}

function awk_host_formatter () {
    awk -F\, '{wwn=tolower(gensub(/[a-z]*:/, "", 1, $1));
               name=gensub(/[a-z]*:/, "", 1, $2);
               h_group=gensub(/[a-z]*:/, "", 1, $3);
               printf("%68s | %15s | %s \n", 
                      wwn,
                      name,
                      h_group)
              }'
}

#------------------------------- HOST_MAPS / details ---------------------------
function awk_host_map_header () {
    echo "" | awk -F\, '{printf("%30s | %-4s \n",
                                "vol",
                                "lun")
                        }'
}

function awk_host_map_formatter () {
    awk -F\, '{vol=gensub(/[a-z]*:/, "", 1, $1);
               server=gensub(/[a-z]*:/, "", 1, $2);
               lun=gensub(/[a-z]*:/, "", 1, $3);
               h_group=gensub(/[a-z]*:/, "", 1, $4);
               printf("%30s | %-4s \n", 
                      vol,
                      lun)
              }'
}

#------------------------------- HOST_MAPS / details ---------------------------
awk_snap_pg_header () {
    echo "" | awk -F\, '{printf("%20s | %-33s | %15s \n", 
                                 "src_prot_group",
                                 "snapshot_name",
                                 "tstamp")
                        }'
}

awk_snap_pg_formatter () {
    awk -F\, '{source=gensub(/[a-z]*:/, "", 1, $1);
               name=gensub(/[a-z]*:/, "", 1, $2);
               tstamp=gensub(/[a-z]*:/, "", 1, $3);
               printf("%20s | %-33s | %15s \n", 
                      source,
                      name,
                      tstamp)
              }'
}
#------------------------------- SNAPSHOT in PROTGROUP -------------------------
awk_snap_formatter () {
    awk -F\, '{source=gensub(/[a-z]*:/, "", 1, $1);
               serial=gensub(/[a-z]*:/, "", 1, $2);
               tstamp=gensub(/[a-z]*:/, "", 1, $3);
               name=gensub(/[a-z]*:/, "", 1, $4);
               size=gensub(/[a-z]*:/, "", 1, $5);
               printf("%20s | %-35s | %20s | %35s | %15s \n", 
                      source,
                      serial,
                      tstamp,
                      name,
                      size)
              }'
}

awk_snap_extractor () {
    awk -F\, '{name=gensub(/[a-z]*:/, "", 1, $4);
               print name
              }'
}
#----------------------------- PERFORMANCE -------------------------------------
awk_perf_header () {
    echo "" | awk -F\, '{printf("%10s | %10s | %8s | %8s | %8s | %8s | %11s | %11s | %4s \n", 
                                "Date",
                                "Time",
                                "Wr / s",
                                "Read / s",
                                "Lat WR",
                                "Lat RD",
                                "Out / s",
                                "In / s",
                                "Q depth")}'
    echo "" | awk -F\, '{printf("%10s | %10s | %8s | %8s | %8s | %8s | %11s | %11s | %4s \n", 
                                " ",
                                " ",
                                "[IO]",
                                "[IO]",
                                "[us/IO]",
                                "[us/IO]",
                                "[GB]",
                                "[GB]",
                                "[#]")}'
    }
                                
awk_perf_formatter () {
    awk -F\, '{writes_per_sec=gensub(/[a-z_]*:/, "", 1, $1);
               usec_per_write_op=gensub(/[a-z_]*:/, "", 1, $2);
               output_per_sec=gensub(/[a-z_]*:/, "", 1, $3);
               reads_per_sec=gensub(/[a-z_]*:/, "", 1, $4);
               input_per_sec=gensub(/[a-z_]*:/, "", 1, $5);
               tstamp=gensub(/[a-z_]*:/, "", 1, $6);
               date=gensub(/^(.+)T.*/, "\\1", 1, tstamp);
               time=gensub(/.*T(.+)Z/, "\\1", 1, tstamp);
               usec_per_read_op=gensub(/[a-z_]*:/, "", 1, $7);
               queue_depth=gensub(/[a-z_]*:/, "", 1, $8);
               printf("%10s | %10s | %8s | %8s | %8s | %8s | %11s | %11s | %4s \n", 
                      date, time,
                      writes_per_sec,
                      reads_per_sec,
                      usec_per_read_op,
                      usec_per_write_op,
                      output_per_sec / 1024 / 1024 /1024,
                      input_per_sec / 1024 / 1024 / 1024,
                      queue_depth)}'
    }
#----------------------------- MAPPING in VOLUME ADD ---------------------------
awk_map_formatter_voladd () {
    awk -F\, '{host=gensub(/[a-z]*:/, "", 1, $1);
               serial=gensub(/[a-z]*:/, "", 1, $2);
               tstamp=gensub(/[a-z]*:/, "", 1, $3);
               name=gensub(/[a-z]*:/, "", 1, $4);
               size=gensub(/[a-z]*:/, "", 1, $5);
               printf("%20s | %-35s | %20s | %35s | %15s \n", 
                      source,
                      serial,
                      tstamp,
                      name,
                      size)
              }'
}

################################################################################
########################### OPTS / ARGS ########################################
################################################################################
if [ $# = 0 ]; then
    echo "$USAGE"
    exit 1;
fi

while getopts "hl:i:u:t:f:S:s:C:n:r:D:d:" optname; do
    case $optname in
        "h")
            echo "$USAGE"
            exit 0
            ;;
        "i")
            _PURE_IP=$OPTARG
            ;;
        "l")
            _LIST=1
            _LIST_MODE=$OPTARG
            case $OPTARG in 
                "snap_pg")
                    _LIST_SNAPSHOTS_PG=1
                    ;;
                "vols")
                    _SHOW_VOLUMES=1
                    ;;
                "msg")
                    _SHOW_MESSAGES=1
                    ;;
                "info")
                    _SHOW_INFO=1
                    ;;
                "maps")
                    _SHOW_MAPPING=1
                    ;;
                "ports")
                    _SHOW_PORTS=1
                    ;;
                "perf")
                    _PERF=1
                    ;;
            esac
            ;;
        "u")
            _PURE_USER=$OPTARG
            ;;
        "t")
            _PURE_TOKEN=$OPTARG
            ;;
        "f")
            _VOLUMES_FILTER=$OPTARG
            _HOST_DETAILS=$OPTARG
            _PERF_PERIOD=$OPTARG
            ;;            
        "S")
            _CREATE_SNAP_PG=1
            _SNAP_PG=$OPTARG
            ;; 
        "s")
            _PG_SNAP_SUFFIX=$OPTARG
            ;;   
        "C")
            _CLONE_SNAPS=1
            _SNAP_PG=$OPTARG
            ;; 
           
        "n")
            _NEW_CLONE_PREFIX=$OPTARG
            ;;
        "r")
            _SNAPSHOT_RESTORE=1
            _SNAP_PG=$OPTARG
            ;;
        "D")
            _CREATE_DEVICES=1
            _CREATE_DEVICES_PGROUP=$OPTARG
            ;;
        "d")
            _CREATE_DEVICES_COUNT=$OPTARG
            ;;
            \?)
            echo "Invalid option: -$OPTARG" >&2
            #exit 1
            ;;
    esac
done


################################################################################
################################### MAIN #######################################
################################################################################
echo $_DIVIDER
################################### AAA ########################################
#-------------------------------------------------------------------------------
# Establish session
# Is sesstion via token, or user and password?
if [ "x$_PURE_USER" != "x" ]; then
    echo "Authenticating interactively, as $_PURE_USER"
    echo "Pure Password:"
    read -s _PURE_PASS
    echo "Getting API token:"
    generateToken
    echo $_DIVIDER
    if [ $? != '0' ]; then
        echo "Error reaching Pure storage"
        exit 2
    else
        if [ "x$_TOKEN_ERROR" != "x" ]; then
            echo "$_TOKEN_ERROR"
            exit 3
        else
            _PURE_TOKEN=`echo "$_TOKEN_RESULT" | grep '^{' |\
                                                  sed 's/[{}\"\ ]//g' |\
                                                  awk -F\: '{ print $2 }'`
            echo "$_PURE_TOKEN"
            echo "$_DIVIDER"
        fi
    fi
else    
    echo "Authenticating with token"
fi    
auth
if [ "x$_AUTH_ERROR" != 'x' ]; then
    echo "$_ERROR_BOX"
    echo "User authentication error, AAA exited with: $_AUTH_ERROR" >&2
    echo "$AUTH_RAW"
    exit 2
else
    echo "Authenticated User:"
    json_cleanup "$_AUTH_USER"; echo "$_CLEAN_RESULT" | awk -F\: '{print $2}'
fi
echo $_DIVIDER
#-------------------------------------------------------------------------------

############################ BASIC ARRAY / POOL INFO ###########################
#-------------------------------------------------------------------------------
if [ $_SHOW_INFO ]; then
    # We want to have some basic info
    ARRAY_INFO=`wget_get 'array'`
    json_cleanup "$ARRAY_INFO"; echo "$_CLEAN_RESULT"
    echo $_DIVIDER
#-------------------------------------------------------------------------------
    # And of course the free and used space information
    SPACE_RAW=`wget_get 'array?space=true'`
    json_cleanup "$SPACE_RAW"; echo "$_CLEAN_RESULT"
    echo $_DIVIDER
fi

###################### Do we like ports list? Yes we do! #######################
if [ $_SHOW_PORTS ]; then
    PORTS_RAW=`wget_get 'port'`
    json_cleanup "$PORTS_RAW"
    awk_port_header
    echo $_DIVIDER
    echo "$PORTS_RAW" | json_cleanup_oneline | grep -v '^$' | \
    awk_port_formatter 
    echo $_DIVIDER
fi

######################## And who wants to see the volumes? #####################
if [ $_SHOW_VOLUMES ]; then
    VOLUMES_RAW=`wget_get 'volume'`
    _MACHINE_LIST=`echo "$VOLUMES_RAW" | json_cleanup_oneline | grep -v '^$'`
    awk_volume_header 
    echo "$_DIVIDER-------------------"
    if [ "x$_VOLUMES_FILTER" == "x" ]; then
        echo "$_MACHINE_LIST" | awk_volume_formatter
    else
        echo "$_MACHINE_LIST" | awk_volume_formatter | grep "$_VOLUMES_FILTER"
    fi
                            
    #json_cleanup "$VOLUMES_RAW"
    #echo "$_CLEAN_RESULT" | sed 's/^\([a-z]*\):/\1: /g'
    echo $_DIVIDER
fi

###################### Messages section, legacy checks of array ################
if [ $_SHOW_MESSAGES ]; then
    MESSAGES_RAW=`wget_get 'message'`
    json_cleanup "$MESSAGES_RAW"
    echo "$_CLEAN_RESULT" | sed 's/^\([a-z]*\):/\1: /g'
    echo $_DIVIDER
fi

######################### Let's ge the mappings, shall we? #####################
if [ $_SHOW_MAPPING ]; then
    HOSTS_RAW=`wget_get 'host'`
    awk_host_header
    echo "$_DIVIDER-------------------"
    _MACHINE_LIST=`echo "$HOSTS_RAW" | json_cleanup_oneline_wwn | grep -v '^$' |\
                   sed 's/iqn:,//g' | sed 's/,/, /g'`
    echo "$_MACHINE_LIST" | awk_host_formatter
    if [ $_HOST_DETAILS ]; then
        json_cleanup "$HOSTS_RAW" 
        FILTERED_MACHINE_LIST=`echo "$_MACHINE_LIST" | grep -i "$_HOST_DETAILS"`
        DESIRED_HOSTS=`echo "$FILTERED_MACHINE_LIST" | awk -F, '{print $2}' |\
                       sed 's/^.*://g'`
        #echo "$FILTERED_MACHINE_LIST"
        #echo "$DESIRED_HOSTS"
        for host in $DESIRED_HOSTS; do
            echo $_DIVIDER
            echo $host
            awk_host_map_header
            echo $_DIVIDER
            HOST_DETAILS_RAW=`wget_get "host/$host/volume"`
            _MACHINE_LIST_DETAIL=`echo "$HOST_DETAILS_RAW" | \
                                  json_cleanup_oneline_wwn` 
            echo "$_MACHINE_LIST_DETAIL" | awk_host_map_formatter
        done
    fi
fi

#############################  List snapshots  #################################
if [ $_LIST_SNAPSHOTS_PG ]; then 
    SNAPSHOTS_RAW=`wget_get 'pgroup?snap=true'`
    awk_snap_pg_header
    echo $_DIVIDER
    _MACHINE_LIST=`echo "$SNAPSHOTS_RAW" | json_cleanup_oneline | grep -v '^$'`
    echo "$_MACHINE_LIST" | awk_snap_pg_formatter
fi

#################### Create a snapshot of a Protection Group ###################
if [ $_CREATE_SNAP_PG ]; then 
    POST_REQUEST='"snap":true,"source":["'$_SNAP_PG'"],"suffix":"'$_PG_SNAP_SUFFIX'"'
    echo $POST_REQUEST
    POST_RAW=`wget_post 'pgroup' "$POST_REQUEST"`
    echo $POST_RAW
    
fi

############################ SNAPSHOTS section here ############################
# Get a list of snapshots from the protection group
if [ $_CLONE_SNAPS ]; then
    SNAPSHOTS_RAW=`wget_get "volume?snap=true&pgrouplist=$_SNAP_PG"`
    _MACHINE_LIST=`echo "$SNAPSHOTS_RAW" | json_cleanup_oneline | grep -v '^$'`
    #echo "$_MACHINE_LIST" | awk_snap_formatter
    SNAPSHOTS=`echo "$_MACHINE_LIST" | awk_snap_extractor `
    for snapshot in $SNAPSHOTS; do
        NEW_CLONE_SUFFIX=`echo $snapshot | awk -F\_ '{print $3}'`
        NEW_CLONE="$_NEW_CLONE_PREFIX"_"$NEW_CLONE_SUFFIX"
        POST_REQUEST='"source":"'$snapshot'","overwrite":"true"'
        #echo "wget_post \"volume/$NEW_CLONE\" \"$POST_REQUEST\""
        RESULT=`wget_post "volume/$NEW_CLONE" "$POST_REQUEST"`
        echo $RESULT
        sleep 1
    done
    #echo $SNAPSHOTS
    POST_REQUEST=''
    
fi

############################ SNAPSHOT restore only #############################
# Get a list of snapshots from the protection group, then restore it to whatever
# source volumes are defined here
if [ $_SNAPSHOT_RESTORE ]; then
    SNAPSHOTS_RAW=`wget_get "volume?snap=true&pgrouplist=$_SNAP_PG"`
    _MACHINE_LIST=`echo "$SNAPSHOTS_RAW" | json_cleanup_oneline | grep -v '^$'`
    #echo "$_MACHINE_LIST" | awk_snap_formatter
    SNAPSHOTS=`echo "$_MACHINE_LIST" | awk_snap_extractor `
    for snapshot in $SNAPSHOTS; do
        NEW_CLONE_SUFFIX=`echo $snapshot | sed ''`
        VOLUME_NAME=`echo $snapshot | sed 's/.*\.//g'`
        #echo "$VOLUME_NAME"
        NEW_CLONE="$VOLUME_NAME"
        POST_REQUEST='"source":"'$snapshot'","overwrite":"true"'
        #echo "wget_post \"volume/$NEW_CLONE\" \"$POST_REQUEST\""
        COMMANDS="$COMMANDS
        wget_post volume/$NEW_CLONE $POST_REQUEST"
    done
    echo "$COMMANDS" | sed 's/wget_post/Restore/g' | sed 's/\"//g' |\
                       sed 's/,.*$//g' | sed 's/source:/ <<- From snapshot: /g'
    echo "If the above lines seem accurate and represent what you intend to do,"
    echo "please type in 'yes'"
    read response
    COMMANDS=`echo "$COMMANDS" | sed 's/\ /;/g'`
    echo $_DIVIDER
    echo "Frame response:"
    if [ $response == 'yes' ]; then
        for command in $COMMANDS; do
            to_execute=`echo $command | sed 's/;/\ /g'`
            echo $to_execute
            RESULT=`$to_execute`
            echo "$RESULT"
            sleep 1
        done
    else
        echo "Cancelling!"
    fi
    #echo $SNAPSHOTS
    POST_REQUEST=''
fi

########################## VOLUMES, more, add more #############################
# If we need to add more devices to a diskgroup, need to ensure there is a 
# script creates them, ads them to the correct host group and protection group
# not happy with how it maps the volumes. It doesn't!!!
if [ $_CREATE_DEVICES ]; then 
    VOLUMES_RAW=`wget_get 'volume'`
    VOLUMES_RAW=`wget_get volume?connect=true`
    _MACHINE_LIST=`echo "$VOLUMES_RAW" | json_cleanup_oneline | grep -v '^$'`
    _VOLUME_LIST=`echo "$_MACHINE_LIST" | \
                  awk -F, '{print $4}' | \
                  grep "$_CREATE_DEVICES_PGROUP" | \
                  awk -F\: '{print $2}' | sort`
    VOL_DET=`wget_get volume?connect=true`
    #echo "$VOL_DET" | json_cleanup_oneline | grep -v '^$' | grep $_CREATE_DEVICES_PGROUP
    echo "Current devices with selected search pattern:"
    echo "$_VOLUME_LIST"
    VOLUME_NAME_PREFIX=`echo "$_VOLUME_LIST" | tail -1 | sed 's/_[0-9]*$//g'`
    echo $_DIVIDER
    echo "Volume name prefix is: $VOLUME_NAME_PREFIX"
    LAST_VOLUME=`echo "$_VOLUME_LIST" | tail -1 `
    LAST_VOLUME_NUMBER=`echo $LAST_VOLUME | sed 's/.*_\([0-9]*\)/\1/g'`
    LAST_VOLUME_DETAILS=`wget_get volume/$LAST_VOLUME?protect=true`
    PGROUP_FOR_NEW_VOLS=`echo $LAST_VOLUME_DETAILS | \
                         json_cleanup_oneline | \
                         awk -F, '{print $2}' | \
                         awk -F\: '{print $2}'`                     
    echo "Last volume number: $LAST_VOLUME_NUMBER"
    echo "These $_CREATE_DEVICES_COUNT new volumes will be added to"
    echo "protection group: $PGROUP_FOR_NEW_VOLS"
    echo ""
    echo "Size for new volumes (1G | 1M | 1T):"
    read new_vol_size
    echo ""
    echo "New volumes to be added:"
    volume=1
    while [ $_CREATE_DEVICES_COUNT -ge $volume ]; do
        volume_suffix=`expr $LAST_VOLUME_NUMBER + $volume`
        volume_suffix=`printf "%04d\n" $volume_suffix`
        new_volume_name="$VOLUME_NAME_PREFIX"_"$volume_suffix"
        echo $new_volume_name
        POST_REQUEST='"size":"'$new_vol_size'"'
        COMMANDS="$COMMANDS
        wget_post volume/$new_volume_name $POST_REQUEST"
        PG_ADD_COMMANDS="$PG_ADD_COMMANDS
        wget_post volume/$new_volume_name/pgroup/$PGROUP_FOR_NEW_VOLS"
        HOST_MAP_COMMANDS="$HOST_MAP_COMMANDS
        wget_post hgroup/$host_group/volume/$new_volume_name"
        volume=`expr $volume + 1`
    done 
    echo $_DIVIDER
    echo "If the above looks OK, please type in 'yes'"
    read response
    COMMANDS=`echo "$COMMANDS" | sed 's/\ /;/g'`
    PG_ADD_COMMANDS=`echo "$PG_ADD_COMMANDS" | sed 's/\ /;/g'`
    echo $_DIVIDER
    echo "Frame response:"
    if [ $response == 'yes' ]; then
        for command in $COMMANDS; do
            to_execute=`echo $command | sed 's/;/\ /g'`
            echo $to_execute
            RESULT=`$to_execute`
            echo "$RESULT"
            sleep 1
        done
        for command in $PG_ADD_COMMANDS; do
            to_execute=`echo $command | sed 's/;/\ /g'`
            echo $to_execute
            RESULT=`$to_execute`
            echo "$RESULT"
            sleep 1
        done
    else
        echo "Cancelling!"
    fi
fi

############################ Performance? ######################################
# Get a list of snapshots from the protection group
if [ $_PERF ]; then
    PERFORMANCE_RAW=`wget_get "array?action=monitor&historical=$_PERF_PERIOD"`
    _MACHINE_LIST=`echo "$PERFORMANCE_RAW" | json_cleanup_oneline | grep -v '^$'`
    awk_perf_header
    echo "$_DIVIDER-----------------------"
    echo "$_MACHINE_LIST" | awk_perf_formatter
fi

################################ Deauth Session ################################
echo $_DIVIDER
echo "Deleting auth session"
deAuth
echo ""
if [ $? == '0' ]; then
    echo "Deauth succesfull"
else
    echo $_ERROR_BOX
    echo "Problem with DeAuth process, session is still active."
fi
echo $_DIVIDER
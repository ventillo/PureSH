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
#   DONE - Volume detail, finish it.

VERSION="0.9"
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
           -u <user> 
           -t <token>

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

        -P      Port information

        -D      Disk / volume information
            -f <regexp>      
                Filtering option (REGEXP). Used in conjunction with -D

        -I      Basic array info, including pool occupancy

        -m      Messages, logging and auditing

        -H      Host listing
            -d  <regexp>    
                Detailed listing for (a) specific host(s)


    ERROR_CODES:
        1: No parameters given
        2: Authentication problem, or Pure array communication error

    EXAMPLES:
        $0 -i 4.2.2.3 -u xyz -t 967adc3d-29ee-1228-6158-7e3ca33fb198 -DF '^ *ora'
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
function wget_get(){
    wget --no-check-certificate -qO- \
    "https://$_PURE_IP/api/1.8/$1" \
    --header "Content-Type: application/json" \
    --load-cookies auth.txt
}

# As authentification uses cookies to store sessions in order to call commands,
# cookies must be written to disk to ./auth.txt
function auth(){
   wget --no-check-certificate -qO- \
    https://$_PURE_IP/api/1.8/auth/session \
    --header "Content-Type: application/json" \
    --post-data='{"api_token":"'$_PURE_TOKEN'"}' \
    --save-cookies auth.txt
}

function cleanup(){
    echo "Cleanup"
}

################################# SPECIFIC #####################################
function json_cleanup(){
    _CLEAN_RESULT=`echo $1 | sed 's/\},/\n\n/g' | sed 's/,/\n/g' | \
                   tr -d '\[\]\{\}\" '`
}

# Obsolete function, prepared for removal
function json_cleanup_oneline(){
    sed 's/\},/\n\n/g' | tr -d '\[\]\{\}\" ' 
}

# Candidate for renaming, replacing the above function
function json_cleanup_oneline_wwn(){
    sed 's/\("[A-F0-9]\{16\}"\),/\1;/g' | \
    sed 's/\},/\n\n/g' | tr -d '\[\]\{\}\" ' | grep -v '^$'
}

# ---------------------------- VOLUMES -----------------------------------------
function awk_port_header(){
    echo "" | awk -F\, '{printf("%8s | %26s | %6s | %7s \n",
                                "name",
                                "wwn", 
                                "portal", 
                                "failover")
                        }'
}

function awk_port_formatter(){
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
function awk_volume_header(){
    echo "" | awk -F\, '{printf("%25s | %26s | %8s | %22s | %s \n",
                                "name",
                                "serial", 
                                "size", 
                                "t_stamp", 
                                "source")
                        }'
}

function awk_volume_formatter(){
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
function awk_host_header(){
    echo "" | awk -F\, '{printf("%68s | %15s | %s \n",
                                "wwn",
                                "name", 
                                "h_group")
                        }'
}

function awk_host_formatter(){
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
function awk_host_map_header(){
    echo "" | awk -F\, '{printf("%30s | %-4s \n",
                                "vol",
                                "lun")
                        }'
}

function awk_host_map_formatter(){
    awk -F\, '{vol=tolower(gensub(/[a-z]*:/, "", 1, $1));
               server=gensub(/[a-z]*:/, "", 1, $2);
               lun=gensub(/[a-z]*:/, "", 1, $3);
               h_group=gensub(/[a-z]*:/, "", 1, $4);
               printf("%30s | %-4s \n", 
                      vol,
                      lun)
              }'
}

################################################################################
########################### OPTS / ARGS ########################################
################################################################################
if [ $# = 0 ]; then
    echo "$USAGE"
    exit 1;
fi

while getopts "hi:u:t:PDf:ImHd:" optname; do
    case $optname in
        "h")
            echo "$USAGE"
            exit 0
            ;;
        "i")
            _PURE_IP=$OPTARG
            ;;
        "u")
            _PURE_USER=$OPTARG
            ;;
        "t")
            _PURE_TOKEN=$OPTARG
            ;;
        "P")
            _SHOW_PORTS=1
            ;;
        "D")
            _SHOW_VOLUMES=1
            ;;
        "f")
            _VOLUMES_FILTER=$OPTARG
            ;;            
        "I")
            _SHOW_INFO=1
            ;;
        "H")
            _SHOW_MAPPING=1
            ;;
        "d")
            _HOST_DETAILS=$OPTARG
            ;;
        "m")
            _SHOW_MESSAGES=1
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
AUTH_RAW=`auth`
AUTH_RESPONSE=$?
if [ $AUTH_RESPONSE -ne '0' ]; then
    echo "$_ERROR_BOX"
    echo "User authentication error, AAA exited with: $AUTH_RESPONSE" >&2
    echo "$AUTH_RAW"
    exit 2
else
    echo "Authenticated User:"
    json_cleanup "$AUTH_RAW"; echo "$_CLEAN_RESULT" | awk -F\: '{print $2}'
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
    awk_volume_header 
    echo "$_DIVIDER-------------------"
    if [ "x$_VOLUMES_FILTER" == "x" ]; then
        echo "$VOLUMES_RAW" | json_cleanup_oneline_wwn |\
                            grep -v '^$' | awk_volume_formatter
    else
        echo "$VOLUMES_RAW" | json_cleanup_oneline_wwn |\
                            grep -v '^$' | awk_volume_formatter |\
                            grep "$_VOLUMES_FILTER"
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

############################ NEXT section here #################################

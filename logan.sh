#!/usr/bin/env bash

###################################################################################
##
##  Log analyzer
##
## @author Mark Torok
## @email
##
## 1. Dec. 2016.
##
###################################################################################


###################################################################################
##
## Help
##  -D : date filtering
##  -T : time filtering
##  -S : severity filtering
##  -M : error messaga filtering
##
## Good to know:
##  * -M has to be the last option, it can contain white spaces
##  * The order and the multiplicity of -D, -T, -S are irrelevant.
##    The last one will be chosen
##
## Usage:
##  * logan.sh -D2012-12-08 : it seeks all loglines with this match in date column
##  * logan.sh -D2012-12-* -SSEVERE : it seeks all lines in all days in Dec.2012. with SEVERE level
##  * logan.sh -D2012-12-* -D2012-12-08 : it takes all lines matching on 08.Dec.2012
##  * logan.sh -T12:*:* -D2012-12-* : it takes all lines matching on Dec.2012 between noon and 1PM
##  * logan.sh -MError message comes here : it seeks all lines matching on "Error message comes here"
##  * logan.sh -MError msg -D2012-12-12 : it seeks "Error msg -D2012-12-12"
##
###################################################################################

set -f
set -e
set -u

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'


###################################################################################
##
## The bodyguard, aka utils!
##
###################################################################################
error_exit() {
    echo "$1" 1>&2
    exit 1
}

console_log() {
    echo ":::   $1" >&2
}

starts_with() {
    local retval=""
    if [[ $1 == $2* ]]; then
        retval="true"
    else
        retval="false"
    fi
    echo "$retval"
}

length_of() {
    local STR="$1"
    echo "${#STR}"
}

index_of() {
    local STR="$1"
    local SUB="$2"

    local retval="${STR%%$SUB*}"
    [[ "$retval" = "$STR" ]] && echo -1 || echo "${#retval}"
}

last_index_of() {
    STR="$1"
    CHR="$2"
    rem="${STR##*$CHR}"
    l_idx=$(( ${#STR}-${#rem} ))
    echo "$l_idx"
}

substr() {
    STR="$1"
    FROM_IDX="$2"
    LEN=""
    retval=""
    if [[ "${#@}" == "3" ]]; then
        LEN="$3"
        retval=`expr substr "$STR" $FROM_IDX $LEN`  # alternatively retval="${STR:FROM_IDX:LEN}"
    else
        retval="${STR:FROM_IDX}"
    fi
    echo "$retval"
}

is_number() {
    re='^[0-9]+$'
    retval=""
    if [[ $1 =~ $re ]] ; then
        retval="true"
    else
        retval="false"
    fi
    echo "$retval"
}

is_range_valid() {
    VALUE=$1
    TOP=$2
    BOTTOM=$3
    retval=""
    res=$(is_number "$VALUE")
    if [ $res == "true" ]; then
        if [ $VALUE -ge $TOP -a $VALUE -le $BOTTOM ]; then
            retval="true"
        else
            retval="false"
        fi
    else
        if [ "$VALUE" == "*" ]; then
            retval="true"
        else
            retval="false"
        fi
    fi
    echo "$retval"
}

get_value() {
    local KEY="$1"
    local ARGS="$2"
    local crits=""
    local crit=""
    local retval=""

    IFS='|||' read -r -a crits <<< "$ARGS"
    for crit in "${crits[@]}"; do
        if [[ "$crit" == "" ]]; then
            continue  # ugly but necessary solution to skip empty elements
        fi
        local idx=$( index_of "$crit" ":" )
        local key=$( substr "$crit" 1 $idx )
        if [[ ! "$KEY" == "$key" ]]; then
            continue
        fi
        local diff=$(( ${#crit}-idx ))
        retval=$( substr "$crit" $(( idx+2 )) $diff )
        break;
    done

    echo "$retval"
}

###################################################################################
##
## Arguments parsing and processing
##
## Including date and time parsing
##
###################################################################################

date_validator() {
    IFS='-' read -r -a DATE <<< "$1"
    retval=""
    if [ ${#DATE[@]} == "3" ]; then
        year=${DATE[0]}
        month=${DATE[1]}
        day=${DATE[2]}

        res_year=$(is_range_valid "$year" 2000 2040)
        if [ ! "$res_year" == "true" ]; then
            error_exit "Invalid Year: $year"
        fi

        res_month=$(is_range_valid "$month" 1 12)
        if [ ! "$res_month" == "true" ]; then
            error_exit "Invalid Month: $month"
        fi

        res_day=$(is_range_valid "$day" 1 31)
        if [ ! "$res_day" == "true" ]; then
            error_exit "Invalid Day: $day"
        fi
    else
        error_exit "Not valid date format! Should be 2016-12-06"
    fi

    echo "$year-$month-$day"
}

time_validator() {
    IFS=':' read -r -a TIME <<< "$1"
    retval=""
    if [ ${#TIME[@]} == "3" ]; then
        hour=${TIME[0]}
        min=${TIME[1]}
        sec=${TIME[2]}

        res_hour=$(is_range_valid "$hour" 0 23)
        if [ ! "$res_hour" == "true" ]; then
            error_exit "Invalid Hour: $hour"
        fi

        res_min=$(is_range_valid "$min" 0 59)
        if [ ! "$res_min" == "true" ]; then
            error_exit "Invalid Min: $min"
        fi

        res_sec=$(is_range_valid "$sec" 0 59)
        if [ ! "$res_sec" == "true" ]; then
            error_exit "Invalid Sec: $sec"
        fi
    else
        error_exit "Not valid time format! Should be 17:54:12"
    fi

    echo "$hour:$min:$sec"
}

severity_validator() {
    local LEVEL="$1"
    local severity_list=("INFO" "WARNING" "SEVERE")
    if [[ ! " ${severity_list[@]} " =~ "${LEVEL}" ]]; then
        error_exit "Not valid severity level: $LEVEL! Should be INFO, WARNING, SEVERE"
    fi
    echo "$LEVEL"
}

text_validator() {
    local TEXT="$1"
    local length=$( length_of "$TEXT" )
    if [[ $length -gt 60 ]]; then
        error_exit "Too long text argument: $length! No more than 60"
    fi
    echo "$TEXT"
}

argument_validator() {
    local ARGS="$@"
    local date_pattern=""
    local time_pattern=""
    local severity_pattern=""
    local text_pattern=""
    local result=""
    local text_arg=""

    local filter_args=$( echo ${ARGS%-M*} )

    local idx=$( index_of "$ARGS" "-M" )
    if [[ ! "$idx" == -1 ]]; then
        text_arg=$( substr "$ARGS" $(( idx+=2 )) ) # remove -M; ugly, fix it!
    fi

    for arg in $filter_args; do
        local retval=$( starts_with "$arg" "-D" )
        if [[ "$retval" == "true" ]]; then
            local raw_date=$( echo ${arg#"-D"} )
            date_pattern=$( date_validator "$raw_date" )
            continue
        fi

        retval=$( starts_with "$arg" "-T" )
        if [[ "$retval" == "true" ]]; then
            local raw_time=$( echo ${arg#"-T"} )
            time_pattern=$( time_validator "$raw_time" )
            continue
        fi

        retval=$( starts_with "$arg" "-S" )
        if [[ "$retval" == "true" ]]; then
            local raw_severity=$( echo ${arg#"-S"} )
            severity_pattern=$( severity_validator "$raw_severity" )
            continue
        fi

        error_exit "Invalid or not existing option: $arg"
    done

    text_pattern=$( text_validator "$text_arg" )

    if [ ! -z "$date_pattern" ]; then
        result+="date:$date_pattern|||"
    fi
    if [ ! -z "$time_pattern" ]; then
        result+="time:$time_pattern|||"
    fi
    if [ ! -z "$severity_pattern" ]; then
        result+="severity:$severity_pattern|||"
    fi
    if [ ! -z "$text_pattern" ]; then
        result+="text:$text_pattern|||"
    fi
    echo "${result%|||*}" # removes trailing pipes
}


###################################################################################
##
## Building grep and its parameter list
##
###################################################################################
date_builder() {
    local DATE=""
    IFS='-' read -r -a DATE <<< "$1"
    local retval=""
    local year="${DATE[0]}"
    local month="${DATE[1]}"
    local day="${DATE[2]}"

    if [[ "$year" == "*" ]]; then
        year="(20[0-3][0-9]|2040)"
    fi
    retval+="$year-"

    if [[ "$month" == "*" ]]; then
        month="(0[1-9]|1[0-2])"
    fi
    retval+="$month-"

    if [[ "$day" == "*" ]]; then
        day="(0[1-9]|[1-2][0-9]|3[0-1])"
    fi
    retval+="$day"

    echo "$retval"
}

time_builder() {
    local TIME=""
    IFS=':' read -r -a TIME <<< "$1"
    local retval=""
    local hour="${TIME[0]}"
    local min="${TIME[1]}"
    local sec="${TIME[2]}"

    if [[ "$hour" == "*" ]]; then
        hour="([0-1][0-9]|2[0-3])"
    fi
    retval+="$hour:"

    if [[ "$min" == "*" ]]; then
        min="(0[1-9]|[1-5][0-9])"
    fi
    retval+="$min:"

    if [[ "$sec" == "*" ]]; then
        sec="(0[1-9]|[1-5][0-9])"
    fi
    retval+="$sec"

    echo "$retval"

}

severity_builder() {
    local SEVERITY="$1"
    local retval=""

    if [[ "$SEVERITY" == "*" ]]; then
        retval="(INFO|WARNING|SEVERE)"
    else
        retval="$SEVERITY"
    fi
    echo "$retval"
}

text_builder() {
    local ARGS="$1"
    local retval=$( get_value "text" "$ARGS" )
    echo "$retval"
}

to_default() {
    local KEY="$1"
    local retval=""
    case "$KEY" in
        date)
            retval=$( date_builder "*-*-*" )
            ;;
        time)
            retval=$( time_builder "*:*:*" )
            ;;
        severity)
            retval=$( severity_builder "*" )
            ;;
    esac

    echo "$retval"
}

value_format() {
    local KEY="$1"
    local VAL="$2"
    local retval=""
    case "$KEY" in
        date)
            retval=$( date_builder "$VAL" )
            ;;
        time)
            retval=$( time_builder "$VAL" )
            ;;
        severity)
            retval=$( severity_builder "$VAL" )
            ;;
    esac
    echo "$retval"
}

get_replacement() {
    local KEY="$1"
    local ARGS="$2"
    local retval=""

    local val=$( get_value "$KEY" "$ARGS" )
    if [[ ! -z "$val" ]]; then
        retval=$( value_format "$KEY" "$val" )
    else
        retval=$( to_default "$KEY" )
    fi

    echo "$retval"
}

filter_builder() {
    local RAW_ARG_ARR="$1"
    local filter='\\|#{date}T#{time}\\.[0-9]{0,3}\\+0100\\|#{severity}\\|'
    local filter_patterns=("date" "time" "severity")

    for key in "${filter_patterns[@]}"; do
        local val=$( get_replacement "$key" "$RAW_ARG_ARR" )
        filter=$( echo "$filter" | sed -e "s/#{$key}/$val/g" )
    done

    echo "$filter"
}

grep_text_builder() {
    local TEXT="$1"
    local grep_cmd="grep -Hn --color=always -i \"$TEXT\""
    echo "$grep_cmd"
}

grep_filter_builder() {
    local FILTER_ARG_ARR="$1"
    local filter=""
    local cmd=""

    filter=$( filter_builder "$FILTER_ARG_ARR" )
    cmd="grep --color=always --with-filename --line-number -P '$filter'"
    echo "$cmd"
}

iterate_logs() {
    local ARGS="$1"

    local find_cmd='find . -type f -name "*" -print0 | xargs -0 #{grep_command}'
    local grep_filter_command=""

    local valid_args=$( argument_validator "$ARGS" )
    local text_arg=$( text_builder "$valid_args" )
    #console_log "text_arg --- $text_arg"
    local grep_text_command=$( grep_text_builder "$text_arg" )
    #console_log "grep_text_command --- $grep_text_command"

    # TODO : remove these hacks and replace them with proper patterns
    filter_args=$( echo "${valid_args%'text'*}" )
    #console_log "filter_args :: $filter_args"
    if [[ ! -z "$filter_args" ]]; then
        grep_filter_command=$( grep_filter_builder "$filter_args" )
        find_cmd=$( echo "$find_cmd" | sed "s/#{grep_command}/$grep_filter_command/g" )

        if [[ ! -z "$text_arg" ]]; then
            find_cmd+=" | grep --color=always -i \"$text_arg\""
        fi
    else
        find_cmd=$( echo "$find_cmd" | sed "s/#{grep_command}/$grep_text_command/g" )
    fi
    
    #console_log "$find_cmd"

    eval "$find_cmd"
}

if [ "$#" -lt 1 ]; then
    error_exit "Search criteria is mandatory!"
fi

ARGS="$@"
#console_log "=== Test1 :: -D2002-12-12"
#iterate_logs "-D2002-12-12"
#console_log "=== Test2 :: -D2002-12-12 -T12:12:12 -SSEVERE -MHello leo"
#iterate_logs "-D2002-12-12 -T12:12:12 -SSEVERE -MHello leo"
#console_log "=== Test3 :: -Mhola mio"
#iterate_logs "-Mhola mio"

iterate_logs "$ARGS"


set +f

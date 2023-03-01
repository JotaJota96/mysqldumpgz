#!/bin/bash
# 
# This script automates and simplifies the following dump extraction flow and 
# performs additional checks and validations:
# 
# $ mysqldump -u root -p --databases MyDatabase > 20221231.sql
# $ chown user:user 20221231.sql
# $ gzip 20221231.sql
# $ mv 20221231.sql.gz ~/dumps/
# 
# Author: JotaJota96
# Date: 2023-01-05
# Repository: https://github.com/JotaJota96/mysqldumpgz
#

##################################################
# Configuration
##################################################

# Load the configuration file
readonly CONFIG_FILE_NAME="mysqldumpgz-config.sh"

readonly CONFIG_FILE_PATH="${BASH_SOURCE%/*}/${CONFIG_FILE_NAME}"

if [ -f "$CONFIG_FILE_PATH" ]; then
    source "$CONFIG_FILE_PATH"
else
    echo "ERROR: configuration file $CONFIG_FILE_PATH not found"
    exit 1
fi

##################################################
# Functions
##################################################

#######################################
# Shows the help.
#######################################
function show_help() {
    local script_name
    script_name=$(basename $BASH_SOURCE)

    echo ""
    echo "This script extracts dumps from a database, compresses them and moves them to a folder."
    echo ""
    echo "Use: ${script_name} [-h|-s|--check|--config] [database_flag] [output_file]"
    echo ""
    echo "Options:"
    echo ""
    echo "  --check            Checks if the commands used by the script are available."
    echo "  --config           Shows the configuration."
    echo "  -h,  --help        Shows this help."
    echo "  -s   --simulate    Shows the commands that extract the dump but does not execute them."
    echo "  -y,  --yes         Answers yes to all questions."
    echo ""
    echo "Database selection:"
    echo ""
    echo "  -a,  --all             Extracts the dump of all databases."
    # Show the available databases and align the descriptions
    local max_len=0
    for dbKey in "${DB_KEYS[@]}"; do
        local options_str="${DB_CONFIG[${dbKey}"short_flag"]}, ${DB_CONFIG[${dbKey}"long_flag"]}"
        local len=${#options_str}
        if [[ $len -gt $max_len ]]; then
            max_len=$len
        fi
    done
    for dbKey in "${DB_KEYS[@]}"; do
        local options_str="${DB_CONFIG[${dbKey}"short_flag"]}, ${DB_CONFIG[${dbKey}"long_flag"]}"
        local len=${#options_str}
        local spaces_count=$((max_len - len))
        local spaces
        spaces=$(printf "%*s" ${spaces_count} '')
        echo "  ${options_str}${spaces}    Extrae dump de ${DB_CONFIG[${dbKey}"db_name"]}."
    done
    echo ""
    echo "You can specify the output file as an argument after the database selector option."
    echo ""
}

#######################################
# Prints a colored message.
# Arguments:
#   Message type (cmd, success, warning, error)
#   Message
# Outputs:
#   Writes colored message to stdout, or stderr if the message type is error.
#######################################
function color_print() {
    local type=$1
    local msg=$2
    # If there are not two arguments
    if [[ $# -ne 2 ]]; then
        type="default"
        msg=$1
    fi

    # if STDOUT is attached to TTY
    if [[ -t 1 ]]; then
        default='\033[0m'
        case $type in
            cmd)     echo -e "\033[0;37m\$ ${msg}${default}" ;;      # Gray
            success) echo -e "\033[0;32m${msg}${default}" ;;      # Green
            warning) echo -e "\033[0;33m${msg}${default}" ;;      # Orange
            error)   echo -e "\033[1;31m${msg}${default}"  >&2 ;; # Red
            *)       echo -e "\033[0m${msg}${default}" ;;         # Normal
        esac
    else
        case $type in
            cmd)   echo "$ ${msg}" ;;
            error) echo "${msg}"  >&2 ;;
            *)     echo "${msg}" ;;
        esac
    fi
}

#######################################
# Checks if the commands used by the script are available.
# Globals:
#   EXIT_ERROR_COMMAND_NOT_FOUND
# Arguments:
#   None
# Outputs:
#   Writes colored message to stdout
# Returns:
#   0 if all commands are available, an error code otherwise.
#######################################
function check_script() {
    ret=0

    echo "Color test:"
    color_print         "This is the default color"
    color_print cmd     "This is a command"
    color_print success "This is a success message"
    color_print warning "This is a warning message"
    color_print error   "This is an error message"

    echo "Command test:"
    local commands=("date" "touch" "mysqldump" "readlink" "gzip")
    for command in "${commands[@]}"; do
        if ! $command --version &> /dev/null; then
            color_print error "ERROR: command $command not found"
            ret=$EXIT_ERROR_COMMAND_NOT_FOUND
        fi
    done

    if [ $ret -eq 0 ]; then
        color_print success "OK"
    fi
    return $ret
}

#######################################
# Shows the value of the configuration constants.
# Globals:
#   DB_KEYS
#   DB_CONFIG
#   DEFAULT_DATE_FORMAT
#   DEFAULT_DUMP_FOLDER
#   DEFAULT_ORGANIZE_BY_DATE
#   DEFAULT_DB_USER
#   DEFAULT_SYS_USER
#   DEFAULT_SYS_GROUP
# Arguments:
#   None
# Outputs:
#   Writes the value of the configuration constants to stdout.
#######################################
function show_config() {
   echo 'DB_CONFIG:'
    for dbKey in  "${DB_KEYS[@]}" ; do
        echo  "DB_KEY: ${dbKey}"
        echo  "    short_flag:  ${DB_CONFIG[${dbKey}short_flag]}"
        echo  "    long_flag:   ${DB_CONFIG[${dbKey}long_flag]}"
        echo  "    show_name:   ${DB_CONFIG[${dbKey}show_name]}"
        echo  "    db_name:     ${DB_CONFIG[${dbKey}db_name]}"
        echo  "    file_suffix: ${DB_CONFIG[${dbKey}file_suffix]}"
    done
    echo ""
    # Print all constants whcich start with DEFAULT_
    for var in $(compgen -A variable | grep '^DEFAULT_'); do
        # if DEFAULT_DB_PASSWORD, don't show the value
        if [[ $var == "DEFAULT_DB_PASSWORD" ]]; then
            echo "$var: ********"
        else
            echo "$var: ${!var}"
        fi
    done
}

#######################################
# Check if a file can be created.
# Arguments:
#   File path
# Returns:
#   0 if the file can be created, 1 if the file already exists, 2 if the file is a directory, 3 if the folder doesn't exist.
#######################################
function can_create_file() {
    local file=$1
    file=$(readlink -f "${file}") # get the absolute path
    
    if [ -f "${file}" ]; then # file already exists
        return 1
    elif [ -d "${file}" ]; then # file is a directory
        return 2
    elif touch "${file}" &> /dev/null; then
        # try to create the file, if the file can be created, delete it and return ok
        rm "${file}"
        return 0
    else # Maybe the folder doesn't exist and returns error
        return 3
    fi
}

#######################################
# Ask for confirmation before doing something.
# Arguments:
#   Message
# Returns:
#   0 if the user confirms, 1 if the user cancels.
#######################################
function ask_yes_no() {
    local msg=$1
    read -r -p "${msg} [y/N] " answer
    if [[ $answer =~ ^([yY][eE][sS]|[yY])$ ]]; then
        return 0
    else
        return 1
    fi
}

#######################################
# Shows a spinner while background tasks are running.
# It must be called with & to run it in the background
# Remember to save the PID of the process and kill it when the background tasks finish
# Arguments:
#   None
# Outputs:
#   Writes a spinner to stdout.
#######################################
function show_spinner() {
    local -a spinner_secuence=("|" "/" "-" "\\")
    while true; do
        for c in "${spinner_secuence[@]}"; do
            echo -ne "${c}" && echo -ne "\b"
            sleep 0.1
        done
    done
}

#######################################
# Generic function to extract dumps
# Globals:
#   DB_CONFIG
#   DEFAULT_DUMP_FOLDER
#   DEFAULT_DATE_FORMAT
#   DEFAULT_SYS_USER
#   DEFAULT_SYS_GROUP
# Arguments:
#   Database user
#   Database user password
#   Database configuration key (from DB_KEYS array)
#   True if the dump is really wanted, false if only want to see what would be done
# Outputs:
#   Writes log messages to stdout.
# Returns:
#   0 if the dump was extracted successfully, an error code otherwise.
#######################################
function get_dump() {
    local db_user="$1"
    local db_pass="$2"
    local db_key=$3
    local show_name=${DB_CONFIG[${db_key}show_name]}
    local db_name=${DB_CONFIG[${db_key}db_name]}
    local file_suffix=${DB_CONFIG[${db_key}file_suffix]}
    local dump_folder="${DEFAULT_DUMP_FOLDER}"
    local today
    today=$(date $DEFAULT_DATE_FORMAT)
    # if the configuration specifies to organize the dumps in folders by date
    if [ "${DEFAULT_ORGANIZE_BY_DATE}" = true ]; then
        local year
        local month
        year=$(date +%Y)
        month=$(date +%m)
        dump_folder="${dump_folder}${year}/${month}/"
        # create the folder if it doesn't exist
        if [ ! -d "${dump_folder}" ]; then
            mkdir -p "${dump_folder}"
        fi
    fi
    local file_sql="${dump_folder}${today}${file_suffix}.sql"
    # if the configuration specifies a file name, use it
    if [ "${DB_CONFIG[${db_key}output_file]}" != "" ]; then
        file_sql="${DB_CONFIG[${db_key}output_file]}"
    fi
    local file_gz="${file_sql}.gz"
    local simulate=$4

    # save the commands to execute in variables
    local cmd_mysqldump="mysqldump -u ${db_user} -p${db_pass} --databases ${db_name}"
    local cmd_gzip="gzip ${file_sql}"
    local cmd_chown="chown ${DEFAULT_SYS_USER}:${DEFAULT_SYS_GROUP} ${file_gz}"

    # if the dump is not wanted, only show the commands
    if [ "${simulate}" != false ]; then
        color_print     "Commands to execute to extract the dump of ${db_name}:"
        color_print cmd "${cmd_mysqldump//-p$db_pass/-p******} > $file_sql"
        color_print cmd "${cmd_gzip}"
        color_print cmd "${cmd_chown}"
        return 0
    fi

    # VALIDATIONS

    # check the received parameters
    if [ "${db_user}" == "" ] || [ "${db_pass}" == "" ]; then
        color_print error "ERROR: You must specify the database user and password"
        return $EXIT_ERROR_ARGS
    fi
    if [ "${db_name}" == "" ]; then
        color_print error "ERROR: You must specify the database name"
        return $EXIT_ERROR_ARGS
    fi
    if [ "${file_sql}" == "" ]; then
        color_print error "ERROR: You must specify a valid file name"
        return $EXIT_ERROR_ARGS
    fi

    # check if the files can be created
    if ! can_create_file "${file_sql}"; then
        color_print error "ERROR: The file ${file_sql} already exists or can't be created."
        color_print error "       The dump of ${db_name} won't be extracted"
        return $EXIT_ERROR_ARGS
    fi
    if ! can_create_file "${file_gz}"; then
        color_print error "ERROR: The file ${file_gz} already exists or can't be created."
        color_print error "       The dump of ${db_name} won't be extracted"
        return $EXIT_ERROR_ARGS
    fi

    # EXECUTION

    # extrae dump
    color_print "${show_name}: Extracting dump of ${db_name}..."
    if ! $cmd_mysqldump > "${file_sql}"  ; then
        color_print error "ERROR: An error occurred while trying to extract the dump of ${db_name}"
        # if the dump fails, the file is created anyway, so I delete it
        if [ -f "${file_sql}" ]; then
            rm "${file_sql}"
        fi

        return $EXIT_ERROR_MYSQLDUMP
    fi

    color_print "${show_name}: Compressing the file..."
    if ! $cmd_gzip ; then
        color_print error "ERROR: An error occurred while trying to compress the file ${file_sql}"
        return $EXIT_ERROR_GZIP
    fi

    color_print "${show_name}: Assigning owner to the compressed file..."
    if ! $cmd_chown ; then
        color_print error "ERROR: An error occurred while trying to assign the owner to the file ${file_gz}"
        return $EXIT_ERROR_CHOWN
    fi

    color_print success "${show_name}: Done."
    color_print success "    File: ${file_gz}"
    return 0
}

##################################################
# Main
##################################################

function main() {
    declare -a dbs_to_extract # keys of the databases to extract
    declare -a pids           # PIDs
    local exit_value=0        # exit value
    local simulate=false      # if true, only show the commands to execute
    local db_password=""      # password of the database
    local default_answer_yes=false # if true, answer yes to all questions

    # Check if the script requires and is running as root
    if [ "${REQUIRE_ROOT}" == true ] && [ "${EUID}" -ne 0 ]; then
        color_print error "ERROR: This script must be run as root"
        exit $EXIT_ERROR_USER_NOT_ROOT
    fi

    # if no arguments are passed, show help
    if [[ $# -eq 0 ]]; then
        show_help
        exit 0
    fi

    # Read arguments and do the corresponding actions
    while [[ $# -gt 0 ]]; do
        option="$1"
        value="$2"

        case $option in
        -h | --help) # show help
            show_help
            exit 0
            ;;
        -s | --simulate) # simulate
            simulate=true
            shift
            ;;
        -y | --yes) # answer yes to all questions
            default_answer_yes=true
            shift
            ;;
        --check) # check
            check_script
            exit $?
            ;;
        --config) # show configuration
            show_config
            exit 0
            ;;
        -a | --all) # extract all databases
            dbs_to_extract=("${DB_KEYS[@]}")
            shift
            ;;
        *) # extract specific databases or invalid option
        db_key_finded=false
            for dbKey in "${DB_KEYS[@]}"; do
                if [[ ${option} != "${DB_CONFIG[${dbKey}short_flag]}" && ${option} != "${DB_CONFIG[${dbKey}long_flag]}" ]]; then
                    continue
                fi

                dbs_to_extract+=("${dbKey}")
                db_key_finded=true
                shift
                
                # if a file is specified, use it as output file
                if [[ "${value:0:1}" != "" && "${value:0:1}" != "-" ]]; then
                    DB_CONFIG[${dbKey}"output_file"]=$(readlink -f "${value}")
                    shift
                fi
                break
            done

            if [[ $db_key_finded == false ]]; then
                color_print error "ERROR: Invalid option ${option}"
                color_print error "    Use -h or --help to get help"
                exit $EXIT_ERROR_ARGS
            fi
            ;;
        esac
    done

    # No databases were specified
    if [ ${#dbs_to_extract[@]} -eq 0 ]; then
        color_print error "ERROR: No database was specified"
        color_print error "    Use -h or --help to get help"
        exit $EXIT_ERROR_ARGS
    fi

    # if it is simulating
    if [ $simulate == true ]; then
        # Show the commands to extract each dump
        for dbKey in "${dbs_to_extract[@]}"; do
            get_dump "${DEFAULT_DB_USER}" "${db_password}" "${dbKey}" "${simulate}"
        done
    else
        # If the database password is not specified in the configuration file
        if [ "${DEFAULT_DB_PASSWORD}" == "" ]; then
            # Ask for the password
            read -r -p "Enter password for ${DEFAULT_DB_USER} database user: " \
                -s db_password
            echo ""
        else
            db_password="${DEFAULT_DB_PASSWORD}"
        fi

        # Ask for confirmation listing the databases to extract
        if [ $default_answer_yes == false ]; then
            echo "The following databases will be extracted:"
            for dbKey in "${dbs_to_extract[@]}"; do
                echo "    ${DB_CONFIG[${dbKey}db_name]}"
            done
            if ! ask_yes_no "Are you sure?"; then
                exit 0
            fi
        fi

        # Extracts the dumps (parallel)
        for dbKey in "${dbs_to_extract[@]}"; do
            get_dump "${DEFAULT_DB_USER}" "${db_password}" "${dbKey}" "${simulate}" &
            pids+=("$!")
        done

        # Show spinner
        show_spinner &
        spinner_pid=$!

        # Wait for all processes to finish
        for pid in "${pids[@]}"; do
            wait "${pid}"
            task_exit=$?
            if [ $exit_value -eq 0 ] && [ $task_exit -ne 0 ]; then
                exit_value=$task_exit
            fi
        done

        kill "${spinner_pid}" &>/dev/null
    fi

    exit $exit_value
}

main "$@"
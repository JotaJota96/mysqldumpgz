#!/bin/bash

# Keys to identify the databases the script can work with. It is used to iterate over the databases.
declare  -a DB_KEYS=("md")

# This associative array contains information related to a database that the script can work with.
# The key of each element is the database key + the name of the property.
# You can add more databases by adding more elements to the DB_KEYS array and adding more elements to this array.
declare -A DB_CONFIG=(
    # Example database "my_database"
    ["md""short_flag"]="-m"           # Short flag
    ["md""long_flag"]="--my-database" # Long flag
    ["md""show_name"]="My Database"   # Name that is shown in the logs
    ["md""db_name"]="my_database"     # Database name
    ["md""file_suffix"]="_myDB"       # File suffix
)

# Default values
readonly DEFAULT_DATE_FORMAT="+%Y-%m-%d"
readonly DEFAULT_DUMP_FOLDER="/home/user/dumps/"
readonly DEFAULT_ORGANIZE_BY_DATE=true
readonly DEFAULT_HOST="localhost"
readonly DEFAULT_PORT="3306"
readonly DEFAULT_DB_USER="root"
readonly DEFAULT_DB_PASSWORD=""
readonly DEFAULT_SYS_USER="user"
readonly DEFAULT_SYS_GROUP="user"
readonly REQUIRE_ROOT=false

# Exit codes
readonly EXIT_ERROR_USER_NOT_ROOT=1
readonly EXIT_ERROR_ARGS=2
readonly EXIT_ERROR_COMMAND_NOT_FOUND=3
readonly EXIT_ERROR_MYSQLDUMP=11
readonly EXIT_ERROR_GZIP=12
readonly EXIT_ERROR_CHOWN=13 

#!/bin/bash


# initialize the repository
vcs_init() {
    # check if a VCS repository already exists
    if [ -d ".myvcs" ]; then
        echo "A vcs repository already exists"
        return 1
    fi

    mkdir .myvcs
    mkdir .myvcs/objects   
    mkdir .myvcs/commits

    touch .myvcs/objects/files

    touch .myvcs/config
    touch .myvcs/logs

    #set the log dir 
    echo "logs_dir=.myvcs/logs" > .myvcs/config

    # HEAD pointer
    echo "No commits yet" > .myvcs/HEAD

    echo "Initialize a new VCS repository in the current directory."
}


# add a file to tracking files
vcs_add() {

    local f_flage=false
    local t_flage=false
    local s_flage=false

    local show_help=false


        # Parse options
    while getopts ":ftsh" opt; do
        case ${opt} in
            f ) f_flage=true ;;
            t ) t_flage=true ;;
            s ) s_flage=true ;;
            h ) show_help=true;;
            \? ) echo "Invalid option: $OPTARG. Use -h for help."
                return ;;
        esac
    done
    shift $((OPTIND -1))


    if [ "$show_help" = true ]; then 
        echo "A version control system like git using bash scripting."
        echo "Usage: myvcs add [OPTION] COMMAND [ARGS]"
        echo ""
        echo "Options:"
        echo "  -h,            Display this help message, WITH NO ARGS"
        echo "  -f             Allows execution by creating subprocesses with fork."
        echo "  -t             Allows execution by threads."
        echo "  -s             Executes the program in a subshell."
        echo ""
        return 1
    fi

    local file_path="$1"

 
    # check if the repository was initialized
    if [ ! -d ".myvcs" ]; then
        echo "no vcs repository found. Please initialize with 'myvcs init'"
        return 1
    fi

    
    if [ "$file_path" = "." ]; then
        readarray -t files_array < <(find . -type f -not -path '*/\.*')
        for file in "${files_array[@]}"; do
            if is_tracked "$file"; then
                :
            else
                if $f_flag; then
                    (
                        add_file "$file"
                    ) &
                elif $t_flag; then
                    {
                        add_file "$file"
                    } &
                elif "$s_flag"; then
                    (
                        add_file "$file"
                    )
                else
                    add_file "$file"
                fi
            fi
        done
    else
        # chekc if the file exists
        if [ ! -f "$file_path" ]; then
            echo "file not found: $file_path"
            return 1
        fi

        if is_tracked "$file_path"; then
            echo "File is already tracked: $file_path"
            return 1
        fi

        # check if the file is in the ignore file


        # calculate the file's hash
        local file_hash
        file_hash=$(compute_file_hash "$file_path")

        # save the file object
        store_file_object "$file_path" "$file_hash"
    fi
}


# create a new commit
vcs_commit() {
    local commit_message="$1"

    # check if the repo was initialized
    if [ ! -d ".myvcs" ]; then
        echo "No VCS repository found. Please initialize with 'myvcs init'."
        return 1
    fi

    local tracked_files=($(list_tracked_files))
    if [ ${#tracked_files[@]} -eq 0 ]; then
        echo "No tracked files found. Please use 'myvcs add' to add files."
        return 1
    fi


    # unique commit id based on the current date
    local commit_id
    commit_id=$(date +%s%N)

    # get the previous commit ID from HEAD
    local prev_commit
    prev_commit=$(cat .myvcs/HEAD)

    # get the current timestamp
    local timestamp
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")

    # create a commit file
    local commit_file=".myvcs/commits/$commit_id"

    echo "Commit ID: $commit_id" > "$commit_file"
    echo "Timestamp: $timestamp" >> "$commit_file"
    echo "Author: $(whoami)" >> "$commit_file"
    echo "Message: $commit_message" >> "$commit_file"
    echo "Previous committ: $prev_commit" >> "$commit_file"

    # calculate the current file hashes to track changes
    echo "Files hashe:" >> "$commit_file"
    while IFS= read -r line; do
        # Extract the file name and hash using parameter expansion
        filename="${line%%:*}"
        hash="${line##*: }"
        echo "$filename: $hash" >> "$commit_file"        
    done < ".myvcs/objects/files"

    # update HEAD pointer to the new commit id
    echo "$commit_id" > .myvcs/HEAD

    echo "Created commit with ID: $commit_id"

    log "$commit_id" "$timestamp" "$(whoami)" "$commit_message"
}


# check out a specific commit
vcs_checkout() {
    local commit_id="$1"

    # check if the repo was initialized
    if [ ! -d ".myvcs" ]; then
        echo "No VCS repository found. Please initialize with 'myvcs init'."
        return 1
    fi

    # check if the checkout commit id is the current commit pointed by HEAD
    local head_id=$(cat .myvcs/HEAD)

    if [ ["$commit_id" = "$head_id"] ]; then
        echo "this is the current commit"
        return 1
    fi

    # check if the commit id exists
    local commit_file=".myvcs/commits/$commit_id"
    if [ ! -f "$commit_file" ]; then
        echo "commit not found: $commit_id"
        return 1
    fi

    echo "cheking out commit: $commit_id"

    # read the commit file to get file hashes
    local start_files=0
    while IFS= read -r line; do

        if [[ "$line" == "Files hashe:" ]]; then
            start_files=1
            continue
        fi
        
        if [ "$start_files" -eq 1 ]; then
            # get the file name and hash
            local file_path=$(echo "$line" | cut -d ':' -f 1 | xargs)
            local file_hash=$(echo "$line" | cut -d ':' -f 2 | xargs)
            
            # find the corresponding object file
            local object_dir=".myvcs/objects/${file_hash:0:2}"
            local object_path="$object_dir/${file_hash:2}"

            if [ ! -f "$object_path" ]; then
                echo "object not found for file: $file_path"
                continue
            fi

            cp "$object_path" "$file_path"
        fi
    done < "$commit_file"

    echo "Checkout completed."
}


vcs_log() {

    local l_flage=false
    local r_flage=false

    local show_help=false


    while getopts ":lrh" opt; do
        case ${opt} in
            l ) l_flage=true ;;
            r ) r_flage=true;;
            h ) show_help=true;;
            \? ) echo "Invalid option: $OPTARG. Use -h for help."
                return ;;
        esac
    done
    shift $((OPTIND -1))


    if [ "$show_help" = true ]; then 
        echo "A version control system like git using bash scripting."
        echo "Usage: myvcs log [OPTION] [ARGS]"
        echo ""
        echo "Options:"
        echo "  -l,            SET THE LOGS FILE PATH"
        echo ""
        return 1
    fi


    if $l_flage; then 
        set_logs_dir $1
        return 1
    fi

    if $r_flage; then 
        set_logs_dir ".myvcs/logs"
        return 1
    fi


    local log_dir=$(get_log_dir)

    echo "Log File: $log_dir"
    echo "-------------------------------------------"
    cat $log_dir
    echo "-------------------------------------------"

}



# compute SHA-1 hash of a file
compute_file_hash() {
    local file_path="$1"
    sha1sum "$file_path" | awk '{print $1}'  # Extract the hash
}


# Store file data in the objects directory
store_file_object() {
    local file_path="$1"
    local file_hash="$2"

    # Determine the object's directory based on the hash
    local object_dir=".myvcs/objects/${file_hash:0:2}"
    local object_path="$object_dir/${file_hash:2}"

    # Create the directory if it doesn't exist
    [ ! -d "$object_dir" ] && mkdir -p "$object_dir"

    cp "$file_path" "$object_path"


    if file_already_tracked "$file_path"; then
        while IFS= read -r line; do
            filename="${line%%:*}"
            hash="${line##*: }"
            
            if [ "$filename" == "$file_path " ]; then
                sed -i "s/$hash/$file_hash/g" ".myvcs/objects/files"
                break
            fi

        done < ".myvcs/objects/files"

    else 
        echo "$file_path : $file_hash" >> .myvcs/objects/files
    fi
}

file_already_tracked() {
    local file_path="$1"
    local files_file=".myvcs/objects/files"
    grep -q "^$file_path " "$files_file"
}

is_tracked() {
    local file="$1"
    local file_hash=$(compute_file_hash "$file")
    local object_path=".myvcs/objects/${file_hash:0:2}/${file_hash:2}"
    [ -f "$object_path" ]
}

list_tracked_files() {
    # Get a list of all objects in the repository
    local objects_dir=".myvcs/objects"
    local objects=("$objects_dir"/*)
    
    # Iterate through each object and extract the file paths
    local tracked_files=()
    for object in "${objects[@]}"; do
        local file=$(basename "$object")
        tracked_files+=("$file")
    done

    echo "${tracked_files[@]}"
}


add_file() {
    local file="$1"
    
    echo $file

    local file_hash
    file_hash=$(compute_file_hash "$file")


    store_file_object "$file" "$file_hash"

    echo "Added file: $file with hash: $file_hash"
}



get_log_dir () {
    local config_file=".myvcs/config"
    if [ -f "$config_file" ]; then
        logs_dir=$(grep "logs_dir=" "$config_file" | cut -d '=' -f 2)
        logs_dir=$(echo "$logs_dir" | tr -d '[:space:]')
        echo "$logs_dir"
    else
        echo "Config file not found: $config_file"
        return 1
    fi
}

set_logs_dir() {

    if ! is_admin; then 
        echo "you need admin permession"
        return 0
    fi

    local log_dir="$1"
    local config_file=".myvcs/config"

    mkdir -p "$(dirname "$config_file")"

    if grep -q "logs_dir=" "$config_file"; then
        sed -i "s|logs_dir=.*|logs_dir=$log_dir|" "$config_file"
    else
        echo "logs_dir=$log_dir" >> "$config_file"
    fi

    echo "Logs directory set to: $log_dir"
}

is_admin() {
    if [ "$(id -u)" -eq 0 ]; then
        return 0
    else
        return 1
    fi
}



log() {
    # get the log file
    local config_file=".myvcs/config"

    local log_dir=$(get_log_dir)

    local commit_id="$1"
    local timestamp="$2"
    local author="$3"
    local message="$4"


    # Log the commit information
    echo "Commit ID: $commit_id" >> "$log_dir"
    echo "Timestamp: $timestamp" >> "$log_dir"
    echo "Author: $author" >> "$log_dir"
    echo "Message: $message" >> "$log_dir"
    echo "-------------------------------------------" >> "$log_dir"
}



show_help() {
    echo "Usage: myvcs [OPTIONS] COMMAND [ARGS]"
    echo "A version control system like git using bash scripting."
    echo ""
    echo "Options:"
    echo "  -h,            Display this help message and exit."
    echo "  -f             Allows execution by creating subprocesses with fork."
    echo "  -t             Allows execution by threads."
    echo "  -s             Executes the program in a subshell."
    echo ""
    echo "Commands:"
    echo "  init           Initialize a new repository."
    echo "  add            Add files to the repository."
    echo "  commit         Record changes to the repository."
    echo "  checkout       Restore previous versions of files."
    echo "  log            View commit history."
    echo "  restore        Reset to a previous commit."
    echo ""
    echo "Run 'myvcs COMMAND --help' for more information on a specific command."
}


# vcs commands
case "$1" in
    init)
        vcs_init;;
    add)
        if [ $# -eq 2 ]; then
            vcs_add "$2"
        elif [ $# -eq 3 ]; then
            vcs_add "$2" "$3"
        else
            echo "Invalid number of arguments for 'add' command"
        fi
        ;;
    commit)
        vcs_commit "$2";;
    checkout)
        vcs_checkout "$2";;

    log) 
        vcs_log $2 $3;;
    *)
        echo "Unknown command: $1"
        echo "use those commands: init, add, commit";;
esac
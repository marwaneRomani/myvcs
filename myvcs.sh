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

    # HEAD pointer
    echo "No commits yet" > .myvcs/HEAD

    echo "Initialized a new VCS repository in the current directory."
}

# Store file data in the objects directory
store_file_object() {
    local file_path="$1"
    local file_hash="$2"

    # Determine the object's directory based on the hash
    local object_dir=".myvcs/objects/${file_hash:0:2}"  # Use the first two characters to create a subdirectory
    local object_path="$object_dir/${file_hash:2}"

    # Create the directory if it doesn't exist
    [ ! -d "$object_dir" ] && mkdir -p "$object_dir"

    # Copy the file to the object storage
    cp "$file_path" "$object_path"

    echo "Stored file: $file_path as object: $object_path"
}


# add a file to tracking files
vcs_add() {
    local file_path="$1"

    # check if the repository was initialized
    if [ ! -d ".myvcs" ]; then
        echo "no vcs repository found. Please initialize with 'myvcs init'"
        return 1
    fi

    # chekc if the file exists
    if [ ! -f "$file_path" ]; then
        echo "file not found: $file_path"
        return 1
    fi

    # calculate the file's hash
    local file_hash
    file_hash=$(compute_file_hash "$file_path")

    # save the file object
    store_file_object "$file_path" "$file_hash"

    echo "Added file: $file_path with hash: $file_hash"
}


# compute SHA-1 hash of a file
compute_file_hash() {
    local file_path="$1"
    sha1sum "$file_path" | awk '{print $1}'  # Extract the hash
}


# create a new commit
vcs_commit() {
    local commit_message="$1"

    # check if the repo was initialized
    if [ ! -d ".myvcs" ]; then
        echo "No VCS repository found. Please initialize with 'myvcs init'."
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
    echo "Previous commit: $prev_commit" >> "$commit_file"

    #TODO: ADD ONLY TRACKED FILE ###
    # calculate the current file hashes to track changes
    echo "File hashes:" >> "$commit_file"
    for file in *; do
        if [ -f "$file" ]; then
            local file_hash
            file_hash=$(compute_file_hash "$file")
            echo "$file: $file_hash" >> "$commit_file"
        fi
    done

    # update HEAD pointer to the new commit id
    echo "$commit_id" > .myvcs/HEAD

    echo "Created commit with ID: $commit_id"
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
    local head_id = $(cat .myvcs/HEAD)

    if [ ["$commit_id" = "$head_id"] ]; then 
        echo "this is the current commit"
        return 1
    fi

    # check if the commit id exists
    local commit_file=".myvcs/commits/$commit_id"
    if [ ! -f "$commit_file" ]; then
        echo "commity not found: $commit_id"
        return 1
    fi

    echo "cheking out commit: $commit_id"

    # read the commit file to get file hashes
    local start_files=0
    while IFS= read -r line; do
        if [[ "$line" == "File hashes:" ]]; then
            start_files=1
            continue
        fi
        
        if [ "$start_files" -eq 1 ]; then
            # get the file name and hash
            local file_name=$(echo "$line" | cut -d: -f1)
            local file_hash=$(echo "$line" | cut -d: -f2)
            
            # find the corresponding object file
            local object_dir=".myvcs/objects/${file_hash:0:2}"
            local object_path="$object_dir/${file_hash:2}"

            if [ ! -f "$object_path" ]; then
                echo "object not found for file: $file_name"
                continue
            fi

            # restore the file
            cp "$object_path" "$file_name"
            echo "restored file: $file_name from commit: $commit_id"
        fi
    done < "$commit_file"

    echo "Checkout completed."
}



# Main script logic to handle command-line arguments
if [ "$#" -eq 0 ]; then
    echo "Usage: $0 [command]"
    echo "Commands:"
    echo "  init     Initialize a new VCS repository"
    exit 1
fi


# vcs commands
case "$1" in
    init)
        vcs_init;;
    add)
        vcs_add "$2";;
    commit)
        vcs_commit "$2";;

    checkout)
        vcs_checkout "$2";;

    *)
        echo "Unknown command: $1"
        echo "use those commands: init, add, commit";;
esac

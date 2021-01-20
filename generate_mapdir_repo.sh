#!/bin/bash

binary_path=../DDNetPP-maps
dir_path="$(pwd)/maps"

mkdir -p "$dir_path" || exit 1
cd "$binary_path" || exit 1
(
    cd "$dir_path" || exit 1
    test -d .git || git init
) || exit 1

git checkout master || exit 1
total_commits="$(git rev-list --count master)"
total_pad="${#total_commits}"
current_commit=0
inital_commit=1

function err() {
    printf "[-] %s\n" "$1"
}
function wrn() {
    printf "[!] %s\n" "$1"
}
function log() {
    printf "[*] %s\n" "$1"
}
function fail() {
    err "$1"
    git checkout master
    exit 1
}
function get_git_remote() {
    local remote
    local url
    remote="$(git remote get-url "$(git remote | grep origin | head -n1)")"
    if [ "$remote" == "" ]
    then
        remote="$(git remote get-url "$(git remote | head -n1)")"
    fi
    url=$remote
    if [[ $remote =~ ^git@ ]]
    then
        nocolon=${remote/:/\/}
        baseurl="${nocolon##*@}"
        site="${baseurl%%/*}"
        repo="${baseurl#*/}"
        repo="${repo%.git*}"
        if [[ ! "$site" =~ \. ]]
        then
            if [[ "$site" =~ github ]]
            then
                site='github.com'
            elif [[ "$site" =~ gitlab ]]
            then
                site='gitlab.com'
            else
                echo "failed to assume url '$site'"
                exit 1
            fi
        fi
        url="https://$site/$repo"
    elif [[ ! $remote =~ ^https ]]
    then
        echo "invalid remote '$remote"
        exit 1
    fi
    echo "$url"
}

function update_map() {
    local mapname_ext=$1
    local commit=$2
    local mapname
    local map_dst
    mapname="${mapname_ext%.map*}"
    map_dst="$dir_path/$mapname"
    test -d "$map_dst" && rm -rf "${dir_path:?}/$mapname"
    test -f "$mapname_ext" || { echo "map not found '$mapname_ext'"; return; }
    if [[ "$mapname" =~ /.+ ]]
    then
        mkdir -p "$dir_path/${mapname%/*}" || exit 1
    fi
    log "converting map '$mapname_ext' ..."
    if ! edit_map "$mapname_ext" "$map_dst" --mapdir
    then
        if edit_map "$mapname_ext" "$map_dst" --mapdir | \
            grep -q 'parse error:.*cause: Sound'
        then
            wrn "WARNING: map '$mapname_ext' has sound layer errors"
        else
            fail "edit_map failed on map '$mapname_ext' at commit '$commit'"
        fi
    fi
}

git_remote="$(get_git_remote)"

for commit in $(printf "%s\n" "$(git --no-pager log --pretty='format:%H')" | tac)
do
    current_commit="$((current_commit+1))"
    git checkout "$commit"
    printf "[*][%*s/%*s] $commit\n" \
        "$total_pad" "$current_commit" "$total_pad" "$total_commits"
    if [ "$inital_commit" == "1" ]
    then
        inital_commit=0
        while IFS= read -r -d '' map
        do
            update_map "$map" "$commit"
        done < <(find . -name "*.map")
    else
        for map in $(git diff --name-only HEAD HEAD~1)
        do
            if [[ "$map" =~ \.map$ ]]
            then
                update_map "$map" "$commit"
            fi
        done
    fi
    commit_msg="$(
        git log --format=%B -n 1 "$commit"
        printf '\n'
        printf '%s/commit/%s' "$git_remote" "$commit"
    )"
    (
        cd "$dir_path" || exit 1
        git add .
        git commit -m "$commit_msg" || true
    ) || fail "commit failed"
done


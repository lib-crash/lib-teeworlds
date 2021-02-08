#!/bin/bash

tw=""
th=""
scale=1

declare -A aMapAdd
declare -A aMapDel

for arg in "$@"
do
    if [ "$arg" == "--help" ] || [ "$arg" == "-h" ] || [ "$arg" == "help" ]
    then
        echo "$(basename "$0") [OPTIONS..] [max width] [max height]"
        echo "description:"
        echo "  This script parses and previews the git diff of a mapdir repo"
        echo "  Use the $(tput bold)edit_map$(tput sgr0) binary from twmap (https://gitlab.com/Patiga/twmap)"
        echo "  To generate a mapdir directory out of a teeworlds map"
        echo "  Then track it in git and if you alter the mapdir"
        echo "  you can preview the $(tput bold)git diff$(tput sgr0) using this tool"
        echo ""
        echo "options:"
        echo "  --help"
        echo "    shows this help"
        echo ""
        echo "max width:"
        echo "  maximum columns used for map preview"
        echo "  defaults to terminal window width - 2"
        echo ""
        echo "max height:"
        echo "  maximum rows used for map preview"
        echo "  defaults to terminal window height - 4"
        echo ""
        echo "example:"
        echo "  edit_map dm1.map dm1 --mapdir"
        echo "  cd dm1"
        echo "  git init && git add . && git commit -m init"
        echo "  cd .."
        echo "  edit_map dm1_edit.map dm1_edit --mapdir"
        echo "  rm -rf dm1/*"
        echo "  cp -r dm1_edit/* dm1/"
        echo "  cd dm1"
        echo "  mapdir_git_diff.sh"
        exit 0
    elif [ "${arg::1}" == "-" ]
    then
        if [ "$arg" == "--buffer" ]
        then
            echo "warning: --buffer is deprecated"
            echo "         buffer mode is default now and non buffer is removed"
        else
            echo "invalid argument '$arg' try '--help'"
            exit 1
        fi
    elif [ "$tw" == "" ]
    then
        tw="$arg"
    elif [ "$th" == "" ]
    then
        th="$arg"
    else
        echo "unexpected argument see --help"
        exit 1
    fi
done

if [ "$tw" == "" ]
then
    tw="$(tput cols)"
fi
if [ "$th" == "" ]
then
    th="$(stty size | cut -d' ' -f1)"
fi
term_max_width="$((tw-2))"
term_max_height="$((th-4))"

function draw_map() {
    local mode="$1"
    printf '+'
    read -ra w_range < <(eval "echo {1..$scaled_width}")
    printf '%0.s-' "${w_range[@]}"
    printf '+\n'
    for((y=0;y<scaled_height;y++))
    do
        printf '|'
        for((x=0;x<scaled_width;x++))
        do
            if [ "$mode" == "add" ]
            then
                printf '%s' "${aMapAdd[$x,$y]}"
            else
                printf '%s' "${aMapDel[$x,$y]}"
            fi
        done
        printf '|\n'
    done
    printf '+'
    printf '%0.s-' "${w_range[@]}"
    printf '+\n'
}
function draw_tile_add() {
    local x="$1"
    local y="$2"
    local id="$3"
    local sx="$x"
    local sy="$y"
    sx="$(awk "BEGIN {printf \"%d\",${scale}*${x}}")"
    sy="$(awk "BEGIN {printf \"%d\",${scale}*${y}}")"
    aMapAdd[$sx,$sy]='+'
    aTilesAdd+=("$id")
}
function draw_tile_del() {
    local x="$1"
    local y="$2"
    local id="$3"
    local sx="$x"
    local sy="$y"
    sx="$(awk "BEGIN {printf \"%d\",${scale}*${x}}")"
    sy="$(awk "BEGIN {printf \"%d\",${scale}*${y}}")"
    aMapDel[$sx,$sy]='-'
    aTilesDel+=("$id")
}

function update_scale() {
    local width="$1"
    local height="$2"
    scaled_width="$width"
    scaled_height="$height"
    if [ "$width" -gt "$term_max_width" ]
    then
        scaled_width="$term_max_width"
        scale="$(awk "BEGIN {printf \"%.2f\",${scaled_width}/${width}}")"
        scaled_height="$(awk "BEGIN {printf \"%d\",${scale}*${height}}")"
    fi
    if [ "$scaled_height" -gt "$term_max_height" ]
    then
        scaled_height="$term_max_height"
        scale="$(awk "BEGIN {printf \"%.2f\",${scaled_height}/${height}}")"
        scaled_width="$(awk "BEGIN {printf \"%d\",${scale}*${width}}")"
    fi
}

aTilesAdd=()
aTilesDel=()

function finish_last_layer() {
    local width="$1"
    local height="$2"
    local name="$3"
    local image="$4"
    draw_map add
    draw_map del
    tput bold
    echo "$name"
    tput sgr0
    echo "  image=$image"
    tput bold
    echo "size"
    tput sgr0
    echo "  orginal=${width}x${height}"
    echo "  scaled=${scaled_width}x${scaled_height}"
    echo "  scale=$scale"
    tput bold
    echo "tiles added"
    tput sgr0
    echo "  amount : new index"
    for tile in "${aTilesAdd[@]}"
    do
        echo "$tile"
    done | sort | uniq -c | sort -nr | awk '{ printf "  %-6d : %-6d\n", $1, $2 }'
    tput bold
    echo "tiles removed"
    tput sgr0
    echo "  amount : index"
    for tile in "${aTilesDel[@]}"
    do
        echo "$tile"
    done | sort | uniq -c | sort -nr | awk '{ printf "  %-6d : %-6d\n", $1, $2 }'
    aTilesAdd=()
    aTilesDel=()
}

function parse_diff() {
    local line
    local first_layer=1
    local layer_name=''
    local layer_width=0
    local layer_height=0
    local tile
    local tile_x
    local tile_x_del
    local tile_x_add
    local tile_y
    local tile_y_del
    local tile_y_add
    local tile_id
    local tile_id_del
    local tile_id_add
    local tile_x_change=' '
    local tile_y_change=' '
    local tile_id_change=' '
    local x
    local y
    while IFS= read -r line
    do
        if [[ "$line" =~ ^\+\+\+\ b ]]
        then
            if [ "$first_layer" == "0" ]
            then
                finish_last_layer "$layer_width" "$layer_height" "$layer_name" "$layer_image"
            fi
            first_layer=0
            layer_name="${line:6}"
            layer_width="$(jq '.width' "$layer_name")"
            layer_height="$(jq '.height' "$layer_name")"
            layer_image="$(jq '.image' "$layer_name")"
            update_scale "$layer_width" "$layer_height"
            for((y=0;y<scaled_height;y++))
            do
                for((x=0;x<scaled_width;x++))
                do
                    aMapAdd[$x,$y]=' '
                    aMapDel[$x,$y]=' '
                done
            done
        elif [[ "$line" =~ ^[+-]?[[:space:]]*\"x\":\ ([0-9]*) ]]
        then
            tile_x="${BASH_REMATCH[1]}"
            tile_x_change="${line::1}"
            if [ "$tile_x_change" == "-" ]
            then
                tile_x_del="$tile_x"
            elif [ "$tile_x_change" == "+" ]
            then
                tile_x_add="$tile_x"
            fi
        elif [[ "$line" =~ ^[+-]?[[:space:]]*\"y\":\ ([0-9]*) ]]
        then
            tile_y="${BASH_REMATCH[1]}"
            tile_y_change="${line::1}"
            if [ "$tile_y_change" == "-" ]
            then
                tile_y_del="$tile_y"
            elif [ "$tile_y_change" == "+" ]
            then
                tile_y_add="$tile_y"
            fi
        elif [[ "$line" =~ ^[+-]?[[:space:]]*\"id\":\ ([0-9]*) ]]
        then
            tile_id="${BASH_REMATCH[1]}"
            tile_id_change="${line::1}"
            if [ "$tile_id_change" == "-" ]
            then
                tile_id_del="$tile_id"
            elif [ "$tile_id_change" == "+" ]
            then
                tile_id_add="$tile_id"
            fi
        elif [ "${line:1:5}" == "    }" ] || [ "${line::2}" == "@@" ]
        then
            if [ "$tile_x_change" == " " ] && [ "$tile_y_change" == " " ] && [ "$tile_id_change" == " " ]
            then
                continue
            fi
            # tile removed (only -)
            if [ "$tile_id_change" == "-" ] && [ "$tile_x_change" == "-" ] && [ "$tile_y_change" == "-" ]
            then
                draw_tile_del "$tile_x" "$tile_y" "$tile_id"
                # printf -- "full delete x=%s y=%s id=%s\n" "$tile_x" "$tile_y" "$tile_id"
            # tile added (only +)
            elif [ "$tile_id_del" == "" ] && [ "$tile_x_del" == "" ] && [ "$tile_y_change" == "+" ] && \
                [ "$tile_id_add" != "" ] && [ "$tile_x_add" != "" ] && [ "$tile_y_add" != "" ]
            then
                draw_tile_add "$tile_x" "$tile_y" "$tile_id"
                # printf "full add x=%s y=%s id=%s\n" "$tile_x" "$tile_y" "$tile_id"
            else
                # partial add
                if [ "$tile_id_add" != "" ] || [ "$tile_x_add" != "" ] || [ "$tile_y_add" != "" ]
                then
                    draw_tile_add "${tile_x_add:-$tile_x}" "${tile_y_add:-$tile_y}" "${tile_id_add:-$tile_id}"
                    # printf "partial add x=%s y=%s id=%s\n" "${tile_x_add:-$tile_x}" "${tile_y_add:-$tile_y}" "${tile_id_add:-$tile_id}"
                fi
                # partial del
                if [ "$tile_id_del" != "" ] || [ "$tile_x_del" != "" ] || [ "$tile_y_del" != "" ]
                then
                    draw_tile_del "${tile_x_del:-$tile_x}" "${tile_y_del:-$tile_y}" "${tile_id_del:-$tile_id}"
                    # printf "partial del x=%s y=%s id=%s\n" "${tile_x_del:-$tile_x}" "${tile_y_del:-$tile_y}" "${tile_id_del:-$tile_id}"
                fi
            fi
            tile_x_change=' '
            tile_x_del=""
            tile_x_add=""
            tile_y_change=' '
            tile_y_del=""
            tile_y_add=""
            tile_id_change=' '
            tile_id_del=""
            tile_id_add=""
        fi
    done < <(git --no-pager diff)
    # add the last tile if the diff ends before a closing }
    if [ "$tile_x_change" == "+" ] || [ "$tile_y_change" == "+" ] || [ "$tile_id_change" == "+" ]
    then
        draw_tile_add "$tile_x" "$tile_y" "$tile_id"
    fi
    finish_last_layer "$layer_width" "$layer_height" "$layer_name" "$layer_image"
}

parse_diff


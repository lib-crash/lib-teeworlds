#!/bin/bash

tw=""
th=""
scale=1
arg_buffer=0

declare -A aMap

for arg in "$@"
do
    if [ "$arg" == "--help" ] || [ "$arg" == "-h" ] || [ "$arg" == "help" ]
    then
        echo "$(basename "$0") [OPTIONS..] [max width] [max height]"
        echo "options:"
        echo "  --help"
        echo "    shows this help"
        echo ""
        echo "  --buffer"
        echo "    use a buffer and print all tiles line by line"
        echo "    this option is nice for environments that do not"
        echo "    support setting the cursor with tput"
        echo "    by default a more fancy and live rendering is used"
        echo ""
        echo "max width:"
        echo "  maximum columns used for map preview"
        echo "  defaults to terminal window width - 2"
        echo ""
        echo "max height:"
        echo "  maximum rows used for map preview"
        echo "  defaults to terminal window height - 4"
        exit 0
    elif [ "${arg::1}" == "-" ]
    then
        if [ "$arg" == "--buffer" ]
        then
            arg_buffer=1
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

if [ "$arg_buffer" == "0" ]
then
    trap 'tput sgr0; tput cnorm; tput rmcup || clear' SIGINT EXIT
fi

function draw_map() {
    printf '+'
    read -ra w_range < <(eval "echo {1..$scaled_width}")
    printf '%0.s-' "${w_range[@]}"
    printf '+\n'
    for((y=0;y<scaled_height;y++))
    do
        printf '|'
        for((x=0;x<scaled_width;x++))
        do
            printf '%s' "${aMap[$x,$y]}"
        done
        printf '|\n'
    done
    printf '+'
    printf '%0.s-' "${w_range[@]}"
    printf '+\n'
}

function draw_tile_change() {
    local x="$1"
    local y="$2"
    local id="$3"
    local sx="$x"
    local sy="$y"
    sx="$(awk "BEGIN {printf \"%d\",${scale}*${x}}")"
    sy="$(awk "BEGIN {printf \"%d\",${scale}*${y}}")"
    if [ "$arg_buffer" == "1" ]
    then
        aMap[$sx,$sy]='*'
    else
        tput cup "$((sy+1))" "$((sx+1))"
        printf '*'
    fi
    aTilesChanged+=("$id")
}

function update_scale() {
    local width="$1"
    local height="$2"
    scaled_width="$width"
    scaled_height="$height"
    local i
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

function draw_canvas() {
    # ik i should go to hell for this
    clear
    printf '+'
    read -ra w_range < <(eval "echo {1..$scaled_width}")
    printf '%0.s-' "${w_range[@]}"
    printf '+\n'
    for((i=0;i<scaled_height;i++))
    do
        printf '|'
        printf '%0.s ' "${w_range[@]}"
        printf '|\n'
    done
    printf '+'
    printf '%0.s-' "${w_range[@]}"
    printf '+\n'
}

aTilesChanged=()

function finish_last_layer() {
    local width="$1"
    local height="$2"
    local name="$3"
    local image="$4"
    if [ "$arg_buffer" == "1" ]
    then
        draw_map "$width" "$height"
    else
        tput cup "$((scaled_height+2))" 0
    fi
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
    echo "tiles changed"
    tput sgr0
    echo "  amount : new index"
    for tile in "${aTilesChanged[@]}"
    do
        echo "$tile"
    done | sort | uniq -c | sort -nr | awk '{ printf "  %-6d : %-6d\n", $1, $2 }'
    aTilesChanged=()
}

function parse_diff() {
    local line
    local first_layer=1
    local layer_name=''
    local layer_width=0
    local layer_height=0
    local tile
    local tile_x=-1
    local tile_y=-1
    local tile_id=-1
    local tile_x_change=0
    local tile_y_change=0
    local tile_id_change=0
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
            if [ "$arg_buffer" == "0" ]
            then
                draw_canvas
            else
                for((y=0;y<scaled_height;y++))
                do
                    for((x=0;x<scaled_width;x++))
                    do
                        aMap[$x,$y]=' '
                    done
                done
            fi
        elif [[ "$line" =~ ^[+-]?[[:space:]]*\"x\":\ ([0-9]*) ]]
        then
            tile_x="${BASH_REMATCH[1]}"
            tile_x_change="${line::1}"
        elif [[ "$line" =~ ^[+-]?[[:space:]]*\"y\":\ ([0-9]*) ]]
        then
            tile_y="${BASH_REMATCH[1]}"
            tile_y_change="${line::1}"
        elif [[ "$line" =~ ^[+-]?[[:space:]]*\"id\":\ ([0-9]*) ]]
        then
            tile_id="${BASH_REMATCH[1]}"
            tile_id_change="${line::1}"
        elif [ "${line:1:5}" == "    }" ]
        then
            if [ "$tile_id_change" == "+" ]
            then
                draw_tile_change "$tile_x" "$tile_y" "$tile_id"
            fi
            tile_x_change=0
            tile_y_change=0
            tile_id_change=0
        fi
    done < <(git --no-pager diff | grep -v '^@@ ')
    # add the last tile if the diff ends before a closing }
    if [ "$tile_x_change" != "0" ] || [ "$tile_y_change" != "0" ] || [ "$tile_id_change" != "0" ]
    then
        draw_tile_change "$tile_x" "$tile_y" "$tile_id"
    fi
    finish_last_layer "$layer_width" "$layer_height" "$layer_name" "$layer_image"
}

parse_diff


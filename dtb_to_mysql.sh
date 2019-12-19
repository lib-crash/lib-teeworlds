#!/bin/bash
# DDRaceNetwork file dtb to mysql records
#
# script that takes a records directory and
# mysql credentials as input
# and then feeds the file based dtb files
# into the database
shopt -s nullglob # used for file list globbing
shopt -s extglob # used for trailing slashes globbing

is_debug=0
is_test=0

if [ "$#" -lt "6" ]
then
    echo "usage: $0 <sql-prefix> <sql-user> <sql-pass> <sql-database> <records-path> <server-type> [--debug|--test]"
    exit 1
fi
if [ "$#" -gt "6" ]
then
    flag=$7
    if [ "$flag" == "--debug" ]
    then
        is_debug=1
    elif [ "$flag" == "--test" ]
    then
        is_test=1
    else
        echo "Invalid flag '$flag' choose between --debug or --test"
        exit 1
    fi
fi

timestamp=0 # sql will create a 0000-00-00 00:00:00 stamp
gameid=0
sql_prefix=$1 # record
sql_user=$2 # teeworlds
sql_password=$3 # PW2
sql_database=$4 # teeworlds
records_path=$5 # records/
servertype=$6 # Brutal
records_path="${records_path%%+(/)}" # strip trailing slash
mysql="mysql --skip-column-names -u $sql_user -p$sql_password $sql_database"

function dbg() {
    if [ "$is_debug" -ne "1" ]
    then
        return 0;
    fi
    echo "$1"
}

if [ ! -d "$records_path" ]
then
    echo "Error: records path does not exist '$records_path'"
    exit 1
fi

# inspired by this stackoverflow answer
# https://stackoverflow.com/a/25059107
function hex_query() {
    local sql=$1
    local i
    shift 1 || return 1
    declare -a args=("$@")
    sql=${sql//[%]/%%}
    sql=${sql//[?]/UNHEX(\'%s\')}
    for ((i=0; i<${#args[@]}; i++))
    do
        args[$i]=$(echo -n "${args[$i]}" | hexdump -v -e '/1 "%02X"')
    done
    printf "$sql\n" "${args[@]}"
}

function add_points() {
    local name=$1
    local mapname=$2
    local points=0
    local sql_finished=""
    local sql_get_points=""
    local sql_set_points=""
    sql_finished="SELECT * FROM ${sql_prefix}_race WHERE Map=? AND Name=? ORDER BY time ASC LIMIT 1;"
    sql_finished=$(hex_query "$sql_finished" "$mapname" "$name")
    dbg "sql:"
    dbg "$sql_finished"
    is_finished=$(echo "$sql_finished" | $mysql)
    if [ "$is_finished" != "" ]
    then
        echo "'$name' finished already."
        dbg "sql:"
        dbg "$is_finished"
        return
    fi
    sql_get_points="SELECT Points FROM ${sql_prefix}_maps WHERE Map=?;"
    sql_get_points=$(hex_query "$sql_get_points" "$mapname")
    points=$(echo "$sql_get_points" | $mysql)
    case $points in
        ''|*[!0-9]*) echo "Points '$points' is not a number map='$mapname'"; exit 1; ;;
        *) test ;;
    esac
    if [ "$is_test" == "1" ]
    then
        echo "Would add +$points points for '$name' (TEST SKIPPING)"
        return;
    fi
    echo "Add +$points points for '$name'"
    sql_set_points="INSERT INTO ${sql_prefix}_points(Name, Points) VALUES (?, ?) ON duplicate key UPDATE Name=VALUES(Name), Points=Points+VALUES(Points);"
    sql_set_points=$(hex_query "$sql_set_points" "$name" "$points")
    is_points=$(echo "$sql_set_points" | $mysql)
    if [ "$is_points" != "" ]
    then
        echo "Error: unexpected output on setting points."
        echo "sql:"
        echo "$is_points"
        exit 1
    fi
}

function insert_record() {
    local name=$1
    local time=$2
    local cp=$3
    local mapname=$4
    local i=0
    echo "Inserting record name='$name' time='$time' cp='$cp'"
    cps=()
    IFS=' '
    for c in $cp
    do
        cps+=("$c")
    done
    add_points "$name" "$mapname"
    if [ "$is_test" == "1" ]
    then
        echo "Would insert rank for '$name' (TEST SKIPPING)"
        return;
    fi
    read -rd '' sql_insert << EOF
INSERT IGNORE INTO ${sql_prefix}_race(
    Map, Name, Timestamp, Time, Server,
    cp1, cp2, cp3, cp4, cp5,
    cp6, cp7, cp8, cp9, cp10,
    cp11, cp12, cp13, cp14, cp15,
    cp16, cp17, cp18, cp19, cp20,
    cp21, cp22, cp23, cp24, cp25,
    GameID, DDNet7
) VALUES (
    ?, ?, ?, ?, ?,
    ?, ?, ?, ?, ?,
    ?, ?, ?, ?, ?,
    ?, ?, ?, ?, ?,
    ?, ?, ?, ?, ?,
    ?, ?, ?, ?, ?,
    ?, true
);
EOF
    sql_insert=$(hex_query "$sql_insert" \
    "$mapname" "$name" "$timestamp" "$time" "$servertype" \
    "${cps[$((i++))]}" "${cps[$((i++))]}" "${cps[$((i++))]}" "${cps[$((i++))]}" "${cps[$((i++))]}" \
    "${cps[$((i++))]}" "${cps[$((i++))]}" "${cps[$((i++))]}" "${cps[$((i++))]}" "${cps[$((i++))]}" \
    "${cps[$((i++))]}" "${cps[$((i++))]}" "${cps[$((i++))]}" "${cps[$((i++))]}" "${cps[$((i++))]}" \
    "${cps[$((i++))]}" "${cps[$((i++))]}" "${cps[$((i++))]}" "${cps[$((i++))]}" "${cps[$((i++))]}" \
    "${cps[$((i++))]}" "${cps[$((i++))]}" "${cps[$((i++))]}" "${cps[$((i++))]}" "${cps[$((i++))]}" \
    "$gameid")
    dbg "sql:"
    dbg "$sql_insert"
    is_insert=$(echo "$sql_insert" | $mysql)
    if [ "$is_insert" != "" ]
    then
        echo "Error: unexpected output on inserting rank."
        echo "sql:"
        echo "$is_insert"
        exit 1
    fi
}

function parse_dtb_file() {
    local dtb=$1
    local index=0
    local name=invalid
    local time=invalid
    local cp=invalid
    local mapname=invalid
    if [ ! -f "$dtb" ]
    then
        echo "Error: file does not exist '$dtb'"
        exit 1
    fi
    mapname=$(basename "$dtb" .dtb)
    echo "Mapname: $mapname"
    sql_map="SELECT Map FROM ${sql_prefix}_maps WHERE Map=?;"
    sql_map=$(hex_query "$sql_map" "$mapname")
    is_map=$(echo "$sql_map" | $mysql)
    if [[ ! "$is_map" =~ "$mapname" ]]
    then
        echo "Error: map not found! sql result:"
        echo "$is_map"
        exit 1
    fi
    while IFS= read -r line
    do
        index=$((index+1))
        if [ "$index" -eq "1" ]; then
            name="$line"
        elif [ "$index" -eq "2" ]; then
            time="$line"
        elif [ "$index" -eq "3" ]; then
            cp="$line"
            insert_record "$name" "$time" "$cp" "$mapname"
            index=0
        fi
    done < "$dtb"
    if [ "$index" -ne "0" ]
    then
        echo "Error: invalid index $index != 0"
        exit 1
    fi
}

for dtb in "$records_path/"*.dtb
do
    echo "$dtb"
    parse_dtb_file "$dtb"
done


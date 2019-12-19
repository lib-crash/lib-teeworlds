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
timestamp=TODO # TODO: choose wisely here
servertype=Novice # TODO:
gameid=0 # TODO:
sql_prefix=record
sql_user=teeworlds # TODO: userinput
sql_database=teeworlds # TODO: userinput
sql_password=PW2 # TODO: userinput

mysql="mysql --skip-column-names -u $sql_user -p$sql_password $sql_database"

if [ "$#" -ne "1" ]
then
    echo "usage: $0 <records path>"
    exit 1
fi

function dbg() {
    if [ "$is_debug" -ne "1" ]
    then
        return 0;
    fi
    echo "$1"
}

records_path=$1
records_path="${records_path%%+(/)}" # strip trailing slash
if [ ! -d "$records_path" ]
then
    echo "Error: records path does not exist '$records_path'"
    exit 1
fi

function add_points() {
    local name=$1 # TODO: sql injection
    local mapname=$2 # TODO: sql injection
    local points=0
    local sql_finished=""
    local sql_get_points=""
    local sql_set_points=""
    sql_finished="SELECT * FROM ${sql_prefix}_race WHERE Map='$mapname' AND Name='$name' ORDER BY time ASC LIMIT 1;"
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
    sql_get_points="SELECT Points FROM ${sql_prefix}_maps WHERE Map='$mapname'"
    points=$(echo "$sql_get_points" | $mysql)
    case $points in
        ''|*[!0-9]*) echo "Points '$points' is not a number."; exit 1; ;;
        *) test ;;
    esac
    echo "Add +$points points for '$name'"
    sql_set_points="INSERT INTO ${sql_prefix}_points(Name, Points) VALUES ('$name', '$points') ON duplicate key UPDATE Name=VALUES(Name), Points=Points+VALUES(Points);"
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
    local name=$1 # TODO: sql injection
    local time=$2
    local cp=$3
    local mapname=$4 # TODO: sql injection
    local i=0
    echo "Inserting record name='$name' time='$time' cp='$cp'"
    cps=()
    IFS=' '
    for c in $cp
    do
        cps+=("$c")
    done
    add_points "$name" "$mapname"
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
    '$mapname', '$name', '$timestamp', '$time', '$servertype',
    '${cps[$((i++))]}', '${cps[$((i++))]}', '${cps[$((i++))]}', '${cps[$((i++))]}', '${cps[$((i++))]}',
    '${cps[$((i++))]}', '${cps[$((i++))]}', '${cps[$((i++))]}', '${cps[$((i++))]}', '${cps[$((i++))]}',
    '${cps[$((i++))]}', '${cps[$((i++))]}', '${cps[$((i++))]}', '${cps[$((i++))]}', '${cps[$((i++))]}',
    '${cps[$((i++))]}', '${cps[$((i++))]}', '${cps[$((i++))]}', '${cps[$((i++))]}', '${cps[$((i++))]}',
    '${cps[$((i++))]}', '${cps[$((i++))]}', '${cps[$((i++))]}', '${cps[$((i++))]}', '${cps[$((i++))]}',
    '$gameid', true
);
EOF
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
    sql_map="SELECT Map FROM ${sql_prefix}_maps WHERE Map='$mapname';"
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


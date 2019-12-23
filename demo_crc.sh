#!/bin/bash
#
# demo_crc.sh <demofile> [crc]
#
# Written by ChillerDragon to view and update teeworlds 0.6 demo CRCs
# https://github.com/lib-crash/lib-teeworlds/blob/master/demo_crc.sh
#
# Free to use, edit and sell. Credits are appreciated but not needed.

CRC_OFFSET=140
CRC_LEN=8
CRC_PATTERN='^[0-9A-Fa-f]{'$CRC_LEN'}$'
TW_MAGIC='TWDEMO'

if [ "$#" -lt "1" ]
then
    echo "Usage: $(basename "$0") <demofile> [new crc]"
    exit 1
fi
demofile="$1"
new_crc="$2"
if [ ! -f "$demofile" ]
then
    echo "Error: file '$demofile' does not exist"
    exit 1
fi
demo_magic=$(head -c 6 "$demofile")
tw_version=$(head -c 11 "$demofile" | tail -c 3)
old_crc=$(head -c $((CRC_OFFSET + (CRC_LEN/2))) "$demofile" | tail -c $((CRC_LEN/2)) | xxd -p)
if [ "$demo_magic" != "$TW_MAGIC" ]
then
    echo "Error: invalid demo file '$demo_magic' != '$TW_MAGIC'"
    exit 1
fi

function log() {
    echo -e "\033[1m[+] $1\033[0m"
}

log "reading demo file..."
echo "teeworlds version: '$tw_version'"
echo "crc: '$old_crc'"

if [ "$new_crc" != "" ]
then
    if [ "${#new_crc}" -ne "$CRC_LEN" ]
    then
        echo "Error: invalid crc len '$new_crc' (${#new_crc}/$CRC_LEN)"
        exit 1
    fi
    if ! [[ "$new_crc" =~ $CRC_PATTERN ]]
    then
        echo "Error: crc is not valid hex '$new_crc'"
        exit 1
    fi
    log "writing demo file..."
    echo "new crc: '$new_crc'"
    echo -n "$new_crc" | xxd -r -p | dd of="$demofile" bs=1 seek="$CRC_OFFSET" count="$CRC_LEN" conv=notrunc
fi


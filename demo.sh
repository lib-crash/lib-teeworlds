#!/bin/bash
#
# demo.sh <demofile>
#

# struct CDemoHeader
# {
# 	unsigned char m_aMarker[7];
# 	unsigned char m_Version;
# 	char m_aNetversion[64];
# 	char m_aMapName[64];
# 	unsigned char m_aMapSize[4];
# 	unsigned char m_aMapCrc[4];
# 	char m_aType[8];
# 	unsigned char m_aLength[4];
# 	char m_aTimestamp[20];
# 	unsigned char m_aNumTimelineMarkers[4];
# 	unsigned char m_aTimelineMarkers[MAX_TIMELINE_MARKERS][4];
# };

H_MAGIC='TWDEMO'
H_MAGIC_LEN=7
H_DEMO_VERSION=$((H_MAGIC_LEN + 1))
H_NETVERISON_LEN=64
H_NETVERISON_END=$((
    H_DEMO_VERSION +
    H_NETVERISON_LEN
))
H_MAPNAME_LEN=64
H_MAPNAME_END=$((
    H_MAGIC_LEN +
    1 +
    64 +
    H_MAPNAME_LEN
))
H_MAPSIZE_LEN=4
H_MAPSIZE_END=$((
    H_MAPNAME_END +
    H_MAPSIZE_LEN
))
H_MAPCRC_LEN=4
H_MAPCRC_END=$((
    H_MAPSIZE_END +
    H_MAPCRC_LEN
))
H_TYPE_LEN=8
H_TYPE_END=$((
    H_MAPCRC_END +
    H_TYPE_LEN
))
H_LENGTH_LEN=4
H_LENGTH_END=$((H_TYPE_END + H_LENGTH_LEN))
H_TIME_LEN=25 # TODO: why is this not 20?
H_TIME_END=$((H_TYPE_END + H_TIME_LEN))
H_NUM_MARKERS_LEN=1
H_NUM_MARKERS_END=$((
    H_TIME_END +
    2 +
    H_NUM_MARKERS_LEN
))

if [ "$#" -lt "1" ] || [ "$1" == "--help" ] || [ "$1" == "-h" ]
then
    echo "Usage: $(basename "$0") [FILTER] <demofile> [FILTER]"
    echo "Description: outputs demo 0.7 header"
    echo "Filter: --map --type --time --markers"
    exit 1
fi
if [[ "$1" =~ ^-- ]]
then
    demofile="$2"
    filter="$1"
else
    demofile="$1"
    filter="$2"
fi
if [ ! -f "$demofile" ]
then
    echo "Error: file '$demofile' does not exist"
    exit 1
fi
{
    header_magic=$(head -c 6 "$demofile")
    header_netversion=$(head -c $H_NETVERISON_END "$demofile" | tail -c $H_NETVERISON_LEN)
    header_mapname=$(head -c $H_MAPNAME_END "$demofile" | tail -c $H_MAPNAME_LEN)
    header_type=$(head -c $H_TYPE_END "$demofile" | tail -c $H_TYPE_LEN)
    header_time=$(head -c $H_TIME_END "$demofile" | tail -c $H_TIME_LEN)
    header_num_markers=$(head -c $H_NUM_MARKERS_END "$demofile" | tail -c $H_NUM_MARKERS_LEN | xxd -p)
    header_num_markers=$((16#$header_num_markers))
} > /dev/null 2>&1
if [ "$header_magic" != "$H_MAGIC" ]
then
    echo "Error: invalid demo file '$header_magic' != '$H_MAGIC'"
    exit 1
fi

if [ "$filter" == "--map" ]
then
    echo "$header_mapname"
elif [ "$filter" == "--type" ]
then
    echo "$header_type"
elif [ "$filter" == "--time" ]
then
    echo "$header_time"
elif [ "$filter" == "--markers" ]
then
    echo "$header_num_markers"
elif [ "$filter" == "" ]
then
    echo "netversion: $header_netversion"
    echo "map: $header_mapname"
    echo "type: $header_type"
    echo "timestamp: $header_time"
    echo "markers: $header_num_markers"
else
    echo "Error: invalid filter '$filter'"
fi


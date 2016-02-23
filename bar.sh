#!/bin/env sh
# -*- coding: utf-8 -*-

# -- bar.sh
# i3 status_command script
#
# This script provides a (theoratically shell agnostic) way
# to retrieve system information and provide them for i3wm's
# status bar.
#
# This script is by no means correct nor the most efficient
# one. It also is kinda hacked for my device(s) to work and
# thus you might have to change a lot to get it to work for
# you.
#
# Just put `status_command sh path/to/bar.sh` into your i3
# `bar` configuration block.
#
# Do whatever you want, but please remember to mention me as
# the original author.
# -- Dave J (https://github.com/chronus7)

# -- colours

# -| as defaults
_red="#EE5555"
_green="#55AA55"
_yellow="#DDAA33"
_blue="#225577"
_magenta="#AA1177"
_cyan="#8899FF"
_white="#DDDDDD"
_black="#666666"

# -| read from .Xresources
if [ -f ~/.Xresources ]; then
    awk_txt='BEGIN{
    vars["*color0"]="black";
    vars["*color1"]="red";
    vars["*color2"]="green";
    vars["*color3"]="yellow";
    vars["*color4"]="blue";
    vars["*color5"]="magenta";
    vars["*color6"]="cyan";
    vars["*color7"]="white";
}/.*color/{ if ($1 in vars) { printf "_%s=%s\n", vars[$1], $2 }}'
    eval $(awk -F: "$awk_txt" ~/.Xresources)
fi

# -| overwrite .Xresources
_red="#EE5555"
_green="#55AA55"
_cyan="#8899FF"
_black="#666666"

# -- functions

function jsonfy() {
    # jsonfy <function> [<success color> [<error color>]]
    func="$1"
    color_success=${2:-$_white}
    color_error=${3:-$_red}
    color=$color_error

    result_code=0
    result=$($func && result_code=$?)

    if [[ $? -eq 0 ]]; then
        color=$color_success
    fi

    echo -n "{\"color\": \"$color\", \"full_text\": \"$result\"}"
}

function jsonfyC() {
    # jsonfy incl. leading comma
    echo -n ",$(jsonfy $@)"
}

function clock() {
    echo -n $(date +'%Y-%b-%d [%a] %H:%M:%S')
}

function battery() {
    # arg1 := Battery-Number

    path="/sys/class/power_supply/BAT$1/"
    if [ ! -d $path ]; then
        echo -n "↯   AC"
        return 0
    fi
    status=$(cat $path/status)
    chrg="charge"
    if [ ! -f $path/${chrg}_full ]; then
        chrg="energy"
    fi
    charge_full=$(cat $path/${chrg}_full)
    charge_now=$(cat $path/${chrg}_now)
    percentage=$(echo $charge_now $charge_full | awk '{ print $1 / $2 * 100 }')
    perc=${percentage/.*/}

    case $status in
        Dis*)
            #status="DIS"
            status="↓"
            ;;
        Char*)
            #status="CHR"
            status="↑"
            ;;
        *)
            #status="FULL"
            status="↯"
            ;;
    esac
    returnval=1

    if [ $perc -gt 20 ]; then
        returnval=0
    else
        #status="⚠"
        returnval=1
    fi

    echo -n "$status "
    printf "%3.1f%%" $percentage

    return $returnval
}

function volume() {
    output=$(amixer get Master | grep -E "^\s+Mono")
    percentage=$(echo $output | awk '{ print $4 }' | tr -d '[]')
    state=$(echo $output | awk '{ print $6 }' | tr -d '[]')
    case $state in
        on)
            echo -n "V $percentage"
            return 0
            ;;
        *)
            echo -n "M $percentage"
            return 1
            ;;
    esac
}

function leds() {
    type xset &>/dev/null
    if [ $? != 0 ]; then
        echo -n "xset required"
        return 1
    fi
    out=$(xset q | grep "Caps Lock" | awk 'function a(f,o){if(f=="on")printf o;else printf "-"}\
            {a($4,"C");a($8,"N");a($12,"S");printf "\n"}')
    ref="-N-" # CNS (Caps,Num,Scroll)
    # custom for this system (t450s)
    out=${out::1}
    ref="-"

    echo -n $out
    [ "$out" = $ref ]
    return $?
}

function layout() {
    type xkblayout-state &>/dev/null
    if [ $? != 0 ]; then
        echo -n "xkblayout-state required"
        return 1
    fi
    x=$(xkblayout-state print 'L %s' | tr '[:lower:]' '[:upper:]')
    echo -n $x
    [ "$x" == "L DE" ] && return 1 || return 0
}

function brightness() {
    printf "BRI %2.1f%%" $(xbacklight)
}

function cpu() {
    # /proc/stat: user,nice,system,idle,iowait,irq,softirq,steal,guest,guest_nice
    # TODO is this the correct current CPU-usage?!
    # ( user + system ) / ( user + system + idle ) * 100
    awk '/cpu /{ printf "CPU %2.1f%%", ($2+$4)/($2+$4+$5)*100}' /proc/stat

    # these would require state/time awareness...
    #top -bn2 | awk '/Cpu/{ print $3 }' | awk -F'/' '{ var+=$1 }END{print var / NR}'
    #top -bn2 | awk '/Cpu/{ print $3 }' | tail -n4 | awk -F'/' '{ var+=$1 }END{print var / NR}'
}

function memory() {
    awk '/MemTotal/{t=$2}/Active:/{a=$2}END{printf "MEM %3.1f%%", a / t * 100}' /proc/meminfo
}

function disk() {
    result=$(df -h "$1" | awk '/\/dev/ { printf("%3.1f/%3d", $3, $2) }' | sed s/G//g)
    printf "%-5s %9sGiB" "$1" $result
}

function wlan_ext() {
    interface="$1"
    info=$(ip link show $interface | head -n1 | cut -d' ' -f3)
    echo -n $interface
    if [ -z "$info" ]; then
        echo -n " (not found)"
        return 1
    elif [ -n "$(echo -n "$info" | grep "UP")" ]; then
        if [ -n "$(echo -n "$info" | grep "NO-CARRIER")" ]; then
            echo -n " (no carrier)"
            return 1
        else
            return 0
        fi
    else
        return 1
    fi
}

function wlan() {
    # This only shows, whether the interface is up or not, but
    # its connection status.
    interface="$1"
    echo -n $interface
    if [ -z "$(grep $interface /proc/net/wireless)" ]; then
        return 1
    else
        return 0
    fi
}

function vpn() {
    echo -n "vpn"
    if [ -z "$(ip addr show | grep ppp0)" ]; then
        return 1
    else
        return 0
    fi
}

function loop() {
    # kinda-start
    echo -n "["

    # wlan
    function wlp3s0() { wlan_ext "wlp3s0"; }
    jsonfy "wlp3s0" "$_green"

    # vpn
    #jsonfyC "vpn" "$_yellow" "$_white"

    # disk-usage
    function disk_root() { disk /; }
    function disk_home() { disk /home; }
    jsonfyC "disk_root"
    jsonfyC "disk_home"

    # memory
    jsonfyC "memory" "$_green"

    # cpu
    jsonfyC "cpu"

    # brightness
    jsonfyC "brightness"

    # layout
    jsonfyC "layout"

    # leds
    jsonfyC "leds" "$_green"

    # volume
    jsonfyC "volume" "$_green" "$_yellow"

    # battery
    function bat_0() { battery 0; }
    function bat_1() { battery 1; }
    jsonfyC "bat_0"
    jsonfyC "bat_1"

    # clock
    jsonfyC "clock"

    # kinda-end
    echo -n "],"
}

# start
echo '{"click_events": false, "version": 1}'
echo "["

interval=1
while true; do
    latest_call=$(date +%s)
    echo $(loop)

    now=$(date +%s)
    sleep $((interval - (now - latest_call)))
done


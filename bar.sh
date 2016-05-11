#!/bin/env sh
# -*- coding: utf-8 -*-
# vim: ft=sh:tw=80:foldmethod=marker

# -- bar.sh {{{
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
# -- Dave J (https://github.com/chronus7) }}}

# --/ GLOBAL VARIABLES

# --| default colours {{{
_red="#EE5555"
_green="#55AA55"
_yellow="#DDAA33"
_blue="#225577"
_magenta="#AA1177"
_cyan="#8899FF"
_white="#DDDDDD"
_black="#666666"
# --| }}}

# --| usage-string {{{
read -d '' USAGE_STR << USG
$0 [-h] [-s COLOR] [-e COLOR] [-a COLOR] [-n COLOR]

  A rather simple script for the i3wm statusbar.

Options:

 -h         Prints this help message and exits.
 -s COLOR   The success-colour to use.
 -e COLOR   The error-colour to use.
 -a COLOR   The alert-colour to use.
 -n COLOR   The neutral-colour to use.

Colours:

  Colours have to be defined in a valid format for i3. The
  hexadecimal format (regex: '[0-9A-F]{6}') works fine.
  Per default the script tries to use the users .Xresources
  for the colours. If this fails, the default-colours are
  used. Colours defined in the arguments have highest
  precedence and therefore override any other colours.
USG
# --| }}}

# --/ FUNCTIONS
function read_Xresources() { #{{{
    # TODO asking the X-server itself would be better, as
    #      one could load the colours in different ways...
    f=~/.Xresources
    if [ -f $f ]; then
        awk_txt='BEGIN{
        vars["*color0"]="black";
        vars["*color1"]="red";
        vars["*color2"]="green";
        vars["*color3"]="yellow";
        vars["*color4"]="blue";
        vars["*color5"]="magenta";
        vars["*color6"]="cyan";
        vars["*color7"]="white";}
        /.*color/{ if ($1 in vars) { printf "_%s=%s\n", vars[$1], $2 }}'
        eval $(awk -F: "$awk_txt" $f)
    fi
} #}}}

function color_S() { echo -n $_green; }
function color_E() { echo -n $_red; }
function color_A() { echo -n $_yellow; }
function color_N() { echo -n $_white; }

function joinStrings() { #{{{
    # joinStrings <sep> <items ...>
    # source: http://stackoverflow.com/a/17841619/2395605
    local IFS="$1"
    shift
    echo -n "$*"
} #}}}

function jsonfy() { #{{{
    # jsonfy <func> [<color_S> [<color_E]]
    func="$1"
    col_S=${2:-$(color_S)}
    col_E=${3:-$(color_E)}
    color=$col_E

    res_code=0
    output=$($func)

    if [ $? -eq 0 ]; then
        color=$col_S
    fi

    echo -n "{\"color\": \"$color\", \"full_text\": \"$output\"}"
} #}}}

# --/ MODULES
function clock() { #{{{
    # clock [<format>]
    # Prints the current time
    fmt="$*"
    [ -z "$fmt" ] && fmt='%Y-%b-%d [%a] %H:%M:%S'
    date +"${fmt}"
} #}}}

function battery() { #{{{
    # battery <num>
    # Prints the battery status of the given battery
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
} #}}}

function volume() { #{{{
    # Prints the current status of master-volume (requires amixer)
    output=$(amixer get Master | grep -E "^\s+Mono")
    offset=0
    if [ -z "$output" ]; then   # fix for different setup
        output=$(amixer get Master | grep -E "^\s+Front Left")
    fi

    percentage=$(cut -d' ' -f$((4 + $offset)) <<< $output | tr -d '[]')
    state=$(cut -d' ' -f$((6 + $offset)) <<< $output | tr -d '[]')
    case $state in
        on)
            echo -n "V $percentage"
            return 0;;
        *)
            echo -n "M $percentage"
            return 1;;
    esac
} #}}}

function leds() { #{{{
    # Prints the status of the keyboard-LEDs (requires xset)
    type xset &>/dev/null || { echo -n "xset required"; return 1; }

    out=$(xset q | grep "Caps Lock" | awk 'function a(f,o){if(f=="on")printf o;else printf "-"}\
            {a($4,"C");a($8,"N");a($12,"S");printf "\n"}')
    ref="-N-" # CNS (Caps,Num,Scroll)
    # custom for this system (t450s)
    out=${out::1}
    ref='-'

    echo -n $out
    [ "$out" = "$ref" ]
    return $?
} #}}}

function layout() { #{{{
    # Prints the keyboard-layout (requires xkblayout-state)
    type xkblayout-state &>/dev/null ||\
        { echo -n "xkblayout-state required"; return 1; }

    x=$(xkblayout-state print 'L %s' | tr '[:lower:]' '[:upper:]')
    echo -n $x
    [ "$x" != "L DE" ]
    return $?
} #}}}

function brightness() { #{{{
    # Prints the screen-brightness (requires xbacklight)
    printf "BRI %4.1f%%" $(xbacklight)
} #}}}

function cpu() { #{{{
    # Prints the current CPU-load
    # /proc/stat: user,nice,system,idle,iowait,irq,softirq,steal,guest,guest_nice
    # ( user + system ) / ( user + system + idle ) * 100
    awk '/cpu /{ printf "CPU %4.1f%%", ($2+$4)/($2+$4+$5)*100}' /proc/stat
} #}}}

function memory() { #{{{
    # Prints the current (active) memory usage
    awk '/MemTotal/{t=$2}/Active:/{a=$2}END{printf "MEM %4.1f%%", a/t*100}' /proc/meminfo
} #}}}

function disk() { #{{{
    # disk <disk-path> [<path-string-padding>]
    # Prints the disk-usage of the given disk
    res="$(df -h "$1" | awk '/\/dev/{printf "%5.1f/%3d", $3, $2 }' | sed s/G//g)"
    printf "%-${2:-0}s %9sGiB" "$1" "$res"
} #}}}

function wlan() { #{{{
    # wlan <interface>
    # Displays the status of the given WLAN-interface.
    i="$1"; echo -n "$i"
    info=$(ip link show $i | head -n1 | cut -d' ' -f3)
    case "$info" in
        "")             # interface not found
            echo -n " (not found)"
            return 1;;
        *NO-CARRIER*)   # up, but no connection
            echo -n " (no-carrier)"
            return 1;;
        *UP*)           # up and it seems to work
            return 0;;
        *)              # everything else (e.g. down)
            return 1;;
    esac
} #}}}

function vpn() { #{{{
    # Shows, whether a VPN-connection is established
    echo -n "VPN"
    [ -n "$(ip addr show | grep ppp0)" ]
    return $?
} #}}}

# --/ MAIN
function loop() {
    echo -n '['
    joinStrings , \
        "$(jsonfy "wlan wlp3s0")"\
        "$(jsonfy "disk /" $(color_N))"\
        "$(jsonfy "disk /home" $(color_N))"\
        "$(jsonfy memory)"\
        "$(jsonfy cpu $(color_N))"\
        "$(jsonfy brightness $(color_N))"\
        "$(jsonfy layout $(color_N))"\
        "$(jsonfy leds $(color_S))"\
        "$(jsonfy volume $(color_S) $(color_A))"\
        "$(jsonfy "battery 0" $(color_N))"\
        "$(jsonfy "battery 1" $(color_N))"\
        "$(jsonfy clock $(color_N))"
    echo '],'
}

function main() { #{{{
    echo '{"click_events": false, "version": 1}'
    echo '['

    interval=1
    while true; do
        prev_call=$(date +%s.%N)
        loop
        now=$(date +%s.%N)
        sleep $(awk "END{print ($interval - ($now - $prev_call))}" < /dev/null)
    done
} #}}}

# --/ ARGUMENT PARSING
while getopts hs:e:a:n: opt; do
    case $opt in
        h) echo "$USAGE_STR"; exit 0;;
        s) _green="#${OPTARG###}";;
        e) _red="#${OPTARG###}";;
        a) _yellow="#${OPTARG###}";;
        n) _white="#${OPTARG###}";;
        ?) echo "Unknown argument $opt"; echo "$USAGE_STR" | head -n1; exit 1;;
    esac
done

# --/ START
main

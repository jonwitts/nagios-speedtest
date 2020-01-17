#! /bin/bash
#
# Script to check Internet connection speed using speedtest-cli
#
# Jon Witts and others - https://github.com/jonwitts/nagios-speedtest/
#
#########################################################################################################################################################
#
# Nagios Exit Codes
#
# 0	=	OK		= The plugin was able to check the service and it appeared to be functioning properly
# 1	=	Warning		= The plugin was able to check the service, but it appeared to be above some warning
#				threshold or did not appear to be working properly
# 2	=	Critical	= The plugin detected that either the service was not running or it was above some critical threshold
# 3	=	Unknown		= Invalid command line arguments were supplied to the plugin or low-level failures internal
#				to the plugin (such as unable to fork, or open a tcp socket) that prevent it from performing the specified operation.
#				Higher-level errors (such as name resolution errors, socket timeouts, etc) are outside of the control of plugins
#				and should generally NOT be reported as UNKNOWN states.
#
########################################################################################################################################################

plugin_name="Nagios speedtest-cli plugin"
version="1.3 2020011721:40_CW"

#####################################################################
#
#	CHANGELOG
#
#	Version 1.0 - Initial Release
#
#	Version 1.1 - Added requirement to use server id in test and need to define
#			full path to speedtest binary - thanks to Sigurdur Bjarnason
#			for changes and improvements
#
#       Version 1.2 - Added ability to check speed from an internal Speedtest Mini
#                       server. Idea sugested by Erik Brouwer
#                   - Added check for bc binary - Jorgen - jvandermeulen
#                   - Minor adjustments to help files
#                   - Change to perf data output - see https://github.com/jonwitts/nagios-speedtest/issues/2
#
#	Version 1.3 - Christian Wirtz <doc@snowheaven.de> Github: doctore74
#			- Added options:
#				- checkmk local check output -T local
#				- piggyback destination host parameter -O {HOSTNAME}
#				- return code override for usage with checkmk mk-jobs -R {0,1,2,3}
#				- checkmk servicename -S {NAME WITHOUT SPACES}
#			- Usage examples:
#			  check_speedtest-cli-check_mk.sh -p -w 50 -c 28 -W 10 -C 3 -m 100 -M 40 -l e -s 6601 -T local -O speedport -R 0 -S dsl-speed
#			  or via crontab and checkmk spool directory
#			  */90 * * * * mk-job dsl-speed /omd/sites/home/local/lib/nagios/plugins/git/nagios-speedtest/check_speedtest-cli-check_mk.sh -p -w 50 -c 28 -W 10 -C 3 -m 100 -M 40 -l e -s 6601 -O speedport -T local -R 0 -S dsl-speed > /var/lib/check_mk_agent/spool/job_dsl-speed
#####################################################################
# function to output script usage
usage()
{
	cat << EOF
	******************************************************************************************

	$plugin_name - Version: $version

	OPTIONS:
	-h	Show this message
	-w	Download Warning Level - *Required* - integer or floating point
	-c	Download Critical Level - *Required* - integer or floating point
	-W	Upload Warning Level - *Required* - integer or floating point
	-C	Upload Critical Level - *Required* - integer or floating point
        -l      Location of speedtest server - *Required * - takes either "i" or "e". If you pass "i" for
                Internal then you will need to pass the URL of the Mini Server to the "s" option. If you pass
                "e" for External then you must pass the server integer to the "s" option.
	-s	Server integer or URL for the speedtest server to test against - *Required* - Run
		"speedtest --list | less" to find your nearest server and note the number of the server
                or use the URL of an internal Speedtest Mini Server
	-p	Output Performance Data
        -m      Download Maximum Level - *Required if you request perfdata* - integer or floating point
                Provide the maximum possible download level in Mbit/s for your connection
        -M      Upload Maximum Level - *Required if you request perfdata* - integer or floating point
                Provide the maximum possible upload level in Mbit/s for your connection
	-v	Output plugin version
	-V	Output debug info for testing
	-T	Output type {local,nagios} - local = checkmk local check style
	-O	Piggyback destination host {HOSTNAME} - prints an optional piggyback section
	-R	Script returncode {0,1,2,3} - override skript returncode (f.e. for checkmk mk-job usage)
	-S	checkmk service name {without spaces!}

	This script will output the Internet Connection Speed using speedtest-cli to Nagios.

	You need to have installed speedtest-cli on your system first and ensured that it is
	working by calling "speedtest --simple".

	See here: https://github.com/sivel/speedtest-cli for info about speedtest-cli

	First you MUST define the location of your speedtest install in the script or this will
	not work.

	The speedtest-cli can take some time to return its result. I recommend that you set the
	service_check_timeout value in your main nagios.cfg  to 120 to allow time for
	this script to run; but test yourself and adjust accordingly.

	You also need to have access to bc on your system for this script to work and that it
	exists in your path.

	Your warning levels must be higher than your critical levels for both upload and download.

	Performance Data will output upload and download speed against matching warning and
	critical levels.

	Jon Witts

	******************************************************************************************
EOF
}

#####################################################################
# function to output error if speedtest binary location not set
locundef()
{
	cat << EOF
	******************************************************************************************

	$plugin_name - Version: $version

	You have not defined the location of the speedtest binary in the script! You MUST do
	this before running the script. See line 175 of the script!

	******************************************************************************************
EOF
}

#####################################################################
# function to check if a variable is numeric
# expects variable to check as first argument
# and human description of variable as second
isnumeric()
{
	re='^[0-9]+([.][0-9]+)?$'
	if ! [[ $1 =~ $re ]]; then
		echo $2" with a value of: "$1" is not a number!"
		usage
		exit 3
	fi
}

#####################################################################
# functions for floating point operations - requires bc!

#####################################################################
# Default scale used by float functions.

float_scale=3

#####################################################################
# Evaluate a floating point number expression.

function float_eval()
{
    local stat=0
    local result=0.0
    if [[ $# -gt 0 ]]; then
	result=$(echo "scale=$float_scale; $*" | bc -q 2>/dev/null)
	stat=$?
	if [[ $stat -eq 0  &&  -z "$result" ]]; then stat=1; fi
    fi
    echo $result
    return $stat
}

#####################################################################
# Evaluate a floating point number conditional expression.

function float_cond()
{
    local cond=0
    if [[ $# -gt 0 ]]; then
	cond=$(echo "$*" | bc -q 2>/dev/null)
	if [[ -z "$cond" ]]; then cond=0; fi
	if [[ "$cond" != 0  &&	"$cond" != 1 ]]; then cond=0; fi
    fi
    local stat=$((cond == 0))
    return $stat
}

########### End of functions ########################################

# Set up the variable for the location of the speedtest binary.
# Edit the line below so that the variable is defined as the location
# to speedtest on your system. On mine it is /usr/local/bin
# Ensure to leave the last slash off!
# You MUST define this or the script will not run!
STb=/usr/bin/

# Set up the variables to take the arguments
DLw=
DLc=
ULw=
ULc=
Loc=
SEs=
PerfData=
MaxDL=
MaxUL=
debug=
checktype=
piggyhost=
rc=
servicename=

# Retrieve the arguments using getopts
while getopts "hw:c:W:C:l:s:pm:M:vVT:O:R:S:" OPTION
do
	case $OPTION in
	h)
		usage
		exit 3
		;;
	w)
		DLw=$OPTARG
		;;
	c)
		DLc=$OPTARG
		;;
	W)
		ULw=$OPTARG
		;;
	C)
		ULc=$OPTARG
		;;
	l)
		Loc=$OPTARG
		;;
	s)
		SEs=$OPTARG
		;;
	p)
		PerfData="TRUE"
		;;
        m)
                MaxDL=$OPTARG
                ;;
        M)
                MaxUL=$OPTARG
                ;;
	v)
		echo "$plugin_name. Version number: $version"
		exit 3
		;;
	V)
		debug="TRUE"
		;;
	T)
		checktype=$OPTARG
		;;
	O)
		piggyhost=$OPTARG
		;;
	R)
		rc=$OPTARG
		;;
	S)
		servicename=$OPTARG
		;;

esac
done

# Check if the Speedtest binary variable $STb has been defined and exit with warning if not
if [[ -z $STb ]]
then
	locundef
	exit 3
fi

# Check for empty arguments and exit to usage if found
if  [[ -z $DLw ]] || [[ -z $DLc ]] || [[ -z $ULw ]] || [[ -z $ULc ]] || [[ -z $Loc ]] || [[ -z $SEs ]]
then
	usage
	exit 3
fi

# Check for empty upload and download maximum arguments if perfdata has been requested
if [ "$PerfData" == "TRUE" ]; then
        if [[ -z $MaxDL ]] || [[ -z $MaxUL ]]
	then
		usage
		exit 3
        fi
fi

# Check for invalid argument passed to $Loc and exit to usage if found
if [[ "$Loc" != "e" ]] && [[ "$Loc" != "i" ]]
then
	usage
	exit 3
fi

# Check for non-numeric arguments
isnumeric $DLw "Download Warning Level"
isnumeric $DLc "Download Critical Level"
isnumeric $ULw "Upload Warning Level"
isnumeric $ULc "Upload Critical Level"
# Only check upload and download maximums if perfdata requested
if [ "$PerfData" == "TRUE" ]; then
	isnumeric $MaxDL "Download Maximum Level"
	isnumeric $MaxUL "Upload Maximum Level"
fi

# Check if binary bc is installed
type bc >/dev/null 2>&1 || { echo >&2 "Please install bc binary (in order to do floating point operations)"; exit 3; }

# Check that warning levels are not less than critical levels
if float_cond "$DLw < $DLc"; then
	echo "\$DLw is less than \$DLc!"
	usage
	exit 3
elif float_cond "$ULw < $ULc"; then
	echo "\$ULw is less than \$ULc!"
	usage
	exit 3
fi

# Output arguments for debug
if [ "$debug" == "TRUE" ]; then
	echo "Download Warning Level = "$DLw
	echo "Download Critical Level = "$DLc
	echo "Upload Warning Level = "$ULw
	echo "Upload Critical Level = "$ULc
        echo "Server Location = "$Loc
        echo "Server URL or Integer = "$SEs
fi

#Set command up depending upon internal or external
if [ "$Loc" == "e" ]; then
	if [ "$debug" == "TRUE" ]; then
		echo "External Server defined"
	fi
	command=$($STb/speedtest --server=$SEs --simple)
elif [ "$Loc" == "i" ]; then
	if [ "$debug" == "TRUE" ]; then
		echo "Internal Server defined"
	fi
	command=$($STb/speedtest --mini=$SEs --simple)
else
	if [ "$debug" == "TRUE" ]; then
		echo "We should never get here as we checked the contents of Location variable earlier!"
	fi
	usage
	exit 3
fi

# Get the output of the speedtest into an array
# so we can begin to process it
i=1
typeset -a array

array=($command)

# Check if array empty or not having at least 9 indicies
element_count=${#array[@]}
expected_count="9"

# Output array indicies count for debug
if [ "$debug" == "TRUE" ]; then
	echo "count = $element_count"
fi

if [ "$element_count" -ne "$expected_count" ]; then
	echo "You do not have the expected number of indices in your output from SpeedTest. Is it correctly installed? Try running the check with the -V argument to see what is going wrong."
	usage
	exit 3
fi

# echo contents of speedtest for debug
if [ "$debug" == "TRUE" ]; then
	echo "$command"
fi

# split array into our variables for processing
ping=${array[1]}
pingUOM=${array[2]}
download=${array[4]}
downloadUOM=${array[5]}
upload=${array[7]}
uploadUOM=${array[8]}

# echo each array for debug
if [ "$debug" == "TRUE" ]; then
	echo "Ping = "$ping
	echo "Download = "$download
	echo "Upload = "$upload
fi

#set up our nagios status and exit code variables
status=
nagcode=

# now we check to see if returned values are within defined ranges
# we will make use of bc for our math!
if float_cond "$download < $DLc"; then
	if [ "$debug" == "TRUE" ]; then
		echo "Download less than critical limit. \$download = $download and \$DLc = $DLc "
	fi
	status="CRITICAL"
	nagcode=2
elif float_cond "$upload < $ULc"; then
	if [ "$debug" == "TRUE" ]; then
		echo "Upload less than critical limit. \$upload = $upload and \$ULc = $ULc"
	fi
	status="CRITICAL"
	nagcode=2
elif float_cond "$download < $DLw"; then
	if [ "$debug" == "TRUE" ]; then
		echo "Download less than warning limit. \$download = $download and \$DLw = $DLw"
	fi
	status="WARNING"
	nagcode=1
elif float_cond "$upload < $ULw"; then
	if [ "$debug" == "TRUE" ]; then
		echo "Upload less than warning limit. \$upload = $upload and \$ULw = $ULw"
	fi
	status="WARNING"
	nagcode=1
else
	if [ "$debug" == "TRUE" ]; then
		echo "Everything within bounds!"
	fi
	status="OK"
	nagcode=0
fi


# Example output
# OK - Ping = 8.841 ms Download = 87.59 Mbit/s Upload = 31.20 Mbit/s|'download'=87.59;80;55;0;105.00 'upload'=31.20;30;20;0;42.00
nagout="$status - Ping = $ping $pingUOM Download = $download $downloadUOM Upload = $upload $uploadUOM"

# append perfout if argument was passed to script
if [ "$PerfData" == "TRUE" ]; then
	if [ "$debug" == "TRUE" ]; then
		echo "PerfData requested!"
	fi
	perfout_nag="|'download'=$download;$DLw;$DLc;0;$(echo $MaxDL*1.05|bc) 'upload'=$upload;$ULw;$ULc;0;$(echo $MaxUL*1.05|bc)"
	perfout="|'download'=$download;$DLw;$DLc;0;$(echo $MaxDL*1.05|bc) 'upload'=$upload;$ULw;$ULc;0;$(echo $MaxUL*1.05|bc)"

	nagout=$nagout$perfout_nag

        NOW=`date`

        # checkmk localcheck output
        cmkout="$nagcode $servicename 'download'=$download;$DLw;$DLc;0;$(echo $MaxDL*1.05|bc)|'upload'=$upload;$ULw;$ULc;0;$(echo $MaxUL*1.05|bc) Ping = $ping $pingUOM Download = $download $downloadUOM Upload = $upload $uploadUOM $status (last run: $NOW)"

fi

# Determine if checktype is nagios or local (checkmk)
if [[ "$checktype" == "nagios" ]]; then
	echo $nagout
	exit $nagcode
else
	if [[ "$piggyhost" != "" ]]; then
		echo -e "<<<<$piggyhost>>>>"
		echo -e "<<<local>>>"
	fi

	echo $cmkout

	if [[ "$piggyhost" != "" ]]; then
		echo -e "<<<>>>"
		echo -e "<<<<>>>>"
	fi

	if [[ "$rc" != "" ]]; then
		exit $rc
	else
		exit 0
	fi
fi

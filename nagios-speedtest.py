# Script to check Internet connection speed using speedtest native client from https://www.speedtest.net/apps/cli
#
# Jon Witts and others - https://github.com/jonwitts/nagios-speedtest/
#
#####################################################################################################################################
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
#####################################################################################################################################

plugin_name = "Nagios speedtest-cli plugin"
version = "1.3 2021033013:20"

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
#   Version 1.2 - Added ability to check speed from an internal Speedtest Mini
#           server. Idea sugested by Erik Brouwer
#           - Added check for bc binary - Jorgen - jvandermeulen
#           - Minor adjustments to help files
#           - Change to perf data output - see https://github.com/jonwitts/nagios-speedtest/issues/2
#
#   Version 1.3 - Rebuilt to use speedtest native client and Python
#

#########################
# Import Python Libraries

import json, sys, getopt, subprocess, os.path

#################################
# function to output script usage
def usage():
    print("******************************************************************************************")
    print(plugin_name + " - Version: " + version)
    print("OPTIONS:")
    print("-h	Show this message")
    print("-v	Output plugin version")
    print("-w	Download Warning Level - *Required* - integer or floating point")
    print("-c	Download Critical Level - *Required* - integer or floating point")
    print("-W	Upload Warning Level - *Required* - integer or floating point")
    print("-C	Upload Critical Level - *Required* - integer or floating point")
    print("-p	Output Performance Data")
    print("    -m      Download Maximum Level - *Required if you request perfdata* - integer or floating point")
    print("            Provide the maximum possible download level in Mbit/s for your connection")
    print("    -M      Upload Maximum Level - *Required if you request perfdata* - integer or floating point")
    print("            Provide the maximum possible upload level in Mbit/s for your connection")
    print("-V	Output debug info for testing")
    print("This script will output the Internet Connection Speed using the native speedtest client to Nagios.")
    print("See here: https://www.speedtest.net/apps/cli for info about the native speedtest client\n")
    print("First you MUST define the location of your speedtest install in the script or this will not work.\n")
    print("The speedtest client can take some time to return its result. I recommend that you set the")
    print("service_check_timeout value in your main nagios.cfg  to 120 to allow time for")
    print("this script to run; but test yourself and adjust accordingly.")
    print("Your warning levels must be higher than your critical levels for both upload and download.")
    print("Performance Data will output upload and download speed against matching warning and critical levels.")
    print("Jon Witts")
    print("******************************************************************************************")

################################
# function to out script version
def versionDetails():
    print(plugin_name + " Version number: " + version)

#####################################
# function to check string for number
def is_number(s):
    try:
        float(s)
        return True
    except ValueError:
        return False

###############################################################
# function to output error if speedtest binary location not set
def locundef():
    print("******************************************************")
    print(str(plugin_name) + " - Version: " + str(version) + "\n")
    print("You have not defined the location of the speedtest binary ")
    print("in the script! You MUST do this before running the script.")
    print("******************************************************")

########### End of functions ###

# Set up the variable for the location of the speedtest binary.
# Edit the line below so that the variable is defined as the location
# to speedtest on your system. On mine it is /usr/bin/speedtest
#
# On Windows this will be somewhere else! You MUST use forward
# slashes when defining your path
# e.g. C:/Program Files/speedtest.exe
#
# You MUST define this or the script will not run!
#STb = "/usr/bin/speedtest"
STb = "F:/git repos/nagios-speedtest/speedtest.exe"

# Set starting values for variables
DLw = None
DLc = None
ULw = None
ULc = None
PerfData = False
MaxDL = None
MaxUL = None
debug = False

# Retrieve the arguments using getopt
try:
    optlist, args = getopt.getopt(sys.argv[1:], 'hw:c:W:C:pm:M:vV')
except getopt.GetoptError as err:
    print("\n" + str(err) + "\n")
    usage()
    sys.exit(3)

# Check for no args passed
if optlist == []:
    print("\nNo arguments passed!\n")
    usage()
    sys.exit(3)

# Assign the arguments to our local variables
for o, a in optlist:
    if o == "-V":
        debug = True
    elif o == "-p":
        PerfData = True
    elif o == "-h":
        usage()
        sys.exit(3)
    elif o == "-v":
        versionDetails()
        sys.exit(3)
    elif o == "-w":
        DLw = a
    elif o == "-c":
        DLc = a
    elif o == "-W":
        ULw = a
    elif o == "-C":
        ULc = a
    elif o == "-m":
        MaxDL = a
    elif o == "-M":
        MaxUL = a
    else:
        # unknown arg passed
        print("\nUnknown arguments passed!\n")
        usage()
        sys.exit(3)

# Check if the Speedtest binary variable STb has been defined and exit with warning if not
if STb == None:
    locundef()
    sys.exit(3)

# Check if the speedtest binary exists at the defined location
if not os.path.exists(STb):
    print("\nThe speedtest binary does not appear to be at the defined location:\n")
    print(STb)
    print("\nYou MUST fix this!\n")
    usage()
    sys.exit(3)

# Check for empty arguments and exit to usage if found
if None in (DLw, DLc, ULw, ULc):
    print("\nEmpty value passed to either -w, -c, -W or -C!\n")
    usage()
    sys.exit(3)

# Check for empty upload and download maximum arguments if perfdata has been requested
if PerfData == True:
    if None in (MaxDL, MaxUL):
        print("\nEmpty value passed to either -m or -M!\n")
        usage()
        sys.exit(3)

# Check for non-numeric arguments
if not is_number(DLw):
    print("\nDLw is not numeric!\n")
    usage()
    sys.exit(3)
if not is_number(DLc):
    print("\nDLc is not numeric!\n")
    usage()
    sys.exit(3)
if not is_number(ULw):
    print("\nULw is not numeric!\n")
    usage()
    sys.exit(3)
if not is_number(ULc):
    print("\nULc is not numeric!\n")
    usage()
    sys.exit(3)

# Only check upload and download maximums if perfdata requested
if PerfData == True:
    if not is_number(MaxDL):
        print("\nMaxDL is not numeric!\n")
        usage()
        sys.exit(3)
    if not is_number(MaxUL):
        print("\nMaxUL is not numeric!\n")
        usage()
        sys.exit(3)

# Check that warning levels are not less than critical levels
if float(DLw) < float(DLc):
    print("\nDLw is less than DLc!\n")
    usage()
    sys.exit(3)
if float(ULw) < float(ULc):
    print("\nULw is less than ULc!\n")
    usage()
    sys.exit(3)

# Output arguments for debug
if debug == True:
    print("\nDownload Warning Level = " + str(DLw))
    print("Download Critical Level = " + str(DLc))
    print("Upload Warning Level = " + str(ULw))
    print("Upload Critical Level = " + str(ULc) + "\n")
    if PerfData == True:
        print("Maximum Download Level = " + str(MaxDL))
        print("Maximum Upload Level = " + str(MaxUL) + "\n")

# display STb for debug
if debug == True:
    print("\nExecuting Speedtest binary from: " + STb + "\n")

# Launch the speedtest binary and capture the result
try:
    data = subprocess.run([STb, "-f", "json"], capture_output=True)
except subprocess.CalledProcessError as err:
    print("\n" + err.output + "\n")
    usage()
    sys.exit(3)

# parse returned data
obj = json.loads(data.stdout)

# read values
ping = round(obj['ping']['latency'], 2)
dlBw = round(obj['download']['bandwidth'] * 8e-6, 2)
ulBw = round(obj['upload']['bandwidth'] * 8e-6, 2)

# print values for debug
if (debug == True):
    print("ping latency:", ping, "ms")
    print("download bandwidth:" ,dlBw, "Mbps")
    print("upload bandwidth:" ,ulBw, "Mbps\n")

# now we check to see if returned values are within defined ranges
if (dlBw < float(DLc)):
	if (debug == True):
		print("Download less than critical limit. dlBw = " + str(dlBw) + " and DLc = " + str(DLc))
	status = "CRITICAL"
	nagcode = 2
elif (ulBw < float(ULc)):
	if (debug == True):
		print("Upload less than critical limit. ulBw = " + str(ulBw) + " and ULc = " + str(ULc))
	status = "CRITICAL"
	nagcode = 2
elif (dlBw < float(DLw)):
	if (debug == True):
		print("Download less than warning limit. dlBw = " + str(dlBw) + " and DLw = " + str(DLw))
	status = "WARNING"
	nagcode = 1
elif (ulBw < float(ULw)):
	if (debug == True):
		print("Upload less than warning limit. ulBw = " + str(ulBw) + " and ULw = " + str(ULw))
	status = "WARNING"
	nagcode = 1
else:
	if (debug == True):
		print("Everything within bounds!\n")
	status = "OK"
	nagcode = 0

nagout = status + " - Ping = " + str(ping) + "ms Download = " + str(dlBw) + " Mpbs Upload = " + str(ulBw) + " Mpbs"

# append perfout if argument was passed to script
if (PerfData == True):
	if (debug == True):
		print("PerfData requested!\n")
	perfout = "|'download'=" + str(dlBw) + ";" + str(DLw) + ";" + str(DLc) + ";0;" + str(float(MaxDL)*1.05) + "'upload'=" + str(ulBw) + ";" + str(ULw) + ";" + str(ULc) + ";0;" + str(float(MaxUL)*1.05)
	nagout = nagout + perfout

print(nagout)
sys.exit(nagcode)

import os, json, sys

# Set up the variables to take the arguments
DLw = 100
DLc = 90
ULw = 30
ULc = 20
#Loc =
#SEs =
PerfData = True
MaxDL = 200
MaxUL = 50
debug = False

# write speedtest to file
os.system("speedtest -f json > nagios-speed.json")

# read file
with open('nagios-speed.json', 'r') as myfile:
    data=myfile.read()

# parse file
obj = json.loads(data)

# read values
ping = round(obj['ping']['latency'], 2)
dlBw = round(obj['download']['bandwidth'] * 8e-6, 2)
ulBw = round(obj['upload']['bandwidth'] * 8e-6, 2)

# print values for debug
if (debug == True):
    print("ping latency:", ping, "ms")
    print("download bandwidth:" ,dlBw, "Mbps")
    print("upload bandwidth:" ,ulBw, "Mbps")

# now we check to see if returned values are within defined ranges
if (dlBw < DLc):
	if (debug == True):
		print("Download less than critical limit. dlBw = " + str(dlBw) + " and DLc = " + str(DLc))
	status = "CRITICAL"
	nagcode = 2
elif (ulBw < ULc):
	if (debug == True):
		print("Upload less than critical limit. ulBw = " + str(ulBw) + " and ULc = " + str(ULc))
	status = "CRITICAL"
	nagcode = 2
elif (dlBw < DLw):
	if (debug == True):
		print("Download less than warning limit. dlBw = " + str(dlBw) + " and DLw = " + str(DLw))
	status = "WARNING"
	nagcode = 1
elif (ulBw < ULw):
	if (debug == True):
		print("Upload less than warning limit. ulBw = " + str(ulBw) + " and ULw = " + str(ULw))
	status = "WARNING"
	nagcode = 1
else:
	if (debug == True):
		print("Everything within bounds!")
	status = "OK"
	nagcode = 0

nagout = status + " - Ping = " + str(ping) + "ms Download = " + str(dlBw) + " Mpbs Upload = " + str(ulBw) + " Mpbs"

# append perfout if argument was passed to script
if (PerfData == True):
	if (debug == True):
		print("PerfData requested!")
	perfout = "|'download'=" + str(dlBw) + ";" + str(DLw) + ";" + str(DLc) + ";0;" + str(MaxDL*1.05) + "'upload'=" + str(ulBw) + ";" + str(ULw) + ";" + str(ULc) + ";0;" + str(MaxUL*1.05)
	nagout = nagout + perfout

print(nagout)
sys.exit(nagcode)
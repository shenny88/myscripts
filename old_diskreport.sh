#!/bin/bash
#========================================================================================================================
# Abstract:     List largest and last modified files in a directory                                                      
#                                                                                                                        
# Usage:        diskusage_new.sh <directory path>                                                                       
#                                                                                                                        
# Description:  This script will be triggered via patrol in the event of a disk space alert in a Linux Server partition. 
#		A directory should be supplied as argument to the script. Script works using find command .It will       
#		first print the list of top 20 large sized files in the directory supplied and also list the files       
#		that are created/modified within the last 6 hours.                                                      
#                                                                                                                        
# Author:       SysOPS IND                                                                                              
#                                                                                                                        
# Changes:      12.01.2017,     v1                                                                                       
#               27.12.2017,	  v1.1                                                                                     
#               27.04.2020,     v1.2   Shenny                                                                           
#========================================================================================================================

# defining colors
red=$(tput setaf 1)
green=$(tput setaf 2)
blue=$(tput setaf 4)
reset=$(tput sgr0)

#function for executing bash trap
cleanup() {
rm /tmp/filesys >/dev/null 2>&1
rm /tmp/findresult >/dev/null 2>&1
}

# Output styling
printline() {
echo -e "${blue}--------------------------------------------------------------------${reset}"
echo ""
}

dateconv() {
#convert time to seconds. Calculated from the time of epoch
#eg: stat -c %y file
#	  2017-07-11 10:49:35.836126595 +0200
#    stat -c %y file | sed 's/ \+[^ ]\+$//' | awk -F. '{if(NF)NF--}1'
#	  2017-07-11 10:49:35
#    date -d "2017-07-11 10:49:35" '+%s'
#	  1499762975
filedate=$(stat -c %y "$1" | sed 's/ \+[^ ]\+$//' | awk -F. '{if(NF)NF--}1')
filetime=$(date -d "$filedate" '+%s' )
return "$filetime"
}

nullcheck() {
echo ""
echo -e "${red}usage: diskusage_find.sh [directory]${reset}"
echo ""
}

result="/tmp/findresult"
checkfs="$1"
trap cleanup EXIT

((!$#)) && { nullcheck ; exit; }
[ ! -d "$checkfs" ] && echo -e "${red}----------Directory:$checkfs doesn't exist-------------${reset}" && exit

echo ""
printline;
echo -e "${green}$(hostname -f)${reset} $(date) user:${green}$(whoami)${reset}"
echo ""
printline;
echo -e "${blue}------------------------Current Disk Usage--------------------------${reset}"
df -hP "$checkfs"
printline
find "$(readlink -f ${checkfs})" -xdev -type f -exec du -Sh {} \+ | sort -rh >"$result"
echo "${blue}-----------------------Largest top 20 files-------------------------${reset}"
head -20 "$result"
printline;
echo "${blue}------Newly created/modified files with in the above list for the last 24 hours >=100MB------${reset}"
for file in $(awk '{print $2}' $result| head -20);do
	dateconv "${file}"
	currtime=$(date -d "$(date +%Y-%m-%d\ %H:%M:%S)" '+%s')
	((diff = currtime - filetime))
	size=$(stat -c %s "${file}")
	if [[ ( "$diff" -le  86400 ) && (  "$size" -ge 104857600 ) ]];then
		ls -ltrh "$file"
	fi
done
printline

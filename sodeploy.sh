#!/bin/bash
#=================================================================================================#
# Abstract    :   Script to push scripts in git to all servers					  #
# Usage       :   ./sodeploy <option> <argument>						  #
# Description :   Scipt will clone the script repo in git locally in test-train212 server and	  #
#                 scp it to all backend servers. ssh key of root needs to copied to authorized    #
#                 list of patrol user in remote server. For more script usage related information #
#                 execute sodeploy -h								  #
# Add. Info   :   In Progress.									  #
# Author      :   SysOps									  #
# Changes     :   08-May-2020, Shenny R S       Initial version:v1				  #
#=================================================================================================#


#Highlighting colors
red=$(tput setaf 1)
green=$(tput setaf 2)
reset=$(tput sgr0)

#Server groups
acs=( ffdc10002.srv.company ffdc10003.srv.company aqb20397.srv.company )
cee=( aqb20242.srv.company aqb20244.srv.company )
tur=( coretestlinx.company-tur.serv coretestlinx1.company-tur.serv corepreprodlinx1.company-tur.serv corepreprodlinx2.company-tur.serv coreprodlinx1.company-tur.serv coreprodlinx2.company-tur.serv )
uwp=( aqb20241.srv.company l0000045.srv.company )
edp=( aqb20243.srv.company aqb70065.srv.company )
scb=( preprodlinx01.adssg.ase1.aws.mytec.cloud.company preprodlinx02.adssg.ase1.aws.mytec.cloud.company testlinx01.adssg.ase1.aws.mytec.cloud.company prodlinx01.adssg.ase1.aws.mytec.cloud.company prodlinx02.adssg.ase1.aws.mytec.cloud.company )
waa=( aqb20238.srv.company aqb20747.srv.company )
azg=( aqb20398.srv.company aqb20399.srv.company )
dev=( ffdc10002.srv.company aqb20397.srv.company aqb20238.srv.company  aqb20242.srv.company aqb20243.srv.company aqb20398.srv.company aqb20241.srv.company aqb70049.srv.company aqb70050.srv.company preprodlinx01.adssg.ase1.aws.mytec.cloud.company preprodlinx02.adssg.ase1.aws.mytec.cloud.company testlinx01.adssg.ase1.aws.mytec.cloud.company coretestlinx.company-tur.serv coretestlinx1.company-tur.serv corepreprodlinx1.company-tur.serv corepreprodlinx2.company-tur.serv 
prod=( ffdc10003.srv.company aqb20747.srv.company aqb20244.srv.company aqb70065.srv.company aqb20399.srv.company l0000045.srv.company prodlinx01.adssg.ase1.aws.mytec.cloud.company prodlinx02.adssg.ase1.aws.mytec.cloud.company coreprodlinx1.company-tur.serv coreprodlinx2.company-tur.serv )
train=( test-train1.aws.company.at test-train2.aeat.company.at )
all=( "${prod[@]}" "${dev[@]}" "${train[@]}" )
grouplist=( acs cee tur uwp edp scb waa azg dev prod train all )

user=patrol
git_tmp_dir="$(mktemp -d /tmp/git-XXXXXXXX)"
git_repo_url="git@lx-git001.aeat.company.at:sysopsind/scripts.git"
#git_repo_url="git@github.com:shenny88/foss.git"

status-ok() {
printf '%-30s %s\n' "[${green}OK${reset}]" "$@"
}

status-notok() {
printf '%-30s %s\n' "[${red}NOT OK${reset}]" "$@"
}

usage() {
echo -e "Usage:\t$0 <option>"
echo -e "\t$0 -a"
echo -e "\t$0 -g <server-group>"
echo -e "\t$0 -h"
echo -e "\t$0 -s <FQDN>\n"
echo -e "Options:"
echo -e "-a\tScripts will be pushed to all servers"
echo -e "-g\tScripts will be pushed to required groups.Defined groups are prod,dev,train,acs,cee,tur,uwp,edp,scb,waa,azg"
echo -e "-s\tScripts will be pushed to mentioned server.FQDN of server should be passed as argument"
echo -e "-h\tScript usage\n"
exit
}

gitpush() {
local group="$1"
case "$group" in
   all)  server_list=( "${all[@]}" ) ;;
   prod) server_list=( "${prod[@]}" ) ;;
   dev)  server_list=( "${dev[@]}" ) ;;
   train)server_list=( "${train[@]}" ) ;;
   acs)  server_list=( "${acs[@]}" ) ;;
   cee)  server_list=( "${cee[@]}" ) ;;
   tur)  server_list=( "${tur[@]}" ) ;;
   uwp)  server_list=( "${uwp[@]}" ) ;;
   edp)  server_list=( "${edp[@]}" ) ;;
   scb)  server_list=( "${scb[@]}" ) ;;
   waa)  server_list=( "${waa[@]}" ) ;;
   azg)  server_list=( "${azg[@]}" ) ;;
   *)    for i in "${all[@]}";do
            if [ "$i" == "$group" ];then
               server_list="${group}"
               RC=0
	       break
            else
               RC=101
            fi
         done
	 [ "$RC" -eq 101 ] && usage 
         ;;
esac
   
if git clone --quiet "$git_repo_url" "$git_tmp_dir" >/dev/null;then 
   status-ok "Git clonned to ${git_tmp_dir}"
   chown -R $user. "$git_tmp_dir"
   find "$git_tmp_dir" -maxdepth 1 -type f -exec chmod a+x {} \;
else
   status-notok "Git clonning failed"
   exit 101
fi

for server in "${server_list[@]}";do
  echo -e "\n\tCopying to ${server}"
  echo -e "------------------------------------------------------------"
  for script in "$git_tmp_dir"/*;do
   ssh "$user"@"$server" mkdir "$git_tmp_dir" 2>/dev/null
   if scp -q "$script" "$user"@"$server":"$git_tmp_dir" 2>/dev/null;then 
      status-ok "Copied ${script} to ${server}:${script}"
      if ssh "$user"@"$server" cp "$script" /opt/company/bin/ 2>/dev/null;then
      	 status-ok "Copied ${server}:${script} to ${server}:/opt/company/bin"
      else
     	 status-notok "Copying ${script} to ${server}:/opt/company/bin failed"
      fi	 
   else
      status-notok "Copying ${script} to ${server} failed"
   fi
  done
done
}

#root user check
[ $(whoami) != "root" ] && echo -e "\nI need to be root in lx-tagl12.aeat.company.at to execute this script\n" && exit 101

#Exit if no argument is passed
((!$#)) && { usage ; exit; }

while getopts ":ag:hs:" option;do
   case "${option}" in
      a) gitpush all ;;
      g) group="${OPTARG}"
         for entry in "${grouplist[@]}";do
	    if [ "$entry" == "$group" ];then
		gitpush "$group"
		RC=0
		break
	    else
		RC=101
	    fi
	 done
	 [ "$RC" -eq 101 ] && usage ;;
      h) usage ;;
      s) remote_server="${OPTARG}"
         gitpush "$remote_server"   ;;
      ?) usage ;;
   esac
done

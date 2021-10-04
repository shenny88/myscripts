#!/bin/bash

#Highlighting colors
red=$(tput setaf 1)
green=$(tput setaf 2)
reset=$(tput sgr0)

error="$(mktemp /tmp/err.XXXX)"
mail2admin="$(mktemp /tmp/mail.XXXX)"
export MAIL_CONFIG=/etc/postfix-sys

while read -r mounts;do
  touchfile="$(mktemp ${mounts}/rocheck.XXXX 2>$error)"
  if [ "$?" -ne 0 ];then
    if $(grep -qE "Permission denied" "$error");then
      printf '%-15s %s\n' "[${green}Read/Write${reset}]" "${mounts}"
    else
      printf '%-15s %s\n' "[${red}Read Only${reset}]" "${mounts}" |tee -a "$2mail"
      romount="${mounts}"
    fi
  else
    printf '%-15s %s\n' "[${green}Read/Write${reset}]" "${mounts}"
  fi
  find "$mounts" -maxdepth 1 -name $(echo $touchfile| awk -F"/" '{print $NF}') -delete 2>/dev/null
done< <(df -hP | grep -E "shared|microfocus|ctm|db2|pmf" | awk '{print $NF}')

[ -s "${mail2admin}" ] && nail -s "$(hostname): $romount changed to read only" -r"<readonly@$(hostname)>" "shenny.ramachandran-sulabha@company.at" < "$mail2admin"

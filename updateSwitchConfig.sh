#!/usr/bin/env bash

host="$1"

conf_file="$(dirname "$0")/config.sh"
if [[ ! -e "$conf_file" ]]; then
	echo "Missing config.sh; see config.sh.example" >&2
	exit 1
fi
. "$(dirname "$0")/config.sh"


case "$host" in
	switch[01].home)
		echo -n ''
	;;
	*)
		echo "Invalid switch name or switch name not specified" >&2
		echo "Example: $0 switch0.home" >&2
		exit 1
	;;
esac

config="$(mktemp)"
cat > "$config"

cookie_jar=$(mktemp)

## Log in
curl -s "http://$host/nikola_login.html" \
  --data-raw "uname=$( echo -n "$CISCO_SG200_AUTH_USERNAME" | urlencode )&pwd2=$( echo -n "$( echo -n "$( echo -n "$CISCO_SG200_AUTH_PASSWORD" | base64 )" | urlencode )" )&language_selector=en-US&err_flag=0&err_msg=&passpage=nikola_main2.html&failpage=nikola_login.html&submit_flag=0" \
  -o /dev/null \
  --cookie-jar "$cookie_jar"

if ! grep -qE '\s+SID\s+' "$cookie_jar"; then
	echo "Unable to log in. Perhaps wait 5 minutes (or whatever the session timeout value is) and try again." >&2
	rm -f "$cookie_jar" "$config"
	exit 1
fi

#cat "$cookie_jar"

curl "http://$host/FileManagementSaveConfigurationSG.html/a1" \
  -H 'Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7' \
  -H 'Accept-Language: en-US,en;q=0.9' \
  -H 'Connection: keep-alive' \
  -H "Origin: http://$host" \
  -H "Referer: http://$host/FileManagementSaveConfigurationSG.html" \
  -H 'User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/111.0.0.0 Safari/537.36' \
  -s \
  -L \
  --cookie "$cookie_jar" \
  -F "v_1_1_1=HTTP" \
  -F "v_1_2_1=Enable" \
  -F "v_1_3_1=Enable" \
  -F "v_1_4_1=Text Configuration" \
  -F "v_1_29_1=XIE_UI_ENUMVAL1" \
  -F ".v_1_38_2_handle=@$config;filename=switch-config" \
  -F "v_1_9_1=XIE_UI_ENUMVAL1" \
  -F "v_1_10_2=startup-config" \
  -F "v_1_10_3=startup-config" \
  -F "v_1_10_4=startup-config" \
  -F "v_1_10_7=" \
  -F "v_1_11_3=1" \
  -F "v_1_11_5=256000" \
  -F "v_1_101_1=NLS ERROR" \
  -F "submit_flag=8" \
  -F "submit_target=FileManagementSaveConfigurationSG.html" \
  -F "err_flag=0" \
  -F "err_msg=" \
  -F "dbgopt=0" \
  -F "v_1_12_1=Apply" \
  --compressed \
  --insecure \
  >/dev/null

rm -f "$cookie_jar"
exit


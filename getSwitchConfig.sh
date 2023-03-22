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

cookie_jar=$(mktemp)
config=$(mktemp)

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


## Download running config
curl "http://$host/FileManagementSaveConfigurationSG.html/a1" \
  -s \
  -L \
  -H 'Content-Type: multipart/form-data; boundary=----WebKitFormBoundary3q6Dt19oWcDu50UA' \
  --cookie "$cookie_jar" \
  --data-raw $'------WebKitFormBoundary3q6Dt19oWcDu50UA\r\nContent-Disposition: form-data; name="v_1_100_1"\r\n\r\n<EMWEB_STRING C=\'return ewaNLSStringGet(ewsContext, DEF_NLS_Common_Common_Id1);\'>\r\n------WebKitFormBoundary3q6Dt19oWcDu50UA\r\nContent-Disposition: form-data; name="v_1_1_1"\r\n\r\nHTTP\r\n------WebKitFormBoundary3q6Dt19oWcDu50UA\r\nContent-Disposition: form-data; name="v_1_1_1"\r\n\r\nHTTP\r\n------WebKitFormBoundary3q6Dt19oWcDu50UA\r\nContent-Disposition: form-data; name="v_1_2_1"\r\n\r\nEnable\r\n------WebKitFormBoundary3q6Dt19oWcDu50UA\r\nContent-Disposition: form-data; name="v_1_2_1"\r\n\r\nEnable\r\n------WebKitFormBoundary3q6Dt19oWcDu50UA\r\nContent-Disposition: form-data; name="v_1_3_1"\r\n\r\nDisable\r\n------WebKitFormBoundary3q6Dt19oWcDu50UA\r\nContent-Disposition: form-data; name="v_1_3_1"\r\n\r\nDisable\r\n------WebKitFormBoundary3q6Dt19oWcDu50UA\r\nContent-Disposition: form-data; name="v_1_4_1"\r\n\r\nText Configuration\r\n------WebKitFormBoundary3q6Dt19oWcDu50UA\r\nContent-Disposition: form-data; name="v_1_4_2"\r\n\r\nConfig script\r\n------WebKitFormBoundary3q6Dt19oWcDu50UA\r\nContent-Disposition: form-data; name="v_1_18_2"\r\n\r\nrunning-config\r\n------WebKitFormBoundary3q6Dt19oWcDu50UA\r\nContent-Disposition: form-data; name="v_1_19_1"\r\n\r\nXIE_UI_ENUMVAL1\r\n------WebKitFormBoundary3q6Dt19oWcDu50UA\r\nContent-Disposition: form-data; name="v_1_19_1"\r\n\r\nXIE_UI_ENUMVAL1\r\n------WebKitFormBoundary3q6Dt19oWcDu50UA\r\nContent-Disposition: form-data; name="v_1_29_1"\r\n\r\nXIE_UI_ENUMVAL1\r\n------WebKitFormBoundary3q6Dt19oWcDu50UA\r\nContent-Disposition: form-data; name="v_1_29_1"\r\n\r\nXIE_UI_ENUMVAL1\r\n------WebKitFormBoundary3q6Dt19oWcDu50UA\r\nContent-Disposition: form-data; name="v_1_10_2"\r\n\r\nrunning-config\r\n------WebKitFormBoundary3q6Dt19oWcDu50UA\r\nContent-Disposition: form-data; name="v_1_10_3"\r\n\r\nrunning-config\r\n------WebKitFormBoundary3q6Dt19oWcDu50UA\r\nContent-Disposition: form-data; name="v_1_10_4"\r\n\r\nrunning-config\r\n------WebKitFormBoundary3q6Dt19oWcDu50UA\r\nContent-Disposition: form-data; name="v_1_10_7"\r\n\r\n\r\n------WebKitFormBoundary3q6Dt19oWcDu50UA\r\nContent-Disposition: form-data; name="v_1_11_4"\r\n\r\n1\r\n------WebKitFormBoundary3q6Dt19oWcDu50UA\r\nContent-Disposition: form-data; name="v_1_11_5"\r\n\r\n256000\r\n------WebKitFormBoundary3q6Dt19oWcDu50UA\r\nContent-Disposition: form-data; name="v_1_101_1"\r\n\r\nNLS ERROR\r\n------WebKitFormBoundary3q6Dt19oWcDu50UA\r\nContent-Disposition: form-data; name="submit_flag"\r\n\r\n8\r\n------WebKitFormBoundary3q6Dt19oWcDu50UA\r\nContent-Disposition: form-data; name="submit_target"\r\n\r\nFileManagementSaveConfigurationSG.html\r\n------WebKitFormBoundary3q6Dt19oWcDu50UA\r\nContent-Disposition: form-data; name="err_flag"\r\n\r\n0\r\n------WebKitFormBoundary3q6Dt19oWcDu50UA\r\nContent-Disposition: form-data; name="err_msg"\r\n\r\n\r\n------WebKitFormBoundary3q6Dt19oWcDu50UA\r\nContent-Disposition: form-data; name="dbgopt"\r\n\r\n0\r\n------WebKitFormBoundary3q6Dt19oWcDu50UA\r\nContent-Disposition: form-data; name="v_1_12_3"\r\n\r\nApply\r\n------WebKitFormBoundary3q6Dt19oWcDu50UA--\r\n' \
  -o "$config"

grep . "$config" | cat
rm -f "$cookie_jar"
rm -f "$config"
exit


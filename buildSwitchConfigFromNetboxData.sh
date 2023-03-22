#!/usr/bin/env bash

conf_file="$(dirname "$0")/config.sh"
if [[ ! -e "$conf_file" ]]; then
	echo "Missing config.sh; see config.sh.example" >&2
	exit 1
fi
. "$(dirname "$0")/config.sh"

. "$NETBOX_CLI_INIT_SH"

main(){

	device_name="$1"
	if [[ -z "$device_name" ]]; then
		echo "Usage: $0 switchname.home" >&2
		exit 1
	fi

	device_json=$( netbox get "/dcim/devices/?name=$device_name&platform=cisco-sg200&status=active" | jq_notnull .results[0] )
	device_id=$( echo "$device_json" | jq_notnull -r .id )

	interface_mgmt_json=$( netbox get "/dcim/interfaces/?device_id=$device_id&name=management" | jq_notnull .results[0] )
	interface_mgmt_id=$( echo "$interface_mgmt_json" | jq_notnull .id )
	interface_mgmt_macaddr=$( echo "$interface_mgmt_json" | jq_notnull -r .mac_address )
	interface_mgmt_vlan_vid=$( echo "$interface_mgmt_json" | jq_notnull -r .untagged_vlan.vid )

	ipaddress_mgmt_json=$( netbox get "/ipam/ip-addresses/?interface_id=$interface_mgmt_id" | jq_notnull .results[0] )
	ipaddress_mgmt_cidr=$( echo "$ipaddress_mgmt_json" | jq_notnull -r .address )
	ipaddress_mgmt_ip=$( echo "$ipaddress_mgmt_cidr" | cut -d/ -f1 )
	ipaddress_mgmt_subnet=$( calculateSubnetFromNetmask "$( echo "$ipaddress_mgmt_cidr" | cut -d/ -f2 )" )
	ipaddress_mgmt_gateway=$( netbox get "/ipam/ip-addresses/?tag=gateway&parent=$ipaddress_mgmt_cidr" | jq_notnull -r .results[0].address | cut -d/ -f1 )

	config=$(mktemp)

	printf '!Netbox-Generated Configuration:\n' > $config
	printf '!Generated                "%s"\n' "$( date "+%Y-%m-%d %H:%M:%S" )" >> $config
	printf '!\n' >> $config

	printf 'network protocol none\n' >> $config
	printf 'network parms %s %s %s\n' "$ipaddress_mgmt_ip" "$ipaddress_mgmt_subnet" "$ipaddress_mgmt_gateway" >> $config

	buildVlanConfig "$device_id" >> $config

	printf 'ip http session soft-timeout 30\n' >> $config

	# begin "configure" section
	printf 'configure\n' >> $config
	printf 'clock summer-time recurring USA zone CDT\n' >> $config
	printf 'clock timezone -6 minutes 0 zone CST\n' >> $config
	printf 'ip domain name home\n' >> $config
	printf 'ip name server 10.0.2.10\n' >> $config

	# user auth
	echo "$device_json" | jq -r '.config_context.config.users[] | "username \"" + .username + "\" password " + .password + " encrypted override-complexity-check"' >> $config

	printf 'authentication dot1x none\n' >> $config

	printf 'spanning-tree configuration name "%s"\n' "$( echo "$interface_mgmt_macaddr" | tr '[a-z]' '[A-Z]' | tr ':' '-' )" >> $config
	echo "$device_json" | jq -r '.local_context_data.config["spanning-tree"][] | "spanning-tree " + .name + " " + (.value|tostring)' >> $config

	printf 'set hostname "%s"\n' "$( echo "$device_name" | cut -d. -f1 )" >> $config
	printf 'set location "%s"\n' "$( echo "$device_json" | jq_notnull -r .location.name )" >> $config
	printf '!\n' >> $config
	printf 'bridge aging-time 30\n' >> $config

	buildInterfaceConfig "$device_id" >> $config

	# add custom interfaces after the normal ones
	echo "$device_json" | jq -r '.config_context.config.interfaces[] | "interface " + .name + "\n" + .config + "\nexit"' 2>/dev/null >> $config

	# end of "configure" section
	printf 'exit\n' >> $config

	printf 'network mgmt_vlan %s\n' "$interface_mgmt_vlan_vid" >> $config

	cat "$config"
	rm -f "$config"
}


buildVlanConfig(){
	device_id=$1

	interfaces_json=$( netbox get "/dcim/interfaces/?device_id=$device_id" | jq_notnull .results )

	# 200,555,1234
	vlan_ids=$( echo "$interfaces_json" | jq '.[] | .tagged_vlans[].vid, .untagged_vlan.vid' | grep -E '^[0-9]+$' | sort -h | uniq | grep -vE '^1$' | tr '\n' ',' | sed 's/,$//' )

	printf 'vlan database\n'
	printf "vlan %s\n" "$vlan_ids"

	# vlan name 200 "Something" (one line per vlan)
	echo "$interfaces_json" \
	| jq -r '.[] | ( .tagged_vlans[] | (.vid|tostring) + " " + "\"" + .name + "\"" ), ( .untagged_vlan | (.vid|tostring) + " " + "\"" + .name + "\"" )' \
	| grep -E '^[0-9]+' \
	| sort -h \
	| uniq \
	| grep -vE '^1 ' \
	| sed 's/^/vlan name /'

	printf 'exit\n'
}

buildInterfaceConfig(){
	device_id=$1

	for interface_name in g{1..8}; do
		interface_json=$( netbox get "/dcim/interfaces/?device_id=$device_id&name=$interface_name" | jq_notnull -r .results[0] )

		printf 'interface %s\n' "$interface_name"

		# adds any custom config into the interface definition
		echo "$interface_json" \
		| jq '""+.custom_fields.port_configuration' \
		| sed -e 's/\\r\\n/\\n/g' \
		| jq -r \
		| grep . \
		| cat

		# this is due to the odd way that vlan1 behaves. might not be necessary. shrug.
		if [[ "$( echo "$interface_json" | jq_notnull -r .untagged_vlan.vid )" -ne 1 ]]; then
			printf "switchport trunk native-vlan %s\n" "$( echo "$interface_json" | jq_notnull -r .untagged_vlan.vid )"

			if ! echo "$interface_json" | jq -r '.tagged_vlans[].vid' | grep -qE '^1$'; then
				printf 'switchport trunk allowed vlan remove 1\n'
			fi
		fi

		tagged_vlans=$( echo "$interface_json" | jq -r '.tagged_vlans[].vid' | tr '\n' ',' | sed 's/,$//' )
		if [[ ! -z "$tagged_vlans" ]]; then
			printf 'switchport trunk allowed vlan add %s\n' "$tagged_vlans"
		fi

		printf 'exit\n'

	done

}

_jq(){
	text=$(</dev/stdin)
	json=$( echo "$text" | jq "$@" )
	if [[ -z "$json" ]]; then
		echo "Invalid JSON data. Text below:" >&2
		cat "$text" >&2
		echo "-------------------------------" >&2
		echo >&2
		exit 1
	fi
	echo "$json"
}

# same as jq, but it checks for null and barfs
jq_notnull(){
	text=$(</dev/stdin)
	json=$( echo "$text" | jq "$@" )
	if [[ "$json" == "null" || -z "$json" ]]; then
		printf '\e[1;31m%s\e[0m\n' "Invalid JSON data" >&2
		echo "jq $@" >&2
		echo "$text" >&2
		exit 1
	fi
	echo "$json"
}

# calculateSubnetFromNetmask 24 => 255.255.255.0
calculateSubnetFromNetmask(){
	case "$1" in
		0)  echo 0.0.0.0         ;;
		1)  echo 128.0.0.0       ;;
		2)  echo 192.0.0.0       ;;
		3)  echo 224.0.0.0       ;;
		4)  echo 240.0.0.0       ;;
		5)  echo 248.0.0.0       ;;
		6)  echo 252.0.0.0       ;;
		7)  echo 254.0.0.0       ;;
		8)  echo 255.0.0.0       ;;
		9)  echo 255.128.0.0     ;;
		10) echo 255.192.0.0     ;;
		11) echo 255.224.0.0     ;;
		12) echo 255.240.0.0     ;;
		13) echo 255.248.0.0     ;;
		14) echo 255.252.0.0     ;;
		15) echo 255.254.0.0     ;;
		16) echo 255.255.0.0     ;;
		17) echo 255.255.128.0   ;;
		18) echo 255.255.192.0   ;;
		19) echo 255.255.224.0   ;;
		20) echo 255.255.240.0   ;;
		21) echo 255.255.248.0   ;;
		22) echo 255.255.252.0   ;;
		23) echo 255.255.254.0   ;;
		24) echo 255.255.255.0   ;;
		25) echo 255.255.255.128 ;;
		26) echo 255.255.255.192 ;;
		27) echo 255.255.255.224 ;;
		28) echo 255.255.255.240 ;;
		29) echo 255.255.255.248 ;;
		30) echo 255.255.255.252 ;;
		31) echo 255.255.255.254 ;;
		32) echo 255.255.255.255 ;;
	esac
}

main "$@"

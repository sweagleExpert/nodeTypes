#!/usr/bin/env bash
#
# SCRIPT: import_node_types.sh
# AUTHOR: dimitris@sweagle.com, filip@sweagle.com
# DATE:   July 2019
# REV:    1.1.D (Valid are A, B, D, T, Q, and P)
#               (For Alpha, Beta, Dev, Test, QA, and Production)
#
# PLATFORM: Not platform dependent
#
# REQUIREMENTS:	- jq is required for this shell script to work.
#               (see: https://stedolan.github.io/jq/)
#				- tested in bash 4.4 on Mac OS X
#
# PURPOSE:	Load NODES types stored as json files, and located in directory provided as input
#
# REV LIST:
#        DATE: DATE_of_REVISION
#        BY:   AUTHOR_of_MODIFICATION
#        MODIFICATION: Describe what was modified, new features, etc--
#
#   201109 - Dimitris - Add Allowed children API for creation
#
# set -n   # Uncomment to check script syntax, without execution.
#          # NOTE: Do not forget to put the # comment back in or
#          #       the shell script will never execute!
#set -x   # Uncomment to debug this shell script
#
##########################################################
#               FILES AND VARIABLES
##########################################################

# command line arguments
this_script=$(basename $0)
INPUT_DIR=${1:-}
# Check required library
if [ ! -x "$(command -v jq)" ]; then
  echo "### ERROR: JQ LIBRARY IS REQUIRED"
fi
# load sweagle host specific variables like aToken, sweagleURL, ...
source $(dirname "$0")/sweagle.env
# Check input args
if [ "$#" -lt "1" ]; then
    echo "########## ERROR: NOT ENOUGH ARGUMENTS SUPPLIED"
    echo "########## YOU SHOULD PROVIDE 1- DIRECTORY WHERE YOUR TYPES ARE STORED"
    exit 1
fi

##########################################################
#                    FUNCTIONS
##########################################################

# arg1: changeset ID
# arg2: node type ID
# arg3: children node type ID
function add_allowed_children() {
	changeset=${1}
	type_id=${2}
  children_id=${3}

	createURL="$sweagleURL/api/v1/model/type/${type_id}/childTypes"

	# Create a new allowed children type
	res=$(\
		curl -sw "%{http_code}" "$createURL" --request POST --header "authorization: bearer $aToken"  --header 'Accept: application/vnd.siren+json' \
		--data "changeset=${changeset}" \
		--data "childTypeId=${children_id}" )

	# check curl exit code
	rc=$?; if [ "${rc}" -ne "0" ]; then "ERROR: CURL exit code ${rc}"; exit ${rc}; fi;
  # check http return code, it's ok if 200 (OK) or 201 (created)
	get_httpreturn http_code res; if [[ "${http_code}" != 20* ]]; then "ERROR HTTP ${http_code}: SWEAGLE response ${res}"; exit ${http_code}; fi;
}


# arg1: changeset ID
function approve_model_changeset() {
	changeset=${1}
	# Create and open a new changeset
	res=$(curl -sw "%{http_code}" "$sweagleURL/api/v1/model/changeset/${changeset}/approve" --request POST --header "authorization: bearer $aToken"  --header 'Accept: application/vnd.siren+json')
	# check curl exit code
	rc=$?; if [ "${rc}" -ne "0" ]; then exit ${rc}; fi;
    # check http return code
	get_httpreturn httpcode res; if [ ${httpcode} -eq "200" ]; then return 0; else return 1; fi;
}


# arg1: title
# arg2: description
function create_modelchangeset() {
	title=${1}
	description=${2}

	# Create and open a new changeset
	res=$(curl -sw "%{http_code}" "$sweagleURL/api/v1/model/changeset" --request POST --header "authorization: bearer $aToken"  --header 'Accept: application/vnd.siren+json' \
		--data-urlencode "title=${title}" \
		--data-urlencode "description=${description}")
	# check exit code
	rc=$?; if [ "${rc}" -ne "0" ]; then exit ${rc}; fi;
    # check http return code
	get_httpreturn httpcode res; if [ ${httpcode} -ne "200" ]; then exit 1; fi;

  cs=$(echo ${res} | jq '.properties.changeset.id')
	echo ${cs}
}


# arg1: changeset ID
# arg2: name
function create_node_type() {
	changeset=${1}
	name=${2}

	# Manage specific integer and date args to avoid conversion error if empty string
	args=""
	if [ -n "${endOfLife}" ]; then
		args="?endOfLife=$endOfLife"
	fi
	if [ -n "${numberOfChildNodes}" ]; then
		if [ -z "$args" ]; then
			args="?numberOfChildNodes=$numberOfChildNodes"
		else
			args="$args&numberOfChildNodes=$numberOfChildNodes"
		fi
	fi
	if [ -n "${numberOfIncludes}" ]; then
		if [ -z "$args" ]; then
			args="?numberOfIncludes=$numberOfIncludes"
		else
			args="$args&numberOfIncludes=$numberOfIncludes"
		fi
	fi
	createURL="$sweagleURL/api/v1/model/type$args"

	# Create a new node_type
	res=$(\
		curl -sw "%{http_code}" "$createURL" --request POST --header "authorization: bearer $aToken"  --header 'Accept: application/vnd.siren+json' \
		--data "changeset=${changeset}" \
		--data-urlencode "name=${name}" \
		--data-urlencode "description=${description}" \
		--data "inheritFromParent=${inheritFromParent}" \
		--data "internal=${internal}" \
		--data "isMetadataset=${isMetadataset}" )

	# check curl exit code
	rc=$?; if [ "${rc}" -ne "0" ]; then "ERROR: CURL exit code ${rc}"; exit ${rc}; fi;
  # check http return code, it's ok if 200 (OK) or 201 (created)
	get_httpreturn http_code res; if [[ "${http_code}" != 20* ]]; then "ERROR HTTP ${http_code}: SWEAGLE response ${res}"; exit ${http_code}; fi;

	# Get the node ID created
	id=$(echo ${res} | jq '.properties.id')
	echo ${id}
}


# arg1: changeset ID
# arg2: type ID
# arg3: name
# arg4: description
# arg5: valueType
# arg6: required
# arg7: sensitive
# arg8: regex
# arg9: dateFormat
# arg10: defaultValue
# arg11: referenceTypeName
function create_type_attribute() {
	changeset=${1}
	type_id=${2}
	name=${3}
	description=${4:-}
	valueType=${5:-Text}
	required=${6:-false}
	sensitive=${7:-false}
	regex=${8:-}
	listOfValues=${9:-}
	dateFormat=${10:-}
	defaultValue=${11:-}
	referenceTypeName=${12:-}

  # Calculate URL depending on referenceType, because both referenceType or valueType must not be present at same time
	if [[ -n "${referenceTypeName}" && "${referenceTypeName}" != "null" ]]; then
		# if there is a reference name, then find referenced type
		referenceTypeId=$(get_node_type "$referenceTypeName")
    if [[ -z "${referenceTypeId}" || "${referenceTypeId}" == "null" ]]; then echo "SWEAGLE ERROR : Node type (${referenceTypeName}) not found"; exit 1; fi;

		createURL="$sweagleURL/api/v1/model/attribute?referenceType=${referenceTypeId}"
	else
		createURL="$sweagleURL/api/v1/model/attribute?valueType=${valueType}"
	fi

	# Create a new type_attribute
	res=$(curl -sw "%{http_code}" "${createURL}" --request POST --header "authorization: bearer ${aToken}"  --header 'Accept: application/vnd.siren+json' \
		--data "changeset=${changeset}" \
		--data "type=${type_id}" \
		--data-urlencode "name=${name}" \
		--data-urlencode "description=${description}" \
		--data "required=${required}" \
		--data "sensitive=${sensitive}" \
		--data-urlencode "regex=${regex}" \
		--data-urlencode "listOfValues=${listOfValues}" \
		--data-urlencode "dateFormat=${dateFormat}" \
		--data-urlencode "defaultValue=${defaultValue}")
	# check curl exit code
	rc=$?; if [ "${rc}" -ne "0" ]; then exit ${rc}; fi;
	# check http return code, it's ok if 200 (OK) or 201 (created)
	get_httpreturn httpcode res; if [[ "${httpcode}" != 20* ]]; then echo ${res}; exit 1; fi;
}


# arg1: changeset ID
# arg2: node type ID
# arg3: children node type ID
function delete_allowed_children() {
	changeset=${1}
	type_id=${2}
  children_id=${3}

	deleteURL="$sweagleURL/api/v1/model/type/${type_id}/childTypes?changeset=${changeset}&childTypeId=${children_id}"
	# delete an existing allowed children type
	res=$(curl -sw "%{http_code}" "$deleteURL" --request DELETE --header "authorization: bearer $aToken"  --header 'Accept: application/vnd.siren+json')

	# check curl exit code
	rc=$?; if [ "${rc}" -ne "0" ]; then "ERROR: CURL exit code ${rc}"; exit ${rc}; fi;
  # check http return code, it's ok if 200 (OK) or 201 (created)
	get_httpreturn http_code res; if [[ "${http_code}" != 20* ]]; then "ERROR HTTP ${http_code}: SWEAGLE response ${res}"; exit ${http_code}; fi;
}


# arg1: changeset ID
# arg2: type ID
# arg3: name
function delete_type_attribute() {
	changeset=${1}
	type_id=${2}
	name=${3}

	# get attribute ID from name
	attr_id=$(get_type_attribute $type_id "${name}")

	# delete attribute
	deleteURL="$sweagleURL/api/v1/model/attribute/${attr_id}?changeset=${changeset}&type=${type_id}"
	res=$(\
		curl -sw "%{http_code}" "$deleteURL" --request DELETE --header "authorization: bearer $aToken"  --header 'Accept: application/vnd.siren+json')

	# check curl exit code
	rc=$?; if [ "${rc}" -ne "0" ]; then exit ${rc}; fi;
	# check http return code, it's ok if 200 (OK) or 201 (created)
	get_httpreturn httpcode res; if [ ${httpcode} -ne 200 ]; then echo ${res}; exit 1; fi;
}


# arg1: type id
function get_all_allowed_child_types() {
	id=${1}

	res=$(\
	  curl -sw "%{http_code}" "$sweagleURL/api/v1/model/type/$id/childTypes" --request GET --header "authorization: bearer $aToken"  --header 'Accept: application/vnd.siren+json' \
		)
	# check curl exit code
	rc=$?; if [ "${rc}" -ne "0" ]; then exit ${rc}; fi;
  # check http return code
	get_httpreturn httpcode res; if [ ${httpcode} -ne "200" ]; then exit 1; fi;

	echo ${res}
}


# Get a node_type id based on its name
# arg1: name
function get_node_type() {
	name=${1}

  # Replace any space in name by %20 as data-urlencode doesn't seem to work for GET
  name=${name//" "/"%20"}
	res=$(curl -sw "%{http_code}" "$sweagleURL/api/v1/model/type?name=${name}&searchMethod=EQUALS" --request GET --header "authorization: bearer $aToken"  --header 'Accept: application/vnd.siren+json' )
	# check curl exit code
	rc=$?; if [ "${rc}" -ne "0" ]; then "ERROR: CURL exit code ${rc}"; exit ${rc}; fi;
  # check http return code
	get_httpreturn http_code res; if [ ${http_code} -ne "200" ]; then echo "ERROR HTTP ${http_code}: SWEAGLE response ${res}"; fi;

	id=$(echo ${res} | jq '.entities[0].properties.id')
	echo ${id}
}


# arg1: type id
# arg2: name
function get_type_attribute() {
	id=${1}
	name=${2:-}

	# Get a type attributes based on type id
	res=$(\
	  curl -sw "%{http_code}" "$sweagleURL/api/v1/model/attribute?type=$id" --request GET --header "authorization: bearer $aToken"  --header 'Accept: application/vnd.siren+json' \
		)
	# check curl exit code
	rc=$?; if [ "${rc}" -ne "0" ]; then exit ${rc}; fi;
  # check http return code
	get_httpreturn httpcode res; if [ ${httpcode} -ne "200" ]; then echo ${res}; exit 1; fi;

	if [ -n "${name}" ]; then
		# Get attribute ID based on its name
		attr_id=$(echo ${res} | jq --arg attr_name ${name} '.entities[].properties | select(.identifierKey|index($attr_name)) | .id')
	else
		# Return list of existing attributes names
		attr_id=$(echo ${res} | jq '.entities[].properties.identifierKey')
	fi
	echo ${attr_id}
}



# arg1: json string to parse
function parse_json_attribute() {
  json=$(echo ${1} | jq --arg attr_name "${2}" '.[] | select(.name==$attr_name)')

	name=$(echo ${2})
	description=$(echo ${json} | jq -r '.description // empty')
	defaultValue=$(echo ${json} | jq -r '.defaultValue // empty')
	required=$(echo ${json} | jq -r '.required // empty')
	sensitive=$(echo ${json} | jq -r '.sensitive // empty')
	referenceTypeName=$(echo ${json} | jq -r '.referenceTypeName // empty')
	valueType=$(echo ${json} | jq -r '.valueType // empty')
	regex=$(echo ${json} | jq -r '.regex // empty')
	listOfValues=$(echo ${json} | jq -r '.listOfValues // empty')
  if [[ "${listOfValues}" == "[]" || "${listOfValues}" == "null" ]]; then
    listOfValues=""
  else
    # If there is a list, we should transform it from JSON format to simple CSV list with no "" separator
    listOfValues=$(echo ${listOfValues} | jq -r '. | join (",")')
  fi
	dateFormat=$(echo ${json} | jq -r '.dateFormat // empty')
}


# arg1: json file to parse
function parse_json_node_type() {
	json=$(cat ${1})

	name=$(echo ${json} | jq -r '.name')
	description=$(echo ${json} | jq -r '.description // empty')
	endOfLife=$(echo ${json} | jq -r '.endOfLife // empty')
	inheritFromParent=$(echo ${json} | jq -r '.inheritFromParent // empty')
	internal=$(echo ${json} | jq -r '.internal // empty')
	isMetadataset=$(echo ${json} | jq -r '.isMetadataset  // empty')
	numberOfChildNodes=$(echo ${json} | jq -r '.numberOfChildNodes  // empty')
	numberOfIncludes=$(echo ${json} | jq -r '.numberOfIncludes // empty')
	attributes=$(echo ${json} | jq -c '.attributes  // empty')
}


# arg1: changeset ID
# arg2: node type ID
# arg3: children node type ID
function remove_allowed_children() {
	changeset=${1}
	type_id=${2}
  children_id=${3}

	createURL="$sweagleURL/api/v1/model/type/${type_id}/childTypes"

	# Delete an existing allowed children type
	res=$(\
		curl -sw "%{http_code}" "$createURL" --request DELETE --header "authorization: bearer $aToken"  --header 'Accept: application/vnd.siren+json' \
		--data "changeset=${changeset}" \
		--data "childTypeId=${children_id}" )

	# check curl exit code
	rc=$?; if [ "${rc}" -ne "0" ]; then "ERROR: CURL exit code ${rc}"; exit ${rc}; fi;
  # check http return code, it's ok if 200 (OK) or 201 (created)
	get_httpreturn http_code res; if [[ "${http_code}" != 20* ]]; then "ERROR HTTP ${http_code}: SWEAGLE response ${res}"; exit ${http_code}; fi;
}


# arg1: changeset ID
# arg2: type ID
# arg3: attribute ID
# arg4: name
# arg5: description
# arg6: valueType
# arg7: required
# arg8: sensitive
# arg9: regex
# arg10: dateFormat
# arg11: defaultValue
# arg12: referenceTypeName
function update_type_attribute() {
	changeset=${1}
	type_id=${2}
	attr_id=${3}
	name=${4}
	description=${5:-}
	valueType=${6:-Text}
	required=${7:-false}
	sensitive=${8:-false}
	regex=${9:-}
	listOfValues=${10:-}
	dateFormat=${11:-}
	defaultValue=${12:-}
	referenceTypeName=${13:-}

  # Calculate URL depending on referenceType, because both referenceType or valueType must not be present at same time
	if [ -n "${referenceTypeName}" ]; then
		# if there is a refence name, then find referenced type
		referenceTypeId=$(get_node_type "$referenceTypeName")
		updateURL="$sweagleURL/api/v1/model/attribute/$attr_id?referenceType=${referenceTypeId}"
	else
		updateURL="$sweagleURL/api/v1/model/attribute/$attr_id?valueType=${valueType}"
	fi

	# update a type_attribute
	res=$(\
		curl -sw "%{http_code}" "$updateURL" --request POST --header "authorization: bearer $aToken"  --header 'Accept: application/vnd.siren+json' \
		--data "changeset=${changeset}" \
		--data "type=${type_id}" \
		--data-urlencode "name=${name}" \
		--data-urlencode "description=${description}" \
		--data "required=${required}" \
		--data "sensitive=${sensitive}" \
		--data-urlencode "regex=${regex}" \
		--data-urlencode "listOfValues=${listOfValues}" \
		--data-urlencode "dateFormat=${dateFormat}" \
		--data-urlencode "defaultValue=${defaultValue}")

	# check curl exit code
	rc=$?; if [ "${rc}" -ne "0" ]; then exit ${rc}; fi;
  # check http return code
	get_httpreturn httpcode res; if [ ${httpcode} -ne "200" ]; then echo ${res}; exit 1; fi;
}

# arg1: changeset ID
# arg2: NODE type ID
# arg3: name
# arg4: description
# arg5: inheritFromParent
# arg6: internal
# arg7: isMetadataset
# arg8: endOfLife
# arg9: numberOfChildNodes
# arg10: numberOfIncludes
function update_node_type() {
	changeset=${1}
	id=${2}
	name=${3}
	description=${4:-}
	inheritFromParent=${5:-false}
	internal=${6:-false}
	isMetadataset=${7:-false}
	endOfLife=${8:-}
	numberOfChildNodes=${9:-}
	numberOfIncludes=${10:-}

	# Manage specific integer and date args to avoid conversion error if empty string
	args=""
	if [ -n "${endOfLife}" ]; then
		args="?endOfLife=$endOfLife"
	fi
	if [ -n "${numberOfChildNodes}" ]; then
		if [ -z "$args" ]; then
			args="?numberOfChildNodes=$numberOfChildNodes"
		else
			args="$args&numberOfChildNodes=$numberOfChildNodes"
		fi
	fi
	if [ -n "${numberOfIncludes}" ]; then
		if [ -z "$args" ]; then
			args="?numberOfIncludes=$numberOfIncludes"
		else
			args="$args&numberOfIncludes=$numberOfIncludes"
		fi
	fi
	updateURL="$sweagleURL/api/v1/model/type/$id$args"

# Update an existing node_type
	res=$(\
		curl -sw "%{http_code}" "$updateURL" --request POST --header "authorization: bearer $aToken"  --header 'Accept: application/vnd.siren+json' \
		--data "changeset=${changeset}" \
		--data-urlencode "name=${name}" \
		--data-urlencode "description=${description}" \
		--data "inheritFromParent=${inheritFromParent}" \
		--data "internal=${internal}" \
		--data "isMetadataset=${isMetadataset}" )
	# check curl exit code
	rc=$?; if [ "${rc}" -ne "0" ]; then exit ${rc}; fi;
  # check http return code
	get_httpreturn httpcode res; if [ ${httpcode} -ne "200" ]; then exit 1; fi;

}


##########################################################
#               BEGINNING OF MAIN
##########################################################

set -o errexit # exit after first line that fails
set -o nounset # exit when script tries to use undeclared variables

# create a new model changeset
modelcs=$(create_modelchangeset 'Create NODE Types' "Create new NODE types at $(date +'%c')")

for file in $INPUT_DIR/*.json; do
	echo "################################################################"
	echo "### Parsing file $file"
	parse_json_node_type "$file"
	type_id=$(get_node_type "$name")
	if [ -z "$type_id" ] || [ "$type_id" == "null" ]; then
		echo "### No existing NODE type $name, create it"
		type_id=$(create_node_type $modelcs "$name")

		echo "Node type created with ID $type_id, creating attributes"
		while IFS=$'\n' read -r attr; do
      parse_json_attribute "${attributes}" "${attr}"
      echo "# Creating attribute (${name})"
			create_type_attribute ${modelcs} ${type_id} "${name}" "${description}" "${valueType}" "${required}" "${sensitive}" "$regex" "${listOfValues}" "${dateFormat}" "${defaultValue}" "${referenceTypeName}"
      # Remove first and last characters that are [] to get name
      #name="${attr:1:${#attr}-2}"
      #attr=$(echo "${attr//[/}")
			#attr=$(echo "${attr//]/}")
			#attr=$(echo "${attr//,/ }")
			#eval "attribute=($attr)"
			#create_type_attribute $modelcs $type_id "${attribute[0]}" "${attribute[1]}" "${attribute[2]}" "${attribute[3]}" "${attribute[4]}" "${attribute[5]}" "${attribute[6]}" "${attribute[7]}" "${attribute[8]}" "${attribute[9]}"
			echo "# Attribute (${name}) created"
		done< <(jq -c -r '.attributes[] | .name' < "${file}")

	else
		echo "### NODE type $name already exits with id ($type_id), update it"
		update_node_type $modelcs $type_id "$name" "$description" "$inheritFromParent" "$internal" "$isMetadataset" "$endOfLife" "$numberOfChildNodes" "$numberOfIncludes"

		# Check what should be made with attributes
		# Compare new and old lists of attributes
		old_attr_list=$(get_type_attribute $type_id)
		new_attr_list=$(echo ${attributes} | jq '.[].name')
    # Replace space by line breaks in list to be able to sort it and use file comparison
    echo $old_attr_list | sed 's/ /\'$'\n/g'| sort > ./old.tmp
		echo $new_attr_list | sed 's/ /\'$'\n/g'| sort > ./new.tmp

		eval "attr_arr=($(comm -13 ./new.tmp ./old.tmp))"
		if [[ 	${#attr_arr[@]} -ne 0 ]]; then
			for i in "${attr_arr[@]+"${attr_arr[@]}"}"
			do
			   echo "# Delete attribute ($i)"
				 delete_type_attribute $modelcs $type_id "$i"
			done
		fi

		eval "attr_arr=($(comm -23 ./new.tmp ./old.tmp))"
		if [[ 	${#attr_arr[@]} -ne 0 ]]; then
			for i in "${attr_arr[@]}"
			do
			   echo "# Create attribute ($i)"
				 parse_json_attribute "${attributes}" "$i"
				 create_type_attribute $modelcs $type_id "$name" "$description" "$valueType" "$required" "$sensitive" "$regex" "$listOfValues" "$dateFormat" "$defaultValue" "$referenceTypeName"
			done
		fi

		eval "attr_arr=($(comm -12 ./new.tmp ./old.tmp))"
		if [[ 	${#attr_arr[@]} -ne 0 ]]; then
			for i in "${attr_arr[@]}"
			do
			   echo "# Update attribute ($i)"
				 attr_id=$(get_type_attribute $type_id "$i")
				 parse_json_attribute "${attributes}" "$i"
				 update_type_attribute $modelcs $type_id $attr_id "$name" "$description" "$valueType" "$required" "$sensitive" "$regex" "$listOfValues" "$dateFormat" "$defaultValue" "$referenceTypeName"
			done
		fi

    rm -f ./new.tmp
		rm -f ./old.tmp

    echo "Removing all existing allowed childrens, if any"
    allowedChild=$(get_all_allowed_child_types $type_id)
  	allowedChild="$(echo ${allowedChild} | jq -r '[.entities[].properties.id] | @sh')"
  	#echo "allowedChildTypes:$allowedChild"
    allowedChildArray=($allowedChild)
    if [[ ${#allowedChildArray[@]} -ne 0 ]]; then
      for i in "${allowedChildArray[@]}"
      do
         echo "# Delete allowed children ($i)"
         delete_allowed_children $modelcs $type_id $i
      done
    fi

	fi

  echo "Adding allowed childrens, if any"
  while IFS=$'\n' read -r children_name; do
    echo "# Adding allowed children (${children_name})"
    children_id=$(get_node_type "$children_name")
    if [ -z "$children_id" ] || [ "$children_id" == "null" ]; then
      echo "### WARNING: No existing CHILDREN node type $children_name, ignore it"
    else
      add_allowed_children ${modelcs} ${type_id} ${children_id}
      echo "# Allowed children (${children_name}) added"
    fi
  done< <(jq -c -r '.allowedChildTypes[]' < "${file}")

done

# approve
approve_model_changeset ${modelcs}
rc=$?; if [[ "${rc}" -ne 0 ]]; then echo "### ERROR: Model changeset approval failed"; exit ${rc}; fi

exit 0

# End of script

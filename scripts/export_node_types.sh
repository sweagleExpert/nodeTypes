#!/usr/bin/env bash
#
# SCRIPT: export_node_types.sh
# AUTHOR: dimitris@sweagle.com, filip@sweagle.com
# DATE:   September 2019
# REV:    1.0.D (Valid are A, B, D, T, Q, and P)
#               (For Alpha, Beta, Dev, Test, QA, and Production)
#
# PLATFORM: Not platform dependent
#
# REQUIREMENTS:	- jq is required for this shell script to work.
#               (see: https://stedolan.github.io/jq/)
#				- tested in bash 4.4 on Mac OS X
#
# PURPOSE:		Export node types from a sweagle tenant and store them as json files in a target directory
#						Directory where properties files will be stored should be provided as input (if none, default is current directory)
#
# REV LIST:
#        DATE: DATE_of_REVISION
#        BY:   AUTHOR_of_MODIFICATION
#        MODIFICATION: Describe what was modified, new features, etc--
#
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
TARGET_DIR=${1:-}
# Check required library
if [ ! -x "$(command -v jq)" ]; then
  echo "### ERROR: JQ LIBRARY IS REQUIRED"
fi
# load sweagle host specific variables like aToken, sweagleURL, ...
source $(dirname "$0")/sweagle.env
# Check input arguments
if [ "$#" -lt "1" ]; then
	echo "*** No target directory provided, will use (.) as output"
	TARGET_DIR="."
else
	if [ ! -d "$TARGET_DIR" ]; then
		echo "********** ERROR: ($1) IS NOT A DIRECTORY"
    echo "********** YOU SHOULD PROVIDE TARGET DIRECTORY WHERE YOUR TYPES WILL BE STORED"
    exit 1
	fi
fi


##########################################################
#                    FUNCTIONS
##########################################################

function get_all_node_types() {

	res=$(\
	  curl -sw "%{http_code}" "$sweagleURL/api/v1/model/type" --request GET --header "authorization: bearer $aToken"  --header 'Accept: application/vnd.siren+json' \
		)
	# check curl exit code
	rc=$?; if [ "${rc}" -ne "0" ]; then exit ${rc}; fi;
  # check http return code
	get_httpreturn httpcode res; if [ ${httpcode} -ne "200" ]; then exit 1; fi;

	echo ${res}
}


# arg1: type id
function get_all_attributes() {
	id=${1}

	# Get a type attributes based on type id
	res=$(\
	  curl -sw "%{http_code}" "$sweagleURL/api/v1/model/attribute?type=$id" --request GET --header "authorization: bearer $aToken"  --header 'Accept: application/vnd.siren+json' \
		)
	# check curl exit code
	rc=$?; if [ "${rc}" -ne "0" ]; then exit ${rc}; fi;
  # check http return code
	get_httpreturn httpcode res; if [ ${httpcode} -ne "200" ]; then exit 1; fi;

	echo ${res}
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

##########################################################
#               BEGINNING OF MAIN
##########################################################

set -o errexit # exit after first line that fails
set -o nounset # exit when script tries to use undeclared variables

eol=$'\n'

echo "*** Getting all node types from SWEAGLE tenant $sweagleURL"
node_types=$(get_all_node_types)

echo "*** Filter only on valid node Types"
node_types=$(echo ${node_types} | jq '.entities[].properties.version | select(.status=="VALID")')
node_types=${node_types//"}$eol{"/"},{"}
#echo "${node_types}" > ./debug.json

for row in $(echo "[${node_types}]" | jq -r '.[] | @base64'); do
    _jq() {
     echo ${row} | base64 --decode | jq ${1}
    }
	type_id=$(_jq '.masterId')
	type_name=$(echo ${row} | base64 --decode | jq -r '.name')
	echo "*** Exporting node type $type_name"
	filename="$TARGET_DIR/$type_name.json"
	# Remove <space> from filename
	filename=${filename//" "/"-"}
  echo "{ \"name\":\"$type_name\""  > $filename
	echo ",\"description\":$(_jq '.description')"  >> $filename
	echo ",\"endOfLife\":$(_jq '.endOfLife')"  >> $filename
	echo ",\"inheritFromParent\":$(_jq '.inheritFromParent')"  >> $filename
	echo ",\"internal\":$(_jq '.internal')"  >> $filename
	echo ",\"isMetadataset\":$(_jq '.isMetadataset')"  >> $filename
	echo ",\"numberOfChildNodes\":$(_jq '.numberOfChildNodes')"  >> $filename
	echo ",\"numberOfIncludes\":$(_jq '.numberOfIncludes')"  >> $filename

	allowedChild=$(get_all_allowed_child_types $type_id)
	allowedChild="[$(echo ${allowedChild} | jq -r '[.entities[].properties.identifierKey] | @csv')]"
	echo ",\"allowedChildTypes\":$allowedChild"  >> $filename

	attributesInitial=$(get_all_attributes $type_id)
	attributes=$(echo ${attributesInitial} | jq '.entities[].properties.version | select(.status=="VALID")')
	attributes=${attributes//"}$eol{"/"},{"}
	#echo "${attributes}" > ./debug-$type_id.json
	if [ -z "${attributes}" ]; then
		echo "No attributes for this node type"
		echo "}"  >> $filename
	else
		echo ",\"attributes\": ["  >> $filename
		for attr in $(echo "[${attributes}]" | jq -r '.[] | @base64'); do
		    _jq() {
		     echo ${attr} | base64 --decode | jq ${1}
		    }
				# attr_id=$(_jq '.masterId')
				attr_name=$(echo ${attr} | base64 --decode | jq -r '.name')
				echo " Exporting attribute $attr_name"
				echo "{ \"name\":\"$attr_name\""  >> $filename
				echo ",\"description\":$(_jq '.description')"  >> $filename
				echo ",\"defaultValue\":$(_jq '.defaultValue')"  >> $filename
				echo ",\"required\":$(_jq '.required')"  >> $filename
				echo ",\"sensitive\":$(_jq '.sensitive')"  >> $filename
				reference="$(_jq '.referenceTypeId')"
				if [ "$reference" != "null" ]; then
					#echo "old=${reference}"
					# convert string to integer
					reference=$(($reference + 0))
					# Get node type name based on its id, we use --argjson instead of --arg to pass a number argument
					reference=$(echo "[${node_types}]" | jq --argjson node_id ${reference} '.[] | select(.masterId==$node_id).name')
					#echo "new=$reference"
				fi
				echo ",\"referenceTypeName\":$reference"  >> $filename
				echo ",\"valueType\":$(_jq '.valueType')"  >> $filename
				echo ",\"regex\":$(_jq '.regex')"  >> $filename
				listOfValues=$(echo ${attributesInitial} | jq --arg attr_name "${attr_name}" -r '.entities[].properties | select(.identifierKey==$attr_name).listOfValues')
				if [ "$listOfValues" != "[]" ]; then
					listOfValues="$(echo ${listOfValues} | jq '[.[].value]')"
				fi
				echo ",\"listOfValues\": $listOfValues"  >> $filename
				echo ",\"dateFormat\":$(_jq '.dateFormat')"  >> $filename
				echo "},"  >> $filename
		done
		# replace last , by } to end json element
	  sed -i '' '$ s/.$/]}/' $filename
	fi
	# Reformat the JSON file
	jq . "${filename}" > "${filename}.tmp"
	mv "${filename}.tmp" "${filename}"
done

exit 0
# End of script

#!/bin/bash
#
# sendspace.com module
# Copyright (c) 2010-2011 Plowshare team
#
# This file is part of Plowshare.
#
# Plowshare is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# Plowshare is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Plowshare.  If not, see <http://www.gnu.org/licenses/>.

MODULE_SENDSPACE_REGEXP_URL="http://\(www\.\)\?sendspace\.com/\(file\|folder\)/"

MODULE_SENDSPACE_DOWNLOAD_OPTIONS=""
MODULE_SENDSPACE_DOWNLOAD_RESUME=yes
MODULE_SENDSPACE_DOWNLOAD_FINAL_LINK_NEEDS_COOKIE=unused

MODULE_SENDSPACE_UPLOAD_OPTIONS=""
MODULE_SENDSPACE_LIST_OPTIONS=""

# Output a sendspace file download URL
# $1: cookie file (unused here)
# $2: sendspace.com url
# stdout: real file download link
sendspace_download() {
    local URL="$2"

    if match 'sendspace\.com\/folder\/' "$URL"; then
        log_error "This is a directory list, use plowlist!"
        return 1
    fi

    local PAGE=$(curl "$URL") || return

    # - Sorry, the file you requested is not available.
    if match '<div class="msg error"' "$PAGE"; then
        local ERR=$(echo "$PAGE" | parse '="msg error"' '">\([^<]*\)')
        log_error "$ERR"
        return $ERR_LINK_DEAD
    fi

    PAGE=$(curl --referer "$URL" "$URL") || return

    local FILE_URL=$(echo "$PAGE" | parse_attr 'download_button' 'href')

    test "$CHECK_LINK" && return 0

    echo "$FILE_URL"
}

# Upload a file to sendspace.com
# $1: cookie file (unused here)
# $2: input file (with full path)
# $3 (optional): alternate remote filename
# stdout: sendspace.com download + delete link
sendspace_upload() {
    eval "$(process_options sendspace "$MODULE_SENDSPACE_UPLOAD_OPTIONS" "$@")"

    local FILE="$2"
    local DESTFILE=${3:-$FILE}

    local DATA=$(curl "http://www.sendspace.com") || return
    local FORM_HTML=$(grep_form_by_order "$DATA" 2 | break_html_lines_alt)
    local form_url=$(echo "$FORM_HTML" | parse_form_action)
    local form_maxfsize=$(echo "$FORM_HTML" | parse_form_input_by_name 'MAX_FILE_SIZE')
    local form_uid=$(echo "$FORM_HTML" | parse_form_input_by_name 'UPLOAD_IDENTIFIER')
    local form_ddir=$(echo "$FORM_HTML" | parse_form_input_by_name 'DESTINATION_DIR')
    local form_jsena=$(echo "$FORM_HTML" | parse_form_input_by_name 'js_enabled')
    local form_sign=$(echo "$FORM_HTML" | parse_form_input_by_name 'signature')
    local form_ufiles=$(echo "$FORM_HTML" | parse_form_input_by_name 'upload_files')
    local form_terms=$(echo "$FORM_HTML" | parse_form_input_by_name 'terms')

    log_debug "starting file upload: $FILE"
    DATA=$(curl_with_log \
        -F "MAX_FILE_SIZE=$form_maxfsize" \
        -F "UPLOAD_IDENTIFIER=$form_uid"  \
        -F "DESTINATION_DIR=$form_ddir"   \
        -F "js_enabled=$form_jsena"       \
        -F "signature=$form_sign"         \
        -F "upload_files=$form_ufiles"    \
        -F "terms=$form_terms"            \
        -F "file[]="                      \
        -F "description[]="               \
        -F "ownemail="                    \
        -F "recpemail="                   \
        -F "upload_file[]=@$FILE;filename=$(basename_file "$DESTFILE")" \
        "$form_url")

    DL_LINK=$(echo "$DATA" | parse_attr 'share link' 'href')
    DEL_LINK=$(echo "$DATA" | parse_attr '\/delete\/' 'href')

    echo "$DL_LINK ($DEL_LINK)"
}

# List a sendspace shared folder
# $1: sendspace folder URL
# stdout: list of links (file and/or folder)
sendspace_list() {
    local URL="$1"

    if ! match 'sendspace\.com\/folder\/' "$URL"; then
        log_error "This is not a directory list"
        return 1
    fi

    PAGE=$(curl "$URL") || return
    LINKS=$(echo "$PAGE" | parse_all '<td class="dl" align="center"' \
            '\(<a href="http[^<]*<\/a>\)' 2>/dev/null)
    SUBDIRS=$(echo "$PAGE" | parse_all '\/folder\/' \
            '\(<a href="http[^<]*<\/a>\)' 2>/dev/null)

    if [ -z "$LINKS" -a -z "$SUBDIRS" ]; then
        log_debug "empty folder"
        return 0
    fi

    # Stay at depth=1 (we do not recurse into directories)
    LINKS=$(echo "$LINKS" "$SUBDIRS")

    # First pass : print debug message
    while read LINE; do
        FILE_NAME=$(echo "$LINE" | parse_attr 'a' 'title')
        log_debug "$FILE_NAME"
    done <<< "$LINKS"

    # Second pass : print links (stdout)
    while read LINE; do
        FILE_URL=$(echo "$LINE" | parse_attr 'a' 'href')
        echo "$FILE_URL"
    done <<< "$LINKS"

    return 0
}

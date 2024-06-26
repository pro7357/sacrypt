#!/usr/bin/bash
_help(){ cat <<E0F
Usage: ./sacrypt.sh [OPTION]... [COMMAND]
Save and encrypt.

Command:
  autosave      Run autosave in the background.
  close         Close autosave.
Option:
  -h, --help    display this help and exit
E0F
}

BWD=$(dirname "$0")

load_config(){
    if [[ -f "$BWD/.config" ]]; then
        source "$BWD/.config"
    elif [[ -f "$BWD/default.config" ]]; then
        source "$BWD/default.config"
        if [[ -z "$PUBLIC_KEY" || ${#ENCRYPT_PATH[@]} -eq 0 ]]; then
            echo "[sacrypt] Critical: Configuration not properly loaded."
            exit 2
        fi
    else
        echo "[sacrypt] Critical: Config file not found at $BWD"
        exit 1
    fi
}

_encrypt(){
    local base="$DECRYPT_PATH/${1##*/}"
    if [[ ! -f "$base/.sacrypt" ]]; then
       touch -t 197001010000.01 "$base/.sacrypt"
    fi

    # Save and encrypt files newer than marker file
    find "$base" -type f -newer "$base/.sacrypt" | while read -r file; do
        echo "${file#$base/}" | anew "$base/.sacrypt"
        name=$(sha256sum <<< "$PUBLIC_KEY/${file#$base/}" | head -c 64)
        tar -P --transform="s|$base/||" -c "$file" \
            | rage -r "$PUBLIC_KEY" > "$1/${name::1}/${name}"
    done

    # Update the marker file
    touch "$base/.sacrypt"
}

_init_encrypt(){
    mkdir -p "$1"
    cd "$1"
    for i in {0..15}; do
        hex=$(printf "%x" "$i")
        mkdir -p "$hex"
    done

    local base="$DECRYPT_PATH/${1##*/}"

    # Save and encrypt everything
    find "$base" -type f | while read -r file; do
        echo "$file"
        name=$(sha256sum <<< "$PUBLIC_KEY/${file#$base/}" | head -c 64)
        tar -P --transform="s|$base/||" -c "$file" \
            | rage -r "$PUBLIC_KEY" > "$1/${name::1}/${name}"
    done

    # Create marker
    touch "$base/.sacrypt"
}

_decrypt(){
    local base="$DECRYPT_PATH/${1##*/}"
    mkdir -p "$base"

    # Decrypt and extract files
    find "$1" -type f -name "*" | while read -r file; do
        rage -d -i "$PRIVATE_KEY" "$file" \
            | tar -xv -C "$base" \
            | anew "$base/.sacrypt"
    done
}

_auto(){
    if [[ ! -d $DECRYPT_PATH ]]; then
        mkdir -p $DECRYPT_PATH
    fi

    for p in "${ENCRYPT_PATH[@]}"; do
        dir="${p##*/}"
        if [[ -d "$p" ]] && [[ -d "$DECRYPT_PATH/$dir" ]]; then
            _encrypt "$p"
            _delete "$p"
        elif [[ -d "$p" ]] && [[ ! -d "$DECRYPT_PATH/$dir" ]]; then
            _decrypt "$p"
        elif [[ ! -d "$p" ]] && [[ -d "$DECRYPT_PATH/$dir" ]]; then
            _init_encrypt "$p"
        fi
    done

    if (( SAVE_TIMER == 0 )); then
        return
    elif (( "$(pgrep -cx "sacrypt.sh")" <= 1 )); then
        $BWD/sacrypt.sh autosave > /dev/null &
    fi
}

_auto_encrypt(){
    while true; do
        for p in "${ENCRYPT_PATH[@]}"; do
            dir="${p##*/}"
            if [[ -d "$p" ]] && [[ -d "$DECRYPT_PATH/$dir" ]]; then
                _encrypt "$p"
                _delete "$p"
            fi
        done
        sleep $SAVE_TIMER
    done
}

_delete(){
    local dir="${1##*/}"
    IFS=$'\n'
    for line in $(< "$DECRYPT_PATH/$dir/.sacrypt"); do
        if [[ ! -e "$DECRYPT_PATH/$dir/$line" ]]; then
            name=$(sha256sum <<< "$PUBLIC_KEY/${line}" | head -c 64)
            echo "missing '$DECRYPT_PATH/$dir/$line'"
            rm -v "$1/${name::1}/${name}"

            sed -i "/$line/d" "$DECRYPT_PATH/$dir/.sacrypt"
        fi
    done
}

_close(){
    pkill sacrypt.sh
    if (( "$(pgrep -cx "sacrypt.sh")" > 0 )); then
        echo "[sacrypt] Error: Fail to close sacrypt."
    fi
}

_main(){
    load_config
    if [[ $1 == '-h' || $1 == --help ]]; then
        _help
    elif [[ $1 == 'autosave' ]]; then
        _auto_encrypt
    elif [[ $1 == 'close' ]]; then
        _close
    elif [[ -z $1 ]]; then
        _auto
    else
        echo "[sacrypt] Error: What this? $@"
    fi
}
_main "$@"

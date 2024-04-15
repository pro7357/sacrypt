#!/usr/bin/bash
_help(){ cat <<E0F
Usage: ./bacrypt.sh [OPTION]
Backup and encryption.

      onloop    start Bacrypt on loop.
      close     close Bacrypt if it running in loop.
  -h, --help    display this help and exit
E0F
}

BWD=$(dirname "$0")

load_config(){
    if [[ -f "$BWD/bacrypt.config" ]]; then
        source "$BWD/bacrypt.config"
    elif [[ -f "$BWD/default.config" ]]; then
        source "$BWD/default.config"
        if [[ -z "$pub_key" || ${#enc_path[@]} -eq 0 ]]; then
            echo "[bacrypt] Critical: Configuration not properly loaded."
            exit 2
        fi
    else
        echo "[bacrypt] Critical: Config file not found at $BWD"
        exit 1
    fi
}

_encrypt(){
    local base="$dec_path/${1##*/}"

    # Backup and encrypt files newer than marker file
    find "$base" -type f -newer "$base/.grass" | while read -r file; do
        echo "${file#$base/}" | anew "$base/.bacrypt"
        name=$(sha256sum <<< "$pub_key/${file#$base/}" | head -c 64)
        tar -P --transform="s|$base/||" -c "$file" \
            | rage -r "$pub_key" > "$1/${name::1}/${name}"

    done

    # Update the marker file
    touch "$base/.grass"
}

_init_encrypt(){
    mkdir -p "$1"
    cd "$1"
    for i in {0..15}; do
        hex=$(printf "%x" "$i")
        mkdir -p "$hex"
    done

    local base="$dec_path/${1##*/}"

    # Backup and encrypt everything
    find "$base" -type f | while read -r file; do
        echo "$file"
        name=$(sha256sum <<< "$pub_key/${file#$base/}" | head -c 64)
        tar -P --transform="s|$base/||" -c "$file" \
            | rage -r "$pub_key" > "$1/${name::1}/${name}"
    done

    # Create marker
    touch "$base/.grass"
}

_decrypt(){
    local base="$dec_path/${1##*/}"
    mkdir -p "$base"

    # Decrypt and extract files
    find "$1" -type f -name "*" | while read -r file; do
        rage -d -i "$private_key" "$file" \
            | tar -xv -C "$base" \
            | anew "$base/.bacrypt"
    done
}

_auto(){
    if [[ ! -d $dec_path ]]; then
        mkdir -p $dec_path
    fi

    for p in "${enc_path[@]}"; do
        dir="${p##*/}"
        if [[ -d "$p" ]] && [[ -d "$dec_path/$dir" ]]; then
            _encrypt "$p"
        elif [[ -d "$p" ]] && [[ ! -d "$dec_path/$dir" ]]; then
            _decrypt "$p"
        elif [[ ! -d "$p" ]] && [[ -d "$dec_path/$dir" ]]; then
            _init_encrypt "$p"
        fi
    done

    if (( save_timer == 0 )); then
        return
    elif (( $(pgrep bacrypt.sh | wc -l) < 1 )); then
        $BWD/bacrypt.sh onloop > /dev/null &
    fi
}

_auto_encrypt(){
    while true; do
        for p in "${enc_path[@]}"; do
            dir="${p##*/}"
            if [[ -d "$p" ]] && [[ -d "$dec_path/$dir" ]]; then
                _encrypt "$p"
                _delete "$p"
            fi
        done
        sleep $save_timer
    done
}

_delete(){
    local dir="${1##*/}"
    IFS=$'\n'
    for line in $(< "$dec_path/$dir/.bacrypt"); do
        #printf "%s\n" "$line"
        if [[ ! -e "$dec_path/$dir/$line" ]]; then
            name=$(sha256sum <<< "$pub_key/${line}" | head -c 64)
            echo "missing $dec_path/$dir/$line"
            #echo "delete: $1/${name::1}/${name}"
            rm -v "$1/${name::1}/${name}"

            sed -i "/$line/d" "$dec_path/$dir/.bacrypt"
        fi
    done
}

_close(){
    pkill bacrypt.sh
    if (( $(pgrep bacrypt.sh | wc -l) >= 1 )); then
        echo "[bacrypt] Error: Fail to close bacrypt."
    fi
}

_main(){
    load_config
    if [[ $1 == '-h' || $1 == --help ]]; then
        _help
    elif [[ $1 == 'onloop' ]]; then
        _auto_encrypt
    elif [[ $1 == 'close' ]]; then
        _close
    elif [[ -z $1 ]]; then
        _auto
        #_delete "$BWD/.data/pub"
    else
        echo "[bacrypt] Error: What this? $@"
    fi
}
_main "$@"

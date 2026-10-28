#!/bin/bash
set -e

# ensures script can run only once at a time
pidof -o %PPID -x $0 >/dev/null && echo "Script $0 already running" && exit 1

function move_output() {
   hda-verb /dev/snd/hwC0D0 0x16 0x701 "$@" > /dev/null 2> /dev/null || true
}

function move_output_to_speaker() {
    move_output 0x0001
}

function move_output_to_headphones() {
    move_output 0x0000
}

function switch_to_speaker() {
    move_output_to_speaker

    # enable speaker
    hda-verb /dev/snd/hwC0D0 0x17 0x70C 0x0002 > /dev/null 2> /dev/null || true

    # disable headphones
    hda-verb /dev/snd/hwC0D0 0x1 0x715 0x2 > /dev/null 2> /dev/null || true
}

function switch_to_headphones() {
    move_output_to_headphones

    # disable speaker
    hda-verb /dev/snd/hwC0D0 0x17 0x70C 0x0000 > /dev/null 2> /dev/null || true

    # pin output mode
    hda-verb /dev/snd/hwC0D0 0x1 0x717 0x2 > /dev/null 2> /dev/null || true

    # pin enable
    hda-verb /dev/snd/hwC0D0 0x1 0x716 0x2 > /dev/null 2> /dev/null || true

    # clear pin value
    hda-verb /dev/snd/hwC0D0 0x1 0x715 0x0 > /dev/null 2> /dev/null || true
}

function enable_microphone() {
    # Node 0x19: Pin-ctls IN (0x20) + VREF_80 (0x04)
    hda-verb /dev/snd/hwC0D0 0x19 0x707 0x24 > /dev/null 2>&1 || true
    # Node 0x13: select connection 1 (Node 0x19)
    hda-verb /dev/snd/hwC0D0 0x13 0x701 0x1 > /dev/null 2>&1 || true
    # Node 0x13: unmute input amp on index 1 with 0x50 gain
    hda-verb /dev/snd/hwC0D0 0x13 0x3b0 0x50 > /dev/null 2>&1 || true
}

function get_sound_card_index() {
    card_index=$(cat /proc/asound/cards | grep -E "sof-hda-dsp|HDA Intel PCH|PCH" | head -n1 | grep -Eo "^\s*[0-9]+")
    card_index="${card_index#"${card_index%%[![:space:]]*}"}"
    if [ -z "$card_index" ]; then
        card_index="0"
    fi
    echo "$card_index"
}

sleep 2 # allows audio system to initialise first

card_index=$(get_sound_card_index)

# Ensure ALSA output controls are unmuted and auto-mute mode is disabled
amixer -c "$card_index" sset 'Master' unmute 100% >/dev/null 2>&1 || true
amixer -c "$card_index" sset 'Speaker' unmute 100% >/dev/null 2>&1 || true
amixer -c "$card_index" sset 'Headphone' unmute 100% >/dev/null 2>&1 || true
amixer -c "$card_index" sset 'Auto-Mute Mode' 'Disabled' >/dev/null 2>&1 || true

# Ensure ALSA input controls are unmuted
amixer -c "$card_index" sset 'Capture' unmute 100% >/dev/null 2>&1 || true
amixer -c "$card_index" sset 'Mic Boost' 2 >/dev/null 2>&1 || true

switch_to_speaker
enable_microphone

old_status=0

while true; do
    if amixer -c "$card_index" get Headphone 2>/dev/null | grep -q "\[off\]"; then
        status=1
        move_output_to_speaker
    else
        status=2
        move_output_to_headphones
    fi

    if [ ${status} -ne ${old_status} ]; then
        case "${status}" in
            1)
                message="Headphones disconnected -> Speaker ON"
                switch_to_speaker
                ;;
            2)
                message="Headphones connected -> Headphones ON"
                switch_to_headphones
                ;;
        esac

        echo "${message}"
        old_status=$status
    fi

    enable_microphone
    sleep .5
done

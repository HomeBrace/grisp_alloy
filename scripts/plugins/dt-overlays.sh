#!/usr/bin/env bash
#
# dt-overlays.sh — compile project Device Tree overlays (.dtso) and merge
# them into the SDK base DTB. Produces a merged DTB ready to feed into the
# bootscheme's FIT image step.
#
# Requires the SDK to ship dtc + fdtoverlay in host/bin/ (already true) and
# the kernel DT include tree at ${SDK}/dt-includes/ (added by make-sdk.sh).
# The base DTB must have been compiled with DTC -@ so __symbols__ resolves
# overlay phandle references like &uart3 (BR2_LINUX_KERNEL_DTB_OVERLAY_SUPPORT=y).

# Compile a single .dtso to a .dtbo using cpp + dtc.
# Usage: compile_dtso DTSO_FILE OUT_DTBO_FILE
compile_dtso() {
    local dtso="$1"
    local out_dtbo="$2"

    local dtc="${GLB_SDK_HOST_DIR}/bin/dtc"
    local dt_inc="${GLB_SDK_DIR}/dt-includes"

    if [[ ! -x "$dtc" ]]; then
        error 1 "dtc not found at $dtc — rebuild SDK"
    fi
    if [[ ! -d "$dt_inc" ]]; then
        error 1 "DT include tree not found at $dt_inc — rebuild SDK"
    fi
    if [[ ! -f "$dtso" ]]; then
        error 1 "DT overlay source not found: $dtso"
    fi

    local pp_file="${out_dtbo%.dtbo}.dts.pp"

    cpp -E -nostdinc -undef -x assembler-with-cpp \
        -I "$dt_inc" \
        -I "$dt_inc/freescale" \
        -o "$pp_file" "$dtso"

    "$dtc" -q -I dts -O dtb -@ -o "$out_dtbo" "$pp_file"
}

# Compile and apply a list of .dtso files against a base DTB.
# Usage: apply_dt_overlays BASE_DTB OUT_DTB DTSO_FILE ...
apply_dt_overlays() {
    local base_dtb="$1"; shift
    local out_dtb="$1"; shift

    local fdtoverlay="${GLB_SDK_HOST_DIR}/bin/fdtoverlay"
    if [[ ! -x "$fdtoverlay" ]]; then
        error 1 "fdtoverlay not found at $fdtoverlay — rebuild SDK"
    fi
    if [[ ! -f "$base_dtb" ]]; then
        error 1 "Base DTB not found: $base_dtb"
    fi
    if [[ $# -eq 0 ]]; then
        error 1 "apply_dt_overlays: no overlay files supplied"
    fi

    local work_dir
    work_dir="$( dirname "$out_dtb" )/dt-overlays"
    rm -rf "$work_dir"
    mkdir -p "$work_dir"

    local dtbo_files=()
    local idx=0
    local dtso dtso_base dtbo_file
    for dtso in "$@"; do
        dtso_base="$( basename "$dtso" )"
        dtso_base="${dtso_base%.dtso}"
        dtbo_file="${work_dir}/$( printf "%02d" "$idx" )_${dtso_base}.dtbo"
        echo "Compiling overlay: $( basename "$dtso" )"
        compile_dtso "$dtso" "$dtbo_file"
        dtbo_files+=( "$dtbo_file" )
        idx=$(( idx + 1 ))
    done

    echo "Merging ${#dtbo_files[@]} overlay(s) into $( basename "$out_dtb" )..."
    "$fdtoverlay" -i "$base_dtb" -o "$out_dtb" "${dtbo_files[@]}"
}

# Expand --dtso file paths and --dtso-dir directory paths into a flat
# overlay list. Files keep caller order; directories contribute their
# *.dtso contents in lexical order. Result is appended to the named
# array variable.
# Usage: collect_dt_overlays OUT_VAR FILES_ARRAY DIRS_ARRAY
#   OUT_VAR — name of array to append into (must already exist)
#   FILES_ARRAY/DIRS_ARRAY — names of arrays holding inputs
collect_dt_overlays() {
    local out_var="$1"
    local files_var="$2"
    local dirs_var="$3"

    local files=()
    local dirs=()
    eval "files=( \"\${${files_var}[@]}\" )"
    eval "dirs=( \"\${${dirs_var}[@]}\" )"

    local f d match
    for d in "${dirs[@]}"; do
        [[ -z "$d" ]] && continue
        if [[ ! -d "$d" ]]; then
            error 1 "DT overlay directory not found: $d"
        fi
        while IFS= read -r match; do
            [[ -z "$match" ]] && continue
            eval "${out_var}+=( \"\$match\" )"
        done < <( find "$d" -maxdepth 1 -name "*.dtso" -type f | sort )
    done

    for f in "${files[@]}"; do
        [[ -z "$f" ]] && continue
        if [[ ! -f "$f" ]]; then
            error 1 "DT overlay source not found: $f"
        fi
        eval "${out_var}+=( \"\$f\" )"
    done
}

#!/usr/bin/env sh
set -eu

run() {
    cwd="$1"
    shift
    if [ -n "$cwd" ]; then
        printf 'run: cd "%s" && %s\n' "$cwd" "$*" >&2
        cd "$cwd"
        "$@"
        cd - > /dev/null
    else
        printf 'run: %s\n' "$*" >&2
        "$@"
    fi
}

read_sha() {
    sha=$(head -c 40 "$1")
    case "$sha" in
        [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f])
            ;;
        *)
            printf 'error: invalid git SHA "%s" from "%s"\n' "$sha" "$1" >&2
            exit 1
            ;;
    esac
    printf '%s' "$sha"
}

fetch_dot_master() {
    src="$1"
    if [ ! -d "$src" ]; then
        run "" git clone https://github.com/marler8997/dot "$src" -b master
    fi
    run "" git -C "$src" fetch origin master
    read_sha "$src/.git/FETCH_HEAD"
}

test_writable() {
    dir="$1"
    if [ ! -d "$dir" ]; then
        return 1
    fi
    test_file="$dir/dof.test"
    if touch "$test_file" 2>/dev/null; then
        rm -f "$test_file"
        return 0
    fi
    return 1
}

add_to_shell_path() {
    dir="$1"
    shell_name=$(basename "${SHELL:-/bin/sh}")
    case "$shell_name" in
        bash)
            rc="$HOME/.bashrc"
            ;;
        zsh)
            rc="$HOME/.zshrc"
            ;;
        fish)
            printf 'dof: to add "%s" to your PATH, run:\n' "$dir" >&2
            printf '  fish_add_path "%s"\n' "$dir" >&2
            return
            ;;
        *)
            rc="$HOME/.profile"
            ;;
    esac
    line="export PATH=\"$dir:\$PATH\""
    if [ -f "$rc" ] && grep -qF "$dir" "$rc"; then
        return
    fi
    printf 'dof: adding "%s" to PATH in %s\n' "$dir" "$rc" >&2
    printf '\n# Added by dof installer\n%s\n' "$line" >> "$rc"
    printf 'dof: restart your shell for PATH changes to take effect\n' >&2
}

prompt_custom_dir() {
    printf 'Enter a directory to install dof into: ' >&2
    read -r custom < /dev/tty || { printf '\nerror: failed to read input\n' >&2; exit 1; }
    if [ -z "$custom" ]; then
        return 1
    fi
    if [ ! -e "$custom" ]; then
        printf '"%s" does not exist, create it? [y/N] ' "$custom" >&2
        read -r confirm < /dev/tty || { printf '\nerror: failed to read input\n' >&2; exit 1; }
        case "$confirm" in
            [Yy]) ;;
            *)
                return 1
                ;;
        esac
        mkdir -p "$custom"
    fi
    if ! test_writable "$custom"; then
        printf 'error: "%s" is not writable\n' "$custom" >&2
        return 1
    fi
    printf '%s' "$custom"
}

select_install_dir() {
    writable_dirs=""
    writable_count=0

    IFS=:
    for dir in $PATH; do
        if [ -z "$dir" ]; then
            continue
        fi
        if test_writable "$dir"; then
            writable_dirs="${writable_dirs}${dir}
"
            writable_count=$((writable_count + 1))
        else
            printf '  (skipping "%s" - not writable)\n' "$dir" >&2
        fi
    done
    unset IFS

    if [ "$writable_count" -eq 0 ]; then
        printf 'note: no writable directories found in PATH\n' >&2
        while true; do
            custom=$(prompt_custom_dir) || { printf 'please try again\n' >&2; continue; }
            add_to_shell_path "$custom"
            printf '%s' "$custom"
            return
        done
    fi

    printf '\nWhere would you like to install dof?\n\n' >&2
    i=1
    printf '%s' "$writable_dirs" | while IFS= read -r dir; do
        printf '  %d) %s\n' "$i" "$dir" >&2
        i=$((i + 1))
    done
    printf '  C) Enter a custom directory (will be added to your PATH)\n\n' >&2

    while true; do
        printf 'Choice: ' >&2
        read -r choice < /dev/tty || { printf '\nerror: failed to read input\n' >&2; exit 1; }
        case "$choice" in
            [0-9]|[0-9][0-9])
                if [ "$choice" -ge 1 ] 2>/dev/null && [ "$choice" -le "$writable_count" ]; then
                    selected=$(printf '%s' "$writable_dirs" | sed -n "${choice}p")
                    printf '%s' "$selected"
                    return
                fi
                printf 'invalid choice, please try again\n' >&2
                ;;
            [Cc])
                custom=$(prompt_custom_dir) || { printf 'please try again\n' >&2; continue; }
                add_to_shell_path "$custom"
                printf '%s' "$custom"
                return
                ;;
            *)
                printf 'invalid choice, please try again\n' >&2
                ;;
        esac
    done
}

# --- main ---

existing=$(command -v dof 2>/dev/null || true)
if [ -n "$existing" ]; then
    printf 'dof: already installed at "%s"\n' "$existing"
    exit 0
fi

for tool in git zig; do
    if ! command -v "$tool" > /dev/null 2>&1; then
        printf 'error: dof requires "%s" but it was NOT found in PATH\n' "$tool" >&2
        exit 1
    fi
done

if [ "$(uname)" = "Darwin" ]; then
    app_data="$HOME/Library/Application Support/dof"
else
    app_data="${XDG_DATA_HOME:-$HOME/.local/share}/dof"
fi
printf 'appdata "%s"\n' "$app_data"
mkdir -p "$app_data"

src="$app_data/src"

install_path="${1:-}"
if [ -n "$install_path" ]; then
    if [ ! -d "$install_path" ]; then
        printf 'error: "%s" does not exist\n' "$install_path" >&2
        exit 1
    fi
    install_dir=$(cd "$install_path" && pwd)
    case ":$PATH:" in
        *:"$install_dir":*)
            ;;
        *)
            printf 'error: "%s" is not in PATH\n' "$install_dir" >&2
            exit 1
            ;;
    esac
else
    install_dir=$(select_install_dir)
fi
printf 'dof: installing to "%s"\n' "$install_dir"

master=$(fetch_dot_master "$src")
run "" git -C "$src" reset --hard "$master"
run "$src" zig build install "-Dsha=$master" --prefix "$install_dir"

printf 'dof has been installed and added to PATH\n'

#!/bin/sh
# Turn Markdown schedules into normal tasks. BusyBox crond handles the clock.
set -eu

export TZ=${TZ:-UTC}
export PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin

# Frontmatter is deliberately flat: one key/value per line, optional quotes.
field() {
    awk -v key="$1" '
        NR == 1 { if ($0 != "---") exit; next }
        $0 == "---" { exit }
        index($0, key ": ") == 1 {
            sub(/^[^:]*: */, ""); sub(/\r$/, "")
            if ($0 ~ /^".*"$/ || $0 ~ /^\047.*\047$/) $0 = substr($0, 2, length($0)-2)
            print; exit
        }' "$file"
}

if [ "$#" -eq 2 ]; then
    agent=$1
    name=$2
    case "$agent$name" in *[!a-zA-Z0-9_-]*) exit 1 ;; esac
    [ -n "$agent" ] && [ -n "$name" ] || exit 1
    [ "$agent" != main ] || exit 1
    file=/data/agents/$agent/cron/$name.md
    [ -f "$file" ] || exit 0
    [ "$(field enabled)" != false ] || exit 0
    kanban=/data/agents/$agent/kanban
    id=cron-$name-$(date -u +%Y%m%d-%H%M)

    # A completed occurrence stays deduplicated; pending work skips overlap.
    for task in "$kanban"/*/"$id.md"; do
        [ ! -f "$task" ] || exit 0
    done
    for task in "$kanban"/todo/cron-*.md "$kanban"/in-progress/cron-*.md; do
        [ -f "$task" ] || continue
        if grep -Fxq "schedule_id: $name" "$task"; then exit 0; fi
    done

    mkdir -p "$kanban/todo"
    temporary=$kanban/todo/.$id.$$.tmp
    trap 'rm -f "$temporary"' EXIT
    {
        printf '%s\n' '---' "id: $id" "created: $(date -u +%Y-%m-%dT%H:%M:%SZ)" \
            'created_by: cron' 'priority: normal' "schedule_id: $name" \
            "scheduled_for: $(date -u +%Y-%m-%dT%H:%M:00Z)"
        group=$(field group)
        case "$group" in
            '') ;;
            *[!a-zA-Z0-9_-]*) echo "Invalid group in $file" >&2; exit 1 ;;
            *) printf 'group: %s\n' "$group" ;;
        esac
        printf '%s\n' '---'
        awk 'NR == 1 { next } !body && $0 == "---" { body=1; next } body' "$file"
    } > "$temporary"
    mv "$temporary" "$kanban/todo/$id.md"
    exit 0
fi

spool=/run/agent-fs/cron
mkdir -p "$spool"
: > "$spool/root"
crond -f -d 8 -c "$spool" &
daemon=$!
trap 'kill "$daemon" 2>/dev/null || true; rm -f "$spool/.root.tmp"' EXIT
trap 'exit 0' INT TERM

while kill -0 "$daemon" 2>/dev/null; do
    {
        for file in /data/agents/*/cron/*.md; do
            [ -f "$file" ] || continue
            directory=${file%/cron/*}
            agent=${directory##*/}
            name=${file##*/}
            name=${name%.md}
            case "$agent$name" in *[!a-zA-Z0-9_-]*) continue ;; esac
            [ "$agent" != main ] && [ -n "$name" ] || continue
            [ -f "$directory/agent.json" ] && [ -f "$directory/Dockerfile" ] || continue
            [ "$(field enabled)" != false ] || continue
            schedule=$(field schedule)
            # Numeric five-field cron only; never interpolate shell commands.
            if ! printf '%s\n' "$schedule" | awk '
                NF != 5 || /[^0-9*,\/ \t-]/ { exit 1 }'; then
                echo "Invalid schedule in $file" >&2
                continue
            fi
            printf '%s /usr/local/bin/cron-tasks %s %s\n' "$schedule" "$agent" "$name"
        done
    } > "$spool/.root.tmp"
    if ! cmp -s "$spool/.root.tmp" "$spool/root"; then
        mv "$spool/.root.tmp" "$spool/root"
        printf 'root\n' > "$spool/cron.update"
    fi
    sleep 5
done
exit 1

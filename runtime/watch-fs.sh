#!/bin/sh
# Watch agent folders, build their images and start containers when work arrives.
# Keeps main's chat environment running, starts queued work and sends task updates
# back to main, so delegation does not keep a chat request open.
set -eu

# Locks survive a container restart, but the replies holding them do not.
rm -rf /run/shoebox/locks
mkdir -p /run/shoebox/outbox /run/shoebox/locks /data/.builds /data/.updates /data/.inbox /data/.control
docker rm -f main-chat >/dev/null 2>&1 || true
# Booting already starts fresh containers, which applies any pending restart.
rm -f /data/.control/restart

# Optional channels are separate commands, passed through by Compose.
if [ "$#" -gt 0 ]; then
    "$@" &
fi

base_hash=$(find /agent-base -type f -exec sha256sum {} \; | sort | sha256sum | cut -d ' ' -f 1)

running() {
    [ "$(docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null)" = true ]
}

# Main writes this after the user confirms; new containers give every chat the changed config.
restart_agents() {
    request=/data/.control/restart
    [ -f "$request" ] || return 0
    if ! grep -qx 'confirmed_by: user' "$request"; then
        printf '%s rejected: request lacks the user confirmation\n' "$(date -u +%FT%TZ)" >> /data/.control/restart.log
        rm -f "$request"
        return 0
    fi
    # chat-main waits while this lock exists, so no reply starts during the check.
    lock=/run/shoebox/locks/.restart
    mkdir "$lock" 2>/dev/null || return 0
    if idle; then
        reason=$(sed -n 's/^reason: //p' "$request" | head -n 1)
        rm -f "$request"
        docker ps -aq | xargs -r docker rm -f >/dev/null
        if start-agent main >/dev/null; then result=restarted; else result=failed; fi
        printf '%s %s: %s\n' "$(date -u +%FT%TZ)" "$result" "${reason:-no reason given}" | tee -a /data/.control/restart.log
    fi
    rmdir "$lock"
}

# Idle means no chat reply, task container or native TUI session is running.
idle() {
    for busy in /run/shoebox/locks/*; do
        [ ! -e "$busy" ] || return 1
    done
    [ -z "$(docker ps -q --filter name=^agent-)" ] || return 1
    ! docker exec main-chat sh -c 'for process in /proc/[0-9]*; do
            tr "\0" " " < "$process/cmdline" 2>/dev/null | grep -q "[a]gent-run" && exit 0
        done; exit 1' >/dev/null 2>&1
}

notify_update() {
    notify_task=$1
    notify_from=$2
    notify_status=$3
    notify_conversation=$4
    [ "$notify_status" != in-progress ] || return 0
    printf 'kanban> %s: %s -> %s\n' "$notify_task" "$notify_from" "$notify_status"
    case "$notify_conversation" in
        ''|*[!a-zA-Z0-9_-]*) return 0 ;;
    esac

    notify_prompt=$(printf 'Task update: %s -> %s.\nTask: %s\nReport the status, not the task output. If done, say which task finished and ask whether to share its result. Do not wait or poll.\n' \
        "$notify_from" "$notify_status" "$notify_task")
    case "$notify_conversation" in
        native-*)
            # Creation is already visible in the TUI's tool calls and main's reply.
            if [ "$notify_from" = new ] && { [ "$notify_status" = todo ] || [ "$notify_status" = backlog ]; }; then
                return 0
            fi
            printf '%s' "$notify_prompt" | chat-main "$notify_conversation"
            return $? ;;
    esac

    # Main already confirms newly queued tasks in its dispatch reply.
    if [ "$notify_from" = new ] && { [ "$notify_status" = todo ] || [ "$notify_status" = backlog ]; }; then
        return 0
    fi

    case "$notify_conversation" in
        telegram-*)
            notify_title=$(awk '/^# / { sub(/^# /, ""); print; exit }' "$notify_task" 2>/dev/null || true)
            notify_prompt=$(printf '%s\nTask title: %s\n%s\n' "$notify_prompt" "${notify_title:-the requested task}" \
                'Write a brief, natural Telegram message in the language of this conversation. Describe the task by its readable title or purpose, never its ID, filename, path, or Kanban state. Do not include technical transitions, role prefixes, or Markdown formatting. If done, say it is ready and offer to share the result. If blocked, explain what is needed in plain language. Do not include the task output.') ;;
    esac
    # Scheduled digests are requested deliveries, so include their result directly.
    # Ordinary task updates keep the existing status-only behaviour.
    if [ "$notify_status" = done ] && grep -q '^schedule_id: ' "$notify_task"; then
        notify_prompt=$(printf 'Scheduled task completed: %s\nRead its ## Result and deliver the full digest now, in its original language. Do not ask whether to share it. Do not add task IDs, paths or status chatter.\n' "$notify_task")
    fi
    if ! notify_text=$(printf '%s' "$notify_prompt" | chat-main "$notify_conversation"); then
        echo "Could not report $notify_task; will retry." >&2
        return 1
    fi

    update_number=$((update_number + 1))
    notify_outbox=/run/shoebox/outbox/$notify_conversation
    mkdir -p "$notify_outbox"
    printf '%s\n' "$notify_text" > "$notify_outbox/.update.tmp"
    mv "$notify_outbox/.update.tmp" "$notify_outbox/$(printf '%012d' "$update_number").txt"
}

report_updates() {
    initial=yes
    update_number=0
    while :; do
        for task in /data/agents/*/kanban/*/*.md; do
            [ -f "$task" ] || continue
            folder=${task%/*}
            status=${folder##*/}
            kanban=${folder%/*}
            agent=${kanban%/kanban}
            filename=${task##*/}
            case "$status" in
                backlog|todo|in-progress)
                    # File-only agents can briefly leave a completed copy too.
                    if [ -f "$kanban/done/$filename" ] || [ -f "$kanban/blocked/$filename" ]; then
                        continue
                    fi ;;
                blocked) [ ! -f "$kanban/done/$filename" ] || continue ;;
                done) ;;
                *) continue ;;
            esac
            record=/data/.updates/${agent##*/}/$filename
            previous=
            if [ -f "$record" ]; then read -r previous conversation < "$record"; fi
            [ "$previous" != "$status" ] || continue
            conversation=$(awk 'NR > 1 && $0 == "---" { exit }
                /^group: / { sub(/^group: /, ""); print; exit }' "$task" 2>/dev/null || true)
            if [ "$initial" != yes ] || [ -n "$previous" ]; then
                notify_update "$task" "${previous:-new}" "$status" "$conversation" || continue
            fi
            mkdir -p "${record%/*}"
            printf '%s %s\n' "$status" "$conversation" > "$record"
        done

        for record in /data/.updates/*/*.md; do
            [ -f "$record" ] || continue
            read -r status conversation < "$record"
            agent=${record%/*}
            kanban=/data/agents/${agent##*/}/kanban
            task=$kanban/$status/${record##*/}
            present=no
            for copy in "$kanban"/*/"${record##*/}"; do
                if [ -f "$copy" ]; then present=yes; break; fi
            done
            [ "$present" = no ] || continue
            notify_update "$task" "$status" removed "$conversation" || continue
            rm "$record"
        done
        initial=no
        sleep 1
    done
}

# Reporting may call an LLM; keep it separate from starting agent containers.
report_updates &
reporter=$!
cron-tasks &
scheduler=$!
trap 'kill "$reporter" "$scheduler" 2>/dev/null || true' EXIT
trap 'exit 0' INT TERM

echo 'runtime up; watching /data/agents'
while :; do
    for agent in /data/agents/*; do
        [ -f "$agent/agent.json" ] && [ -f "$agent/Dockerfile" ] || continue
        name=${agent##*/}

        # Build lazily so an empty install doesn't need an agent image.
        if [ "$(cat /data/.builds/base 2>/dev/null)" != "$base_hash" ]; then
            docker build -t agent-base /agent-base || break
            printf '%s\n' "$base_hash" > /data/.builds/base
        fi

        mkdir -p "$agent/home/workspace"
        if [ ! -f "$agent/home/memory.md" ]; then
            printf '# memory\n' > "$agent/home/memory.md"
        fi
        if [ "$name" != main ]; then
            for status in backlog todo in-progress blocked done; do
                mkdir -p "$agent/kanban/$status"
            done
        fi

        hash=$({
            cat "$agent/Dockerfile"
            if [ -d "$agent/build" ]; then
                find "$agent/build" -type f -exec sha256sum {} \; | sort
            fi
            printf '%s' "$base_hash"
        } | sha256sum | cut -d ' ' -f 1)
        if [ "$(cat "/data/.builds/$name" 2>/dev/null)" != "$hash" ]; then
            if [ -d "$agent/build" ]; then
                docker build -t "agent-$name" "$agent" || continue
            else
                docker build -t "agent-$name" - < "$agent/Dockerfile" || continue
            fi
            printf '%s\n' "$hash" > "/data/.builds/$name"
        fi

        if [ "$name" = main ]; then
            if ! running main-chat; then
                start-agent main || true
            fi
            continue
        fi

        if running "agent-$name"; then
            continue
        fi
        for task in "$agent"/kanban/todo/*.md "$agent"/kanban/in-progress/*.md; do
            [ -f "$task" ] || continue
            start-agent "$name" || true
            break
        done
    done
    # After this pass's builds, so restarted containers use the rebuilt images.
    restart_agents
    sleep 2
done

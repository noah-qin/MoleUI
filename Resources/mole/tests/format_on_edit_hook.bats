#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    HOOK="$PROJECT_ROOT/.claude/hooks/format-on-edit.sh"
    TEST_REPO="$(cd -P "$BATS_TEST_TMPDIR" && pwd)/repo"
    STUB_BIN="$BATS_TEST_TMPDIR/bin"
    FORMAT_LOG="$BATS_TEST_TMPDIR/format.log"

    mkdir -p "$TEST_REPO/cmd/demo" "$TEST_REPO/scripts" "$STUB_BIN"
    git init -q "$TEST_REPO"
    printf 'package demo\n' > "$TEST_REPO/cmd/demo/main.go"
    printf '#!/bin/bash\n' > "$TEST_REPO/scripts/demo.sh"

    cat > "$STUB_BIN/goimports" <<'SH'
#!/bin/bash
printf 'goimports:%s\n' "$*" >> "$FORMAT_LOG"
SH
    cat > "$STUB_BIN/shfmt" <<'SH'
#!/bin/bash
printf 'shfmt:%s\n' "$*" >> "$FORMAT_LOG"
SH
    chmod +x "$STUB_BIN/goimports" "$STUB_BIN/shfmt"
}

run_hook() {
    local payload="$1"
    # shellcheck disable=SC2016  # the inner bash receives payload and hook as argv
    run env PATH="$STUB_BIN:$PATH" FORMAT_LOG="$FORMAT_LOG" \
        /bin/bash -c 'printf "%s\n" "$1" | /bin/bash "$2"' _ "$payload" "$HOOK"
}

@test "Claude file_path payload formats one repository file" {
    payload=$(jq -nc \
        --arg cwd "$TEST_REPO" \
        --arg file "$TEST_REPO/cmd/demo/main.go" \
        '{cwd: $cwd, tool_input: {file_path: $file}}')

    run_hook "$payload"

    [ "$status" -eq 0 ]
    [ "$(cat "$FORMAT_LOG")" = "goimports:-w -local github.com/tw93/mole $TEST_REPO/cmd/demo/main.go" ]
}

@test "hook refuses files and symlink targets outside the repository" {
    outside="$BATS_TEST_TMPDIR/outside.go"
    printf 'package outside\n' > "$outside"
    ln -s "$outside" "$TEST_REPO/cmd/demo/link.go"

    payload=$(jq -nc \
        --arg cwd "$TEST_REPO" \
        --arg file "$outside" \
        '{cwd: $cwd, tool_input: {file_path: $file}}')
    run_hook "$payload"
    [ "$status" -eq 0 ]

    payload=$(jq -nc \
        --arg cwd "$TEST_REPO" \
        --arg file "$TEST_REPO/cmd/demo/link.go" \
        '{cwd: $cwd, tool_input: {file_path: $file}}')
    run_hook "$payload"
    [ "$status" -eq 0 ]
    [ ! -e "$FORMAT_LOG" ]
}

@test "Codex project skills are symlinks to the canonical Claude skills" {
    local skill
    local skill_link

    for skill in bugs mole release-flow release-notes; do
        skill_link="$PROJECT_ROOT/.agents/skills/$skill"
        [ -L "$skill_link" ]
        [ "$(readlink "$skill_link")" = "../../.claude/skills/$skill" ]
        [ -f "$skill_link/SKILL.md" ]
    done

    skill_link="$PROJECT_ROOT/.agents/skills/release-notes"
    [ -x "$skill_link/scripts/post-reactions.sh" ]
    grep -q '^policy:$' "$skill_link/agents/openai.yaml"
    grep -q '^  allow_implicit_invocation: false$' "$skill_link/agents/openai.yaml"
}

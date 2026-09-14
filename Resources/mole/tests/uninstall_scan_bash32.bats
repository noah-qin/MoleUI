#!/usr/bin/env bats

# Regression for #863: "Can't Open App List, Scanning forever."
#
# macOS ships /bin/bash 3.2 (Apple does not upgrade past it, GPLv3). The
# bin/uninstall.sh shebang is `#!/bin/bash`, so the installed script runs
# under 3.2 regardless of any Homebrew bash also on the system. Under
# `set -u`, bash 3.2 treats `"${empty_array[@]}"` as an unbound expansion
# rather than expanding to zero elements.
#
# scan_applications declares `local -a app_data_tuples=()` and only appends
# rows for apps that miss the warm metadata cache (uncached_rows_file). When
# every discovered app is satisfied by the cache, app_data_tuples stays
# empty while scan_raw_file is non-empty (use_cached_scan_metadata already
# wrote rows to it). The early-return at the `[[ ... && ! -s ... ]]` guard
# therefore does not fire, and the subsequent `for ... in
# "${app_data_tuples[@]}"` iteration aborts with
# "app_data_tuples[@]: unbound variable".

setup_file() {
	PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
	export PROJECT_ROOT
}

setup() {
	HOME="$(mktemp -d "${BATS_TEST_DIRNAME}/tmp-scan-bash32.XXXXXX")"
	export HOME
	# Safety: refuse to operate on a real home directory.
	if [[ "$HOME" != "${BATS_TEST_DIRNAME}/tmp-"* ]]; then
		printf 'FATAL: HOME is not a test temp dir: %s\n' "$HOME" >&2
		return 1
	fi
	export TERM="dumb"
}

teardown() {
	if [[ "$HOME" == "${BATS_TEST_DIRNAME}/tmp-"* ]]; then
		rm -rf "$HOME"
	fi
}

# Build a sourceable copy of bin/uninstall.sh: rewrites SCRIPT_DIR so library
# sources resolve, and strips the `main "$@"` invocation so we can drive
# scan_applications directly.
sourceable_uninstall_sh() {
	local out="$1"
	awk -v script_dir="$PROJECT_ROOT/bin" '
		/^SCRIPT_DIR=/ { print "SCRIPT_DIR=\"" script_dir "\""; next }
		/main "\$@"/ { print "# main skipped by test"; next }
		{ print }
	' "$PROJECT_ROOT/bin/uninstall.sh" > "$out"
}

create_test_app_bundle() {
	local app_path="$1"
	local bundle_id="$2"
	local display_name="$3"
	local background_only="${4:-false}"

	mkdir -p "$app_path/Contents"
	cat > "$app_path/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>$bundle_id</string>
    <key>CFBundleName</key>
    <string>$display_name</string>
</dict>
</plist>
PLIST

	if [[ "$background_only" == "true" ]]; then
		/usr/libexec/PlistBuddy -c "Add :LSBackgroundOnly bool true" \
			"$app_path/Contents/Info.plist" > /dev/null 2>&1
	fi
}

@test "scan_applications: Pass 2 tolerates empty app_data_tuples on /bin/bash 3.2 (#863)" {
	src="$HOME/uninstall_source.sh"
	sourceable_uninstall_sh "$src"

	apps_root="$HOME/Applications"
	mkdir -p "$apps_root/TestApp.app/Contents"
	: > "$apps_root/TestApp.app/Contents/Info.plist"

	# Seed the warm metadata cache so that the one discovered app
	# (TestApp.app) is a cache hit: matching mtime, non-empty bundle id
	# and display name, plus a matching language signature, are the conditions
	# the awk classifier and
	# use_cached_scan_metadata require for the cached branch to "stick".
	app_mtime="$(stat -f %m "$apps_root/TestApp.app")"
	done_marker="$HOME/scan.done"

	# The bug not only emits "unbound variable"; the spinner subshell can
	# keep running after the parent script errors out. The user-visible
	# symptom is exactly "scanning forever". Mirror the marker-file watchdog
	# from the #722 hang test (uninstall.bats: "uninstall_persist_cache_file
	# does not hang...") so a regression surfaces as HANG rather than blocking
	# the whole bats run.
	(
		env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" \
			MOLE_TEST_NO_AUTH=1 \
			APPS_ROOT="$apps_root" APP_MTIME="$app_mtime" SRC_PATH="$src" \
			/bin/bash --noprofile --norc <<'EOF' > "$HOME/scan.out" 2> "$HOME/scan.err"
set -euo pipefail

# shellcheck source=/dev/null
source "$SRC_PATH"

# Seed the production cache schema after sourcing so the language signature
# exactly matches the preference snapshot used by this scan.
mkdir -p "$MOLE_UNINSTALL_META_CACHE_DIR"
printf '%s|%s|4|0|0|com.test.TestApp|TestApp|%s\n' \
	"$APPS_ROOT/TestApp.app" "$APP_MTIME" "$MOLE_UNINSTALL_LANGUAGE_SIGNATURE" \
	> "$MOLE_UNINSTALL_META_CACHE_FILE"

# Skip the real pkgutil receipt scan: it walks every package on the host and
# can take longer than this test's watchdog on machines with large receipt
# databases. The regression under test is the empty app_data_tuples guard.
pkg_receipt_nonstandard_app_paths() { return 0; }

# Restrict the discovered search dirs to our sandboxed Applications folder
# so scan_applications does not pick up real /Applications and dilute the
# all-cached condition we are exercising.
uninstall_print_app_search_dirs() { printf '%s\n' "$APPS_ROOT"; }

# Bundle-id resolution would otherwise call /usr/bin/mdls and reject our
# placeholder Info.plist. The cached branch only needs an echo-through here.
uninstall_resolve_eligible_bundle_id() { printf '%s\n' "${2:-${1##*/}}"; }
uninstall_resolve_display_name() {
	: > "$HOME/name-resolved"
	printf 'TestApp\n'
}

scan_applications > /dev/null
[[ ! -e "$HOME/name-resolved" ]] || exit 2
EOF
		: > "$done_marker"
	) &
	bgpid=$!

	# Poll for completion marker for up to ~5s.
	for _ in $(seq 1 50); do
		[[ -e "$done_marker" ]] && break
		sleep 0.1
	done

	status_msg=""
	if [[ ! -e "$done_marker" ]]; then
		kill -TERM "$bgpid" 2> /dev/null || true
		# Reap the orphaned spinner subshell so it does not leak into the
		# next test or the rest of the run.
		pkill -P "$bgpid" 2> /dev/null || true
		status_msg="HANG"
	fi
	wait "$bgpid" 2> /dev/null || true

	[[ -z "$status_msg" ]] || {
		echo "scan_applications hung, Pass 2 guard regressed" >&2
		echo "stderr captured:" >&2
		cat "$HOME/scan.err" >&2 2> /dev/null || true
		false
	}
	# Use `run` + status check rather than bare `! grep`: bats SC2314 rejects
	# a trailing `!` because earlier bats versions ignored it. `run` records
	# the inverted status explicitly so the assertion is portable.
	run grep -q 'unbound variable' "$HOME/scan.err"
	[ "$status" -ne 0 ]
}

@test "scan_applications refreshes only a cached localized name when AppleLanguages changes (#1520)" {
	src="$HOME/uninstall_source.sh"
	sourceable_uninstall_sh "$src"

	apps_root="$HOME/Applications"
	app_path="$apps_root/VideoFusion-macOS.app"
	create_test_app_bundle "$app_path" "com.example.VideoFusion" "VideoFusion-macOS"
	/usr/libexec/PlistBuddy -c "Add :CFBundleDevelopmentRegion string en" \
		"$app_path/Contents/Info.plist"
	mkdir -p "$app_path/Contents/Resources/en.lproj"
	printf '"CFBundleDisplayName" = "VideoFusion";\n' \
		> "$app_path/Contents/Resources/en.lproj/InfoPlist.strings"
	app_mtime="$(stat -f %m "$app_path")"

	bin_dir="$HOME/bin"
	mkdir -p "$bin_dir"
	cat > "$bin_dir/defaults" <<'EOF'
#!/bin/sh
printf '(\n    "en-CN",\n    "zh-Hans-CN"\n)\n'
EOF
	chmod +x "$bin_dir/defaults"

	run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" PATH="$bin_dir:$PATH" \
		MOLE_TEST_NO_AUTH=1 APPS_ROOT="$apps_root" APP_PATH="$app_path" \
		APP_MTIME="$app_mtime" SRC_PATH="$src" \
		/bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$SRC_PATH"

uninstall_print_app_search_dirs() { printf '%s\n' "$APPS_ROOT"; }
pkg_receipt_nonstandard_app_paths() { return 0; }
uninstall_quick_app_size_kb() { printf '0\n'; }
uninstall_inline_du_size_kb() { printf '0\n'; }
start_uninstall_metadata_refresh() { :; }

mkdir -p "$MOLE_UNINSTALL_META_CACHE_DIR"
printf '%s|%s|4096|1700000000|1700000001|com.example.VideoFusion|剪映专业版|old-language-signature\n' \
	"$APP_PATH" "$APP_MTIME" > "$MOLE_UNINSTALL_META_CACHE_FILE"

apps_file=$(scan_applications)
result=$(cat "$apps_file")
[[ "$result" == *"|$APP_PATH|VideoFusion|com.example.VideoFusion|4.2MB|"* ]] || {
	printf 'unexpected scan result: %s\n' "$result" >&2
	exit 1
}
[[ "$result" != *"剪映专业版"* ]] || exit 2

IFS='|' read -r cached_path cached_mtime cached_size cached_epoch cached_updated \
	cached_bundle cached_name cached_language < "$MOLE_UNINSTALL_META_CACHE_FILE"
[[ "$cached_path" == "$APP_PATH" ]] || exit 3
[[ "$cached_mtime" == "$APP_MTIME" ]] || exit 4
[[ "$cached_size" == "4096" ]] || exit 5
[[ "$cached_epoch" == "1700000000" ]] || exit 6
[[ "$cached_updated" == "1700000001" ]] || exit 7
[[ "$cached_bundle" == "com.example.VideoFusion" ]] || exit 8
[[ "$cached_name" == "VideoFusion" ]] || exit 9
[[ -n "$cached_language" && "$cached_language" != "old-language-signature" ]] || exit 10
EOF

	[ "$status" -eq 0 ] || {
		echo "$output"
		return 1
	}
}

@test "app discovery treats the app suffix case-insensitively without admitting nested bundles" {
	src="$HOME/uninstall_source.sh"
	sourceable_uninstall_sh "$src"

	apps_root="$HOME/Applications"
	mkdir -p \
		"$apps_root/Upper.APP" \
		"$apps_root/Mixed.App" \
		"$apps_root/Lower.app" \
		"$apps_root/Receipt.APP" \
		"$apps_root/Outer.APP/Nested.app"

	run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" \
		APPS_ROOT="$apps_root" SRC_PATH="$src" \
		/bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$SRC_PATH"

uninstall_print_app_search_dirs() { printf '%s\n' "$APPS_ROOT"; }
pkg_receipt_nonstandard_app_paths() { printf '%s\n' "$APPS_ROOT/Receipt.APP"; }
get_file_mtime() { printf '1\n'; }

discovered_file="$HOME/discovered"
: > "$discovered_file"
_scan_discover_apps
cat "$discovered_file"
EOF

	[ "$status" -eq 0 ] || return 1
	[ "$(printf '%s\n' "$output" | grep -cF "$apps_root/Upper.APP|Upper|1")" -eq 1 ] || return 1
	[ "$(printf '%s\n' "$output" | grep -cF "$apps_root/Mixed.App|Mixed|1")" -eq 1 ] || return 1
	[ "$(printf '%s\n' "$output" | grep -cF "$apps_root/Lower.app|Lower|1")" -eq 1 ] || return 1
	[ "$(printf '%s\n' "$output" | grep -cF "$apps_root/Receipt.APP|Receipt|1")" -eq 1 ] || return 1
	[[ "$output" != *"Outer.APP/Nested.app"* ]]
}

@test "bundle dedupe ranks direct mixed-case app paths before user copies" {
	src="$HOME/uninstall_source.sh"
	sourceable_uninstall_sh "$src"

	run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" SRC_PATH="$src" \
		/bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$SRC_PATH"

scan_raw_file="$HOME/raw"
printf '%s\n' \
	"$HOME/Applications/Shared.APP|Shared|com.example.shared|1|1" \
	"/Applications/Shared.APP|Shared|com.example.shared|1|1" \
	> "$scan_raw_file"

_scan_dedupe_bundle_ids
cat "$scan_raw_file"
EOF

	[ "$status" -eq 0 ] || return 1
	[ "$(printf '%s\n' "$output" | grep -cF 'com.example.shared')" -eq 1 ] || return 1
	[[ "$output" == "/Applications/Shared.APP|Shared|com.example.shared|1|1" ]]
}

@test "scan_applications surfaces inline physical app size before deferred refresh (#1126)" {
	src="$HOME/uninstall_source.sh"
	sourceable_uninstall_sh "$src"

	apps_root="$HOME/Applications"
	app_path="$apps_root/SizedApp.app"
	create_test_app_bundle "$app_path" "com.example.SizedApp" "SizedApp"

	run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" \
		MOLE_TEST_NO_AUTH=1 APPS_ROOT="$apps_root" SRC_PATH="$src" \
		MOLE_UNINSTALL_INLINE_MDLS_DISPLAY_TIMEOUT_SEC=0 \
		MOLE_UNINSTALL_INLINE_MDLS_SIZE_TIMEOUT_SEC=0 \
		/bin/bash --noprofile --norc <<'EOF'
set -euo pipefail

# shellcheck source=/dev/null
source "$SRC_PATH"

uninstall_print_app_search_dirs() { printf '%s\n' "$APPS_ROOT"; }
mdls() {
    if [[ "${2:-}" == "kMDItemPhysicalSize" ]]; then
        printf '4096000\n'
        return 0
    fi
    printf '(null)\n'
}

apps_file=$(scan_applications)
cat "$apps_file"
EOF

	[ "$status" -eq 0 ]
	[[ "$output" == *"|$app_path|SizedApp|com.example.SizedApp|4.1MB|"* ]] || return 1
	[[ "$output" == *"|4000" ]]
}

@test "uninstall metadata cache version invalidates logical-size snapshots" {
	src="$HOME/uninstall_source.sh"
	sourceable_uninstall_sh "$src"

	run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" SRC_PATH="$src" \
		/bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$SRC_PATH"
[[ "$MOLE_UNINSTALL_META_CACHE_FILE" == */uninstall_app_metadata_v3 ]]
EOF

	[ "$status" -eq 0 ]
}

@test "scan_applications falls back to bounded du when the quick mdls size probe misses" {
	src="$HOME/uninstall_source.sh"
	sourceable_uninstall_sh "$src"

	apps_root="$HOME/Applications"
	app_path="$apps_root/DuApp.app"
	create_test_app_bundle "$app_path" "com.example.DuApp" "DuApp"

	run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" \
		MOLE_TEST_NO_AUTH=1 APPS_ROOT="$apps_root" SRC_PATH="$src" \
		MOLE_UNINSTALL_INLINE_MDLS_DISPLAY_TIMEOUT_SEC=0 \
		MOLE_UNINSTALL_INLINE_MDLS_SIZE_TIMEOUT_SEC=0 \
		MOLE_UNINSTALL_INLINE_DU_SIZE_TIMEOUT_SEC=0 \
		/bin/bash --noprofile --norc <<'EOF'
set -euo pipefail

# shellcheck source=/dev/null
source "$SRC_PATH"

uninstall_print_app_search_dirs() { printf '%s\n' "$APPS_ROOT"; }
# Spotlight has not indexed the freshly installed app yet.
mdls() { printf '(null)\n'; }
du() { printf '2048\t/mocked\n'; }

apps_file=$(scan_applications)
cat "$apps_file"
EOF

	[ "$status" -eq 0 ]
	[[ "$output" == *"|$app_path|DuApp|com.example.DuApp|2.1MB|"* ]] || return 1
	[[ "$output" == *"|2048" ]]
}

@test "scan_applications keeps the fast path when cold rows exceed the du fallback cap" {
	src="$HOME/uninstall_source.sh"
	sourceable_uninstall_sh "$src"

	apps_root="$HOME/Applications"
	app_path="$apps_root/CapApp.app"
	create_test_app_bundle "$app_path" "com.example.CapApp" "CapApp"

	run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" \
		MOLE_TEST_NO_AUTH=1 APPS_ROOT="$apps_root" SRC_PATH="$src" \
		MOLE_UNINSTALL_INLINE_MDLS_DISPLAY_TIMEOUT_SEC=0 \
		MOLE_UNINSTALL_INLINE_MDLS_SIZE_TIMEOUT_SEC=0 \
		MOLE_UNINSTALL_INLINE_DU_SIZE_TIMEOUT_SEC=0 \
		MOLE_UNINSTALL_INLINE_DU_MAX_COLD_ROWS=0 \
		/bin/bash --noprofile --norc <<'EOF'
set -euo pipefail

# shellcheck source=/dev/null
source "$SRC_PATH"

uninstall_print_app_search_dirs() { printf '%s\n' "$APPS_ROOT"; }
mdls() { printf '(null)\n'; }
du() { printf '2048\t/mocked\n'; }

apps_file=$(scan_applications)
cat "$apps_file"
EOF

	[ "$status" -eq 0 ]
	[[ "$output" == *"|$app_path|CapApp|com.example.CapApp|--|"* ]] || return 1
	[[ "$output" == *"|0" ]]
}

@test "scan_applications includes Artpaper's two-segment bundle id (#861)" {
	src="$HOME/uninstall_source.sh"
	sourceable_uninstall_sh "$src"

	apps_root="$HOME/Applications"
	app_path="$apps_root/Artpaper.app"
	mkdir -p "$app_path/Contents"
	cat > "$app_path/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>andriiliakh.Artpaper</string>
    <key>CFBundleName</key>
    <string>Artpaper</string>
</dict>
</plist>
PLIST

	run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" \
		MOLE_TEST_NO_AUTH=1 APPS_ROOT="$apps_root" SRC_PATH="$src" \
		/bin/bash --noprofile --norc <<'EOF'
set -euo pipefail

# shellcheck source=/dev/null
source "$SRC_PATH"

uninstall_print_app_search_dirs() { printf '%s\n' "$APPS_ROOT"; }

apps_file=$(scan_applications)
cat "$apps_file"
EOF

	[ "$status" -eq 0 ]
	[[ "$output" == *"|$app_path|Artpaper|andriiliakh.Artpaper|"* ]]
}

@test "scan_applications includes top-level background apps but excludes nested helpers (#970/#1265)" {
	src="$HOME/uninstall_source.sh"
	sourceable_uninstall_sh "$src"

	apps_root="$HOME/Applications"
	onedrive_app="$apps_root/OneDrive.app"
	betterdisplay_app="$apps_root/BetterDisplay.app"
	nested_helper="$apps_root/Vendor/Helper.app"
	create_test_app_bundle "$onedrive_app" "com.microsoft.OneDrive-mac" "OneDrive" true
	create_test_app_bundle "$betterdisplay_app" "pro.betterdisplay.BetterDisplay" "BetterDisplay" true
	create_test_app_bundle "$nested_helper" "com.example.Helper" "Helper" true

	run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" \
		MOLE_TEST_NO_AUTH=1 APPS_ROOT="$apps_root" SRC_PATH="$src" \
		/bin/bash --noprofile --norc <<'EOF'
set -euo pipefail

# shellcheck source=/dev/null
source "$SRC_PATH"

uninstall_print_app_search_dirs() { printf '%s\n' "$APPS_ROOT"; }

apps_file=$(scan_applications)
cat "$apps_file"
EOF

	[ "$status" -eq 0 ]
	[[ "$output" == *"|$onedrive_app|OneDrive|com.microsoft.OneDrive-mac|"* ]] || return 1
	[[ "$output" == *"|$betterdisplay_app|BetterDisplay|pro.betterdisplay.BetterDisplay|"* ]] || return 1
	[[ "$output" != *"|$nested_helper|Helper|com.example.Helper|"* ]] || return 1
}

@test "scan_applications dedupes backup Applications clones by bundle id (#975)" {
	src="$HOME/uninstall_source.sh"
	sourceable_uninstall_sh "$src"

	apps_root="$HOME/Applications"
	backup_root="$HOME/BackupClone/Applications"
	local_app="$apps_root/Dupe.app"
	backup_app="$backup_root/Dupe.app"
	create_test_app_bundle "$local_app" "com.example.Dupe" "Dupe"
	create_test_app_bundle "$backup_app" "com.example.Dupe" "Dupe"

	run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" \
		MOLE_TEST_NO_AUTH=1 APPS_ROOT="$apps_root" BACKUP_ROOT="$backup_root" SRC_PATH="$src" \
		/bin/bash --noprofile --norc <<'EOF'
set -euo pipefail

# shellcheck source=/dev/null
source "$SRC_PATH"

uninstall_print_app_search_dirs() { printf '%s\n' "$APPS_ROOT" "$BACKUP_ROOT"; }

apps_file=$(scan_applications)
cat "$apps_file"
EOF

	[ "$status" -eq 0 ]
	[[ "$output" == *"|$local_app|Dupe|com.example.Dupe|"* ]] || return 1
	[[ "$output" != *"|$backup_app|Dupe|com.example.Dupe|"* ]]
}

@test "scan_applications keeps distinct installs sharing a bundle id (Xcode vs Xcode-beta)" {
	src="$HOME/uninstall_source.sh"
	sourceable_uninstall_sh "$src"

	apps_root="$HOME/Applications"
	stable_app="$apps_root/Xcode.app"
	beta_app="$apps_root/Xcode-beta.app"
	create_test_app_bundle "$stable_app" "com.apple.dt.Xcode" "Xcode"
	create_test_app_bundle "$beta_app" "com.apple.dt.Xcode" "Xcode"

	run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" \
		MOLE_TEST_NO_AUTH=1 APPS_ROOT="$apps_root" SRC_PATH="$src" \
		/bin/bash --noprofile --norc <<'EOF'
set -euo pipefail

# shellcheck source=/dev/null
source "$SRC_PATH"

uninstall_print_app_search_dirs() { printf '%s\n' "$APPS_ROOT"; }

apps_file=$(scan_applications)
cat "$apps_file"
EOF

	[ "$status" -eq 0 ]
	[[ "$output" == *"|$stable_app|"* ]] || return 1
	[[ "$output" == *"|$beta_app|"* ]]
}

@test "scan_applications keeps unique apps from backup Applications roots (#975)" {
	src="$HOME/uninstall_source.sh"
	sourceable_uninstall_sh "$src"

	backup_root="$HOME/BackupClone/Applications"
	backup_app="$backup_root/OnlyThere.app"
	create_test_app_bundle "$backup_app" "com.example.OnlyThere" "OnlyThere"

	run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" \
		MOLE_TEST_NO_AUTH=1 BACKUP_ROOT="$backup_root" SRC_PATH="$src" \
		/bin/bash --noprofile --norc <<'EOF'
set -euo pipefail

# shellcheck source=/dev/null
source "$SRC_PATH"

uninstall_print_app_search_dirs() { printf '%s\n' "$BACKUP_ROOT"; }

apps_file=$(scan_applications)
cat "$apps_file"
EOF

	[ "$status" -eq 0 ]
	[[ "$output" == *"|$backup_app|OnlyThere|com.example.OnlyThere|"* ]]
}

@test "scan_applications keeps original rows when dedupe pass fails (#975)" {
	src="$HOME/uninstall_source.sh"
	sourceable_uninstall_sh "$src"

	run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" SRC_PATH="$src" \
		/bin/bash --noprofile --norc <<'EOF'
set -euo pipefail

# shellcheck source=/dev/null
source "$SRC_PATH"

scan_raw_file="$HOME/scan.raw"
printf '%s\n' "$HOME/Applications/Keep.app|Keep|com.example.Keep|1" > "$scan_raw_file"

awk() { return 2; }

_scan_dedupe_bundle_ids
cat "$scan_raw_file"
EOF

	[ "$status" -eq 0 ]
	[[ "$output" == "$HOME/Applications/Keep.app|Keep|com.example.Keep|1" ]]
}

@test "scan_applications ignores PATH stat shims (#865)" {
	src="$HOME/uninstall_source.sh"
	sourceable_uninstall_sh "$src"

	apps_root="$HOME/Applications"
	app_path="$apps_root/Plain.app"
	mkdir -p "$app_path/Contents"
	cat > "$app_path/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.example.Plain</string>
    <key>CFBundleName</key>
    <string>Plain</string>
</dict>
</plist>
PLIST

	stub_dir="$HOME/stub-bin"
	mkdir -p "$stub_dir"
	cat > "$stub_dir/stat" <<'SH'
#!/bin/sh
exit 64
SH
	chmod +x "$stub_dir/stat"

	run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" \
		MOLE_TEST_NO_AUTH=1 APPS_ROOT="$apps_root" SRC_PATH="$src" \
		PATH="$stub_dir:$PATH" \
		/bin/bash --noprofile --norc <<'EOF'
set -euo pipefail

# shellcheck source=/dev/null
source "$SRC_PATH"

uninstall_print_app_search_dirs() { printf '%s\n' "$APPS_ROOT"; }

apps_file=$(scan_applications)
cat "$apps_file"
EOF

	[ "$status" -eq 0 ]
	[[ "$output" == *"|$app_path|Plain|com.example.Plain|"* ]]
}

@test "receipt discovery survives its first candidate on /bin/bash 3.2 (#1354)" {
	# The seen_apps dedup loop ran over "${seen_apps[@]}" while the array
	# was still empty for the first candidate; bash 3.2 under set -u
	# aborts that expansion, the scan subshell died, and the uninstall
	# spinner span forever. The candidate prefixes are fixed system paths,
	# so the harness rewrites them into the test HOME (same pattern as
	# sourceable_uninstall_sh) and leaves the loop under test untouched.
	local mock_bin="$HOME/mock-pkgutil"
	mkdir -p "$mock_bin" "$HOME/usr-local/Example.app/Contents"
	cat > "$mock_bin/pkgutil" << MOCK
#!/bin/bash
case "\$1" in
    --pkgs) printf 'com.example.tool\n' ;;
    --files) printf '${HOME#/}/usr-local/Example.app/Contents/Info.plist\n' ;;
esac
MOCK
	chmod +x "$mock_bin/pkgutil"

	# The copy must rename the load guard too: common.sh already sourced the
	# real file, and the readonly guard would silently keep the original
	# function, turning this test into a no-op against the wrong code.
	sed -e "s|/usr/local/|$HOME/usr-local/|g" \
		-e 's|MOLE_PKG_RECEIPTS_LOADED|MOLE_PKG_RECEIPTS_TEST_LOADED|g' \
		"$PROJECT_ROOT/lib/core/pkg_receipts.sh" > "$HOME/pkg_receipts_test.sh"

	run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" \
		PATH="$mock_bin:/usr/bin:/bin" \
		MOLE_PKG_RECEIPT_CACHE_DISABLE=1 /bin/bash --noprofile --norc << 'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$HOME/pkg_receipts_test.sh"

rc=0
out=$(pkg_receipt_nonstandard_app_paths) || rc=$?
printf 'RC=%s OUT=%s\n' "$rc" "$out"
EOF

	[ "$status" -eq 0 ] || {
		echo "$output"
		return 1
	}
	[[ "$output" != *"unbound variable"* ]] || return 1
	[[ "$output" == *"RC=0 OUT=$HOME/usr-local/Example.app"* ]] || return 1
}

@test "receipt discovery preserves mixed-case app bundles in complete scans" {
	local mock_bin="$HOME/mock-pkgutil-mixed-app"
	mkdir -p "$mock_bin" \
		"$HOME/usr-local/Direct.APP" \
		"$HOME/usr-local/Nested.App/Contents"
	cat > "$mock_bin/pkgutil" << MOCK
#!/bin/bash
case "\$1" in
    --pkgs) printf 'com.example.mixed-apps\n' ;;
    --files)
        printf '%s\n' \
            '${HOME#/}/usr-local/Direct.APP' \
            '${HOME#/}/usr-local/Nested.App/Contents/Info.plist'
        ;;
esac
MOCK
	chmod +x "$mock_bin/pkgutil"

	# Redirect the fixed production prefix into the isolated HOME while keeping
	# the real mixed-case parser and complete-scan contract under test.
	sed -e "s|/usr/local/|$HOME/usr-local/|g" \
		-e 's|MOLE_PKG_RECEIPTS_LOADED|MOLE_PKG_RECEIPTS_MIXED_TEST_LOADED|g' \
		"$PROJECT_ROOT/lib/core/pkg_receipts.sh" > "$HOME/pkg_receipts_mixed_test.sh"

	run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" \
		PATH="$mock_bin:/usr/bin:/bin" \
		MOLE_PKG_RECEIPT_CACHE_DISABLE=1 /bin/bash --noprofile --norc << 'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$HOME/pkg_receipts_mixed_test.sh"

pkg_receipt_nonstandard_app_paths --require-complete
EOF

	[ "$status" -eq 0 ] || {
		echo "$output"
		return 1
	}
	[[ "$output" == *"$HOME/usr-local/Direct.APP"* ]] || return 1
	[[ "$output" == *"$HOME/usr-local/Nested.App"* ]] || return 1
}

@test "a newly installed receipt invalidates the cached complete answer" {
	# uninstall reads a complete receipt answer as proof that no other install
	# owns an app's leftovers. A TTL alone cannot carry that proof: a sibling
	# packaged after the cache was written stays invisible for up to an hour,
	# and the shared-bundle-id guard then clears leftovers the survivor needs.
	# The cache is keyed by the receipt list, so installing anything busts it.
	local mock_bin="$HOME/mock-pkgutil-cache"
	local pkgs_file="$HOME/receipt-pkgs.txt"
	mkdir -p "$mock_bin" \
		"$HOME/usr-local/First.app/Contents" \
		"$HOME/usr-local/Second.app/Contents"
	cat > "$mock_bin/pkgutil" << MOCK
#!/bin/bash
case "\$1" in
    --pkgs) cat "$pkgs_file" ;;
    --files)
        case "\$2" in
            com.example.first) printf '${HOME#/}/usr-local/First.app/Contents/Info.plist\n' ;;
            com.example.second) printf '${HOME#/}/usr-local/Second.app/Contents/Info.plist\n' ;;
        esac
        ;;
esac
MOCK
	chmod +x "$mock_bin/pkgutil"
	printf 'com.example.first\n' > "$pkgs_file"

	sed -e "s|/usr/local/|$HOME/usr-local/|g" \
		-e 's|MOLE_PKG_RECEIPTS_LOADED|MOLE_PKG_RECEIPTS_TEST_LOADED|g' \
		"$PROJECT_ROOT/lib/core/pkg_receipts.sh" > "$HOME/pkg_receipts_cache_test.sh"

	run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" PKGS_FILE="$pkgs_file" \
		PATH="$mock_bin:/usr/bin:/bin" \
		MOLE_PKG_RECEIPT_CACHE_FILE="$HOME/receipt-cache" \
		/bin/bash --noprofile --norc << 'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$HOME/pkg_receipts_cache_test.sh"

first=$(pkg_receipt_nonstandard_app_paths --require-complete)
# Same receipts: the cache may answer, and must still answer correctly.
warm=$(pkg_receipt_nonstandard_app_paths --require-complete)
# A second package lands. The cached answer is now incomplete.
printf 'com.example.first\ncom.example.second\n' > "$PKGS_FILE"
after=$(pkg_receipt_nonstandard_app_paths --require-complete)
printf 'FIRST=[%s]\nWARM=[%s]\nAFTER=[%s]\n' \
    "$(printf '%s' "$first" | tr '\n' ' ')" \
    "$(printf '%s' "$warm" | tr '\n' ' ')" \
    "$(printf '%s' "$after" | tr '\n' ' ')"
EOF

	[ "$status" -eq 0 ] || {
		echo "$output"
		return 1
	}
	[[ "$output" == *"FIRST=[$HOME/usr-local/First.app]"* ]] || return 1
	[[ "$output" == *"WARM=[$HOME/usr-local/First.app]"* ]] || return 1
	# The whole point: the newly packaged sibling must appear immediately.
	[[ "$output" == *"AFTER=[$HOME/usr-local/First.app $HOME/usr-local/Second.app]"* ]] || return 1
}

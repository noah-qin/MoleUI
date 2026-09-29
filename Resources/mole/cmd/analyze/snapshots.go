//go:build darwin

package main

import (
	"context"
	"os/exec"
	"strings"
	"time"

	tea "github.com/charmbracelet/bubbletea"
)

const localSnapshotProbeTimeout = 3 * time.Second

type localSnapshotMsg struct {
	probeID int64
	count   int
	err     error
}

type localSnapshotCommandRunner func(context.Context, string, ...string) ([]byte, error)

func runLocalSnapshotCommand(ctx context.Context, name string, args ...string) ([]byte, error) {
	return exec.CommandContext(ctx, name, args...).Output()
}

func (m model) detectLocalSnapshotsCmd() tea.Cmd {
	run := m.snapshotRunner
	if run == nil {
		run = runLocalSnapshotCommand
	}
	return localSnapshotProbeCmd(run, m.snapshotProbeID)
}

func localSnapshotProbeCmd(run localSnapshotCommandRunner, probeID int64) tea.Cmd {
	return func() tea.Msg {
		ctx, cancel := context.WithTimeout(context.Background(), localSnapshotProbeTimeout)
		defer cancel()

		output, err := run(ctx, "/usr/bin/tmutil", "listlocalsnapshotdates", "/")
		if err != nil {
			return localSnapshotMsg{probeID: probeID, err: err}
		}

		return localSnapshotMsg{probeID: probeID, count: parseLocalSnapshotCount(output)}
	}
}

// parseLocalSnapshotCount ignores tmutil's localized heading and counts only
// the documented YYYY-MM-DD-HHMMSS snapshot-date rows. Snapshot sizes are
// intentionally not inferred because tmutil does not expose retained bytes.
func parseLocalSnapshotCount(data []byte) int {
	count := 0
	for line := range strings.SplitSeq(string(data), "\n") {
		if _, err := time.Parse("2006-01-02-150405", strings.TrimSpace(line)); err == nil {
			count++
		}
	}
	return count
}

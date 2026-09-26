package main

import (
	"encoding/json"
	"fmt"
	"os"
	"time"
)

// runWatchMode streams metrics continuously as newline-delimited JSON (one full
// MetricsSnapshot per line) using a single warm Collector, so rate metrics
// (network, disk IO) stay accurate across ticks.
func runWatchMode(interval time.Duration) {
	runWatchStdout(interval)
}

// watchState mirrors the TUI's collection cadence (cmd/status/main.go): a full
// collect priming the enrichment cache, then mostly fast collects that inherit
// the cached slow-changing fields, with periodic process/full refreshes.
type watchState struct {
	ready         bool
	lastFullAt    time.Time
	lastProcessAt time.Time
}

func (s *watchState) nextMode(now time.Time) collectionMode {
	return nextCollectionMode(s.ready, s.lastFullAt, s.lastProcessAt, now)
}

func (s *watchState) collect(c *Collector) (MetricsSnapshot, error) {
	now := time.Now()
	mode := s.nextMode(now)

	var (
		snap MetricsSnapshot
		err  error
	)
	switch mode {
	case collectionFull:
		snap, err = c.Collect()
	case collectionProcess:
		snap, err = c.CollectProcesses()
	default:
		snap, err = c.CollectFast()
	}

	if err == nil {
		recordCollectionFreshness(mode, snap.CollectedAt, &s.lastFullAt, &s.lastProcessAt)
		s.ready = true
	}
	return snap, err
}

// runWatchStdout emits the first snapshot immediately (so the consumer paints
// without waiting a full interval), then mirrors the TUI cadence: the first
// successful fast snapshot is followed by an immediate full snapshot, and later
// ticks wait for the configured interval after each collection finishes. Exits
// cleanly when stdout closes (parent process gone).
func runWatchStdout(interval time.Duration) {
	collector := NewCollector(processWatchOptionsFromFlags())
	enc := json.NewEncoder(os.Stdout)
	var st watchState

	for {
		wasReady := st.ready
		snap, err := st.collect(collector)
		if err != nil {
			fmt.Fprintf(os.Stderr, "status: collect failed: %v\n", err)
			if snap.CollectedAt.IsZero() {
				time.Sleep(interval)
				continue
			}
		}
		if err := enc.Encode(snap); err != nil {
			return // stdout closed; parent died, nothing left to feed.
		}
		if wasReady {
			time.Sleep(interval)
		}
	}
}

package main

import "time"

type collectionMode int

const (
	collectionFast collectionMode = iota
	collectionProcess
	collectionFull
)

type collectionResult struct {
	data        MetricsSnapshot
	err         error
	mode        collectionMode
	completedAt time.Time
}

func (c *Collector) collectMode(mode collectionMode) collectionResult {
	var data MetricsSnapshot
	var err error
	switch mode {
	case collectionFull:
		data, err = c.Collect()
	case collectionProcess:
		data, err = c.CollectProcesses()
	default:
		data, err = c.CollectFast()
	}
	return collectionResult{data: data, err: err, mode: mode, completedAt: time.Now()}
}

// collectionSchedule owns retry timing for both the TUI and watch stream.
// Attempts consume their interval even on failure; sample freshness belongs
// to the collector and is never inferred from these timestamps.
type collectionSchedule struct {
	hasSnapshot          bool
	lastFullAttemptAt    time.Time
	lastProcessAttemptAt time.Time
}

func (s collectionSchedule) nextMode(now time.Time) collectionMode {
	if !s.hasSnapshot {
		return collectionFast
	}
	if s.lastFullAttemptAt.IsZero() || now.Sub(s.lastFullAttemptAt) >= slowRefreshInterval {
		return collectionFull
	}
	if s.lastProcessAttemptAt.IsZero() || now.Sub(s.lastProcessAttemptAt) >= processWatchInterval {
		return collectionProcess
	}
	return collectionFast
}

// recordCompletion returns the wait before the next collection. Only the first
// usable fast snapshot gets immediate enrichment; an empty result always waits.
func (s *collectionSchedule) recordCompletion(result collectionResult, interval time.Duration) time.Duration {
	firstSnapshot := !s.hasSnapshot && !result.data.CollectedAt.IsZero()
	if result.mode == collectionFull {
		s.lastFullAttemptAt = result.completedAt
	}
	if result.mode == collectionFull || result.mode == collectionProcess {
		s.lastProcessAttemptAt = result.completedAt
	}
	s.hasSnapshot = s.hasSnapshot || !result.data.CollectedAt.IsZero()
	if firstSnapshot && result.mode == collectionFast {
		return 0
	}
	return interval
}

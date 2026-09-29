//go:build darwin

package main

import (
	"os"
	"strings"
)

const liveSortModeEnv = "MOLE_ANALYZE_LIVE_SORT"

func liveScanSortModeFromEnv() liveSortMode {
	switch strings.ToLower(strings.TrimSpace(os.Getenv(liveSortModeEnv))) {
	case "continuous":
		return liveSortContinuous
	default:
		return liveSortFreezeOnMove
	}
}

func nextLiveSortMode(mode liveSortMode) liveSortMode {
	if mode == liveSortContinuous {
		return liveSortFreezeOnMove
	}
	return liveSortContinuous
}

func liveSortModeLabel(mode liveSortMode) string {
	if mode == liveSortFreezeOnMove {
		return "freeze-on-move"
	}
	return "continuous"
}

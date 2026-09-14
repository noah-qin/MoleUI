package main

import (
	"fmt"
	"strings"
)

// Health score weights and thresholds.
const (
	// Weights.
	healthCPUWeight     = 30.0
	healthMemWeight     = 25.0
	healthDiskWeight    = 20.0
	healthThermalWeight = 15.0
	healthIOWeight      = 10.0

	// CPU.
	cpuNormalThreshold = 50.0
	cpuHighThreshold   = 85.0

	// Memory.
	memNormalThreshold     = 70.0
	memHighThreshold       = 88.0
	memPressureWarnPenalty = 5.0
	memPressureCritPenalty = 15.0

	// Disk.
	diskWarnThreshold = 80.0
	diskCritThreshold = 93.0

	// Thermal.
	thermalNormalThreshold = 65.0
	thermalHighThreshold   = 85.0

	// Disk IO (MB/s).
	ioNormalThreshold = 50.0
	ioHighThreshold   = 150.0

	// Battery.
	batteryCycleWarn   = 800
	batteryCycleDanger = 900
	batteryCapWarn     = 80
	batteryCapDanger   = 60

	// Uptime (seconds).
	uptimeWarnDays   = 7
	uptimeDangerDays = 14
	uptimeWarnSecs   = uptimeWarnDays * 86400
	uptimeDangerSecs = uptimeDangerDays * 86400

	// Score display bands (shared with view.go score styling).
	scoreExcellentThreshold = 85
	scoreGoodThreshold      = 65
	scoreFairThreshold      = 45
)

func calculateHealthScore(cpu CPUStatus, mem MemoryStatus, disks []DiskStatus, diskIO DiskIOStatus, thermal ThermalStatus, batteries []BatteryStatus, uptimeSecs uint64) (int, string) {
	score := 100.0
	issues := []string{}

	// CPU penalty.
	cpuPenalty := 0.0
	if cpu.Usage > cpuNormalThreshold {
		if cpu.Usage > cpuHighThreshold {
			// Scale across the remaining range up to 100% so the penalty keeps
			// growing with usage (matches the disk branch). Dividing by the raw
			// high threshold instead made the penalty drop past 85%, letting the
			// score rise as CPU load got worse.
			cpuPenalty = healthCPUWeight * (cpu.Usage - cpuNormalThreshold) / (100 - cpuNormalThreshold)
		} else {
			cpuPenalty = (healthCPUWeight / 2) * (cpu.Usage - cpuNormalThreshold) / (cpuHighThreshold - cpuNormalThreshold)
		}
	}
	score -= cpuPenalty
	if cpu.Usage > cpuHighThreshold {
		issues = append(issues, "High CPU")
	}

	// Memory penalty.
	memPenalty := 0.0
	if mem.UsedPercent > memNormalThreshold {
		if mem.UsedPercent > memHighThreshold {
			// Scale across the remaining range up to 100% so the penalty keeps
			// growing with usage (matches the disk branch). Dividing by the raw
			// normal threshold instead made the penalty drop past 88%, letting
			// the score rise as memory pressure got worse.
			memPenalty = healthMemWeight * (mem.UsedPercent - memNormalThreshold) / (100 - memNormalThreshold)
		} else {
			memPenalty = (healthMemWeight / 2) * (mem.UsedPercent - memNormalThreshold) / (memHighThreshold - memNormalThreshold)
		}
	}
	score -= memPenalty
	if mem.UsedPercent > memHighThreshold {
		issues = append(issues, "High Memory")
	}

	// Memory pressure penalty.
	switch mem.Pressure {
	case "warn":
		score -= memPressureWarnPenalty
		issues = append(issues, "Memory Pressure")
	case "critical":
		score -= memPressureCritPenalty
		issues = append(issues, "Critical Memory")
	}

	// Disk penalty.
	diskPenalty := 0.0
	if len(disks) > 0 {
		diskUsage := disks[0].UsedPercent
		if diskUsage > diskWarnThreshold {
			if diskUsage > diskCritThreshold {
				diskPenalty = healthDiskWeight * (diskUsage - diskWarnThreshold) / (100 - diskWarnThreshold)
			} else {
				diskPenalty = (healthDiskWeight / 2) * (diskUsage - diskWarnThreshold) / (diskCritThreshold - diskWarnThreshold)
			}
		}
		score -= diskPenalty
		if diskUsage > diskCritThreshold {
			issues = append(issues, "Disk Almost Full")
		}
	}
	for _, disk := range disks {
		if disk.SmartStatus == smartStatusFailing {
			if score > 44 {
				score = 44
			}
			issues = append(issues, "Disk SMART Failing")
			break
		}
	}

	// Thermal penalty.
	thermalPenalty := 0.0
	if thermal.CPUTemp > 0 {
		if thermal.CPUTemp > thermalNormalThreshold {
			if thermal.CPUTemp > thermalHighThreshold {
				thermalPenalty = healthThermalWeight
				issues = append(issues, "Overheating")
			} else {
				thermalPenalty = healthThermalWeight * (thermal.CPUTemp - thermalNormalThreshold) / (thermalHighThreshold - thermalNormalThreshold)
			}
		}
		score -= thermalPenalty
	}

	// Disk IO penalty.
	ioPenalty := 0.0
	totalIO := diskIO.ReadRate + diskIO.WriteRate
	if totalIO > ioNormalThreshold {
		if totalIO > ioHighThreshold {
			ioPenalty = healthIOWeight
			issues = append(issues, "Heavy Disk IO")
		} else {
			ioPenalty = healthIOWeight * (totalIO - ioNormalThreshold) / (ioHighThreshold - ioNormalThreshold)
		}
	}
	score -= ioPenalty

	// Battery health penalty (only when battery present).
	if len(batteries) > 0 {
		b := batteries[0]
		_, sev := batteryHealthLabel(b.CycleCount, b.Capacity)
		switch sev {
		case "danger":
			score -= 5
			issues = append(issues, "Battery Service Soon")
		case "warn":
			score -= 2
		}
	}

	// Uptime penalty (long uptime without restart).
	if uptimeSecs > uptimeDangerSecs {
		score -= 3
		issues = append(issues, "Restart Recommended")
	} else if uptimeSecs > uptimeWarnSecs {
		score -= 1
	}

	// Clamp score.
	if score < 0 {
		score = 0
	}
	if score > 100 {
		score = 100
	}

	// Build message.
	var msg string
	switch {
	case score >= scoreExcellentThreshold:
		msg = "Excellent"
	case score >= scoreGoodThreshold:
		msg = "Good"
	case score >= scoreFairThreshold:
		msg = "Fair"
	default:
		msg = "Needs Attention"
	}

	if len(issues) > 0 {
		msg = msg + ": " + strings.Join(issues, ", ")
	}

	return int(score), msg
}

// batteryHealthLabel returns a human-readable health label and severity based on cycle count and capacity.
// Severity is "ok", "warn", or "danger".
func batteryHealthLabel(cycles int, capacity int) (string, string) {
	if cycles > batteryCycleDanger || (capacity > 0 && capacity < batteryCapDanger) {
		return "Service Soon", "danger"
	}
	if cycles > batteryCycleWarn || (capacity > 0 && capacity < batteryCapWarn) {
		return "Fair", "warn"
	}
	return "Healthy", "ok"
}

// uptimeSeverity returns "ok", "warn", or "danger" based on uptime seconds.
func uptimeSeverity(secs uint64) string {
	if secs > uptimeDangerSecs {
		return "danger"
	}
	if secs > uptimeWarnSecs {
		return "warn"
	}
	return "ok"
}

func formatUptime(secs uint64) string {
	days := secs / 86400
	hours := (secs % 86400) / 3600
	mins := (secs % 3600) / 60
	if days > 0 {
		// Only show days and hours when uptime is over 1 day (skip minutes for brevity)
		return fmt.Sprintf("%dd %dh", days, hours)
	}
	if hours > 0 {
		return fmt.Sprintf("%dh %dm", hours, mins)
	}
	return fmt.Sprintf("%dm", mins)
}

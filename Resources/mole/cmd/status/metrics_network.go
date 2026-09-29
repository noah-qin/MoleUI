package main

import (
	"context"
	"fmt"
	"net/url"
	"os"
	"runtime"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/shirou/gopsutil/v4/net"
)

var ioCountersFunc = net.IOCounters

const (
	minNetworkSampleInterval = 100 * time.Millisecond
	networkIPCacheTTL        = 10 * time.Second
)

var noiseInterfacePrefixes = [...]string{"lo", "awdl", "utun", "llw", "bridge", "gif", "stf", "xhc", "anpi", "ap"}

func collectIOCountersSafely() (stats []net.IOCountersStat, err error) {
	defer func() {
		if r := recover(); r != nil {
			err = fmt.Errorf("panic collecting network counters: %v", r)
		}
	}()
	return ioCountersFunc(true)
}

func (c *Collector) primeNetworkCounters(now time.Time) {
	stats, err := collectIOCountersSafely()
	if err != nil {
		return
	}
	c.lastNetAt = now
	for _, s := range stats {
		c.prevNet[s.Name] = s
	}
}

func (c *Collector) collectNetwork(now time.Time) []NetworkStatus {
	if c.prevNet == nil {
		c.prevNet = make(map[string]net.IOCountersStat)
	}
	if c.rxHistoryBuf == nil {
		c.rxHistoryBuf = NewRingBuffer(NetworkHistorySize)
	}
	if c.txHistoryBuf == nil {
		c.txHistoryBuf = NewRingBuffer(NetworkHistorySize)
	}

	stats, err := collectIOCountersSafely()
	if err != nil {
		// Some restricted environments can break netstat-backed collectors.
		// Degrade gracefully to keep status output available.
		c.rxHistoryBuf.Add(0)
		c.txHistoryBuf.Add(0)
		return nil
	}

	// Map interface IPs.
	ifAddrs := c.getInterfaceIPsCached(now)

	if c.lastNetAt.IsZero() {
		c.lastNetAt = now
		for _, s := range stats {
			c.prevNet[s.Name] = s
		}
	}

	elapsed := now.Sub(c.lastNetAt).Seconds()
	if elapsed < minNetworkSampleInterval.Seconds() {
		elapsed = minNetworkSampleInterval.Seconds()
	}

	var result []NetworkStatus
	for _, cur := range stats {
		if isNoiseInterface(cur.Name) {
			continue
		}
		prev, ok := c.prevNet[cur.Name]
		if !ok {
			continue
		}
		rx := float64(counterDelta(cur.BytesRecv, prev.BytesRecv)) / 1024.0 / 1024.0 / elapsed
		tx := float64(counterDelta(cur.BytesSent, prev.BytesSent)) / 1024.0 / 1024.0 / elapsed
		result = append(result, NetworkStatus{
			Name:      cur.Name,
			RxRateMBs: rx,
			TxRateMBs: tx,
			IP:        ifAddrs[cur.Name],
		})
	}

	c.lastNetAt = now
	for _, s := range stats {
		c.prevNet[s.Name] = s
	}

	sort.Slice(result, func(i, j int) bool {
		return result[i].RxRateMBs+result[i].TxRateMBs > result[j].RxRateMBs+result[j].TxRateMBs
	})
	if len(result) > 3 {
		result = result[:3]
	}

	var totalRx, totalTx float64
	for _, r := range result {
		totalRx += r.RxRateMBs
		totalTx += r.TxRateMBs
	}

	// Update history using the global/aggregated stats
	c.rxHistoryBuf.Add(totalRx)
	c.txHistoryBuf.Add(totalTx)

	return result
}

func (c *Collector) getInterfaceIPsCached(now time.Time) map[string]string {
	if c.cachedNetIPs != nil && now.Sub(c.lastNetIPAt) < networkIPCacheTTL {
		return c.cachedNetIPs
	}
	c.cachedNetIPs = getInterfaceIPs()
	c.lastNetIPAt = now
	return c.cachedNetIPs
}

func getInterfaceIPs() map[string]string {
	result := make(map[string]string)
	ifaces, err := net.Interfaces()
	if err != nil {
		return result
	}
	for _, iface := range ifaces {
		for _, addr := range iface.Addrs {
			// IPv4 only.
			if strings.Contains(addr.Addr, ".") && !strings.HasPrefix(addr.Addr, "127.") {
				ip, _, _ := strings.Cut(addr.Addr, "/")
				result[iface.Name] = ip
				break
			}
		}
	}
	return result
}

func isNoiseInterface(name string) bool {
	lower := strings.ToLower(name)
	for _, prefix := range noiseInterfacePrefixes {
		if strings.HasPrefix(lower, prefix) {
			return true
		}
	}
	return false
}

func collectProxy() ProxyStatus {
	if proxy := collectProxyFromEnv(os.Getenv); proxy.Enabled {
		return proxy
	}

	// macOS: check system proxy via scutil.
	if runtime.GOOS == "darwin" {
		ctx, cancel := context.WithTimeout(context.Background(), 500*time.Millisecond)
		defer cancel()
		out, err := runCmd(ctx, "scutil", "--proxy")
		if err == nil {
			if proxy := collectProxyFromScutilOutput(out); proxy.Enabled {
				return proxy
			}
		}

		if proxy := collectProxyFromTunInterfaces(); proxy.Enabled {
			return proxy
		}
	}

	return ProxyStatus{Enabled: false}
}

func collectProxyFromEnv(getenv func(string) string) ProxyStatus {
	// Include ALL_PROXY for users running proxy tools that only export a single variable.
	envKeys := []string{
		"https_proxy", "HTTPS_PROXY",
		"http_proxy", "HTTP_PROXY",
		"all_proxy", "ALL_PROXY",
	}
	for _, key := range envKeys {
		val := strings.TrimSpace(getenv(key))
		if val == "" {
			continue
		}

		proxyType := "HTTP"
		lower := strings.ToLower(val)
		if strings.HasPrefix(lower, "socks") {
			proxyType = "SOCKS"
		}

		host := parseProxyHost(val)
		if host == "" {
			host = val
		}
		return ProxyStatus{Enabled: true, Type: proxyType, Host: host}
	}

	return ProxyStatus{Enabled: false}
}

func collectProxyFromScutilOutput(out string) ProxyStatus {
	if out == "" {
		return ProxyStatus{Enabled: false}
	}

	if scutilProxyEnabled(out, "SOCKSEnable") {
		host := joinHostPort(scutilProxyValue(out, "SOCKSProxy"), scutilProxyValue(out, "SOCKSPort"))
		if host == "" {
			host = "System Proxy"
		}
		return ProxyStatus{Enabled: true, Type: "SOCKS", Host: host}
	}

	if scutilProxyEnabled(out, "HTTPSEnable") {
		host := joinHostPort(scutilProxyValue(out, "HTTPSProxy"), scutilProxyValue(out, "HTTPSPort"))
		if host == "" {
			host = "System Proxy"
		}
		return ProxyStatus{Enabled: true, Type: "HTTPS", Host: host}
	}

	if scutilProxyEnabled(out, "HTTPEnable") {
		host := joinHostPort(scutilProxyValue(out, "HTTPProxy"), scutilProxyValue(out, "HTTPPort"))
		if host == "" {
			host = "System Proxy"
		}
		return ProxyStatus{Enabled: true, Type: "HTTP", Host: host}
	}

	if scutilProxyEnabled(out, "ProxyAutoConfigEnable") {
		pacURL := scutilProxyValue(out, "ProxyAutoConfigURLString")
		host := parseProxyHost(pacURL)
		if host == "" {
			host = "PAC"
		}
		return ProxyStatus{Enabled: true, Type: "PAC", Host: host}
	}

	if scutilProxyEnabled(out, "ProxyAutoDiscoveryEnable") {
		return ProxyStatus{Enabled: true, Type: "WPAD", Host: "Auto Discovery"}
	}

	return ProxyStatus{Enabled: false}
}

func collectProxyFromTunInterfaces() ProxyStatus {
	stats, err := collectIOCountersSafely()
	if err != nil {
		return ProxyStatus{Enabled: false}
	}

	var activeTun []string
	for _, s := range stats {
		lower := strings.ToLower(s.Name)
		if strings.HasPrefix(lower, "utun") || strings.HasPrefix(lower, "tun") {
			if s.BytesRecv+s.BytesSent > 0 {
				activeTun = append(activeTun, s.Name)
			}
		}
	}
	if len(activeTun) == 0 {
		return ProxyStatus{Enabled: false}
	}
	sort.Strings(activeTun)
	host := activeTun[0]
	if len(activeTun) > 1 {
		host = activeTun[0] + "+"
	}
	// Reported as a tunnel, never as a proxy. This branch is only reached when
	// no proxy is configured in the environment or in scutil, which is exactly
	// the case where an active `utun` is most likely iCloud Private Relay or a
	// VPN. Calling that "Proxy TUN" told users something false about a machine
	// that has no proxy at all.
	// Keep the existing JSON type value for automation consumers. IsTunnel is
	// the presentation hint that lets the terminal UI use an honest label.
	return ProxyStatus{Enabled: true, Type: "TUN", Host: host, IsTunnel: true}
}

func scutilProxyEnabled(out, key string) bool {
	return scutilProxyValue(out, key) == "1"
}

func scutilProxyValue(out, key string) string {
	prefix := key + " :"
	for line := range strings.Lines(out) {
		line = strings.TrimSpace(line)
		if after, ok := strings.CutPrefix(line, prefix); ok {
			return strings.TrimSpace(after)
		}
	}
	return ""
}

func parseProxyHost(raw string) string {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return ""
	}

	target := raw
	if !strings.Contains(target, "://") {
		target = "http://" + target
	}
	parsed, err := url.Parse(target)
	if err != nil {
		return ""
	}
	host := parsed.Host
	if host == "" {
		return ""
	}
	return strings.TrimPrefix(host, "@")
}

func joinHostPort(host, port string) string {
	host = strings.TrimSpace(host)
	port = strings.TrimSpace(port)
	if host == "" {
		return ""
	}
	if port == "" {
		return host
	}
	if _, err := strconv.Atoi(port); err != nil {
		return host
	}
	return host + ":" + port
}

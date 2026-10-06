package main

import (
	"context"
	"encoding/json"
	"errors"
	"strings"
	"testing"
	"time"

	gopsutilnet "github.com/shirou/gopsutil/v4/net"
)

func TestCollectProxyFromEnvSupportsAllProxy(t *testing.T) {
	env := map[string]string{
		"ALL_PROXY": "socks5://127.0.0.1:7890",
	}
	getenv := func(key string) string {
		return env[key]
	}

	got := collectProxyFromEnv(getenv)
	if !got.Enabled {
		t.Fatalf("expected proxy enabled")
	}
	if got.Type != "SOCKS" {
		t.Fatalf("expected SOCKS type, got %s", got.Type)
	}
	if got.Host != "127.0.0.1:7890" {
		t.Fatalf("unexpected host: %s", got.Host)
	}
}

func TestCollectProxyFromScutilOutputPAC(t *testing.T) {
	out := `
<dictionary> {
  ProxyAutoConfigEnable : 1
  ProxyAutoConfigURLString : http://127.0.0.1:6152/proxy.pac
}`
	got := collectProxyFromScutilOutput(out)
	if !got.Enabled {
		t.Fatalf("expected proxy enabled")
	}
	if got.Type != "PAC" {
		t.Fatalf("expected PAC type, got %s", got.Type)
	}
	if got.Host != "127.0.0.1:6152" {
		t.Fatalf("unexpected host: %s", got.Host)
	}
}

func TestCollectProxyFromScutilOutputHTTPHostPort(t *testing.T) {
	out := `
<dictionary> {
  HTTPEnable : 1
  HTTPProxy : 127.0.0.1
  HTTPPort : 7890
}`
	got := collectProxyFromScutilOutput(out)
	if !got.Enabled {
		t.Fatalf("expected proxy enabled")
	}
	if got.Type != "HTTP" {
		t.Fatalf("expected HTTP type, got %s", got.Type)
	}
	if got.Host != "127.0.0.1:7890" {
		t.Fatalf("unexpected host: %s", got.Host)
	}
}

func TestCollectIOCountersSafelyRecoversPanic(t *testing.T) {
	original := ioCountersFunc
	ioCountersFunc = func(bool) ([]gopsutilnet.IOCountersStat, error) {
		panic("boom")
	}
	t.Cleanup(func() { ioCountersFunc = original })

	stats, err := collectIOCountersSafely()
	if err == nil {
		t.Fatalf("expected error from panic recovery")
	}
	if !strings.Contains(err.Error(), "panic collecting network counters") {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(stats) != 0 {
		t.Fatalf("expected empty stats when panic recovered")
	}
}

func TestCollectIOCountersSafelyReturnsData(t *testing.T) {
	original := ioCountersFunc
	want := []gopsutilnet.IOCountersStat{
		{Name: "en0", BytesRecv: 1, BytesSent: 2},
	}
	ioCountersFunc = func(bool) ([]gopsutilnet.IOCountersStat, error) {
		return want, nil
	}
	t.Cleanup(func() { ioCountersFunc = original })

	got, err := collectIOCountersSafely()
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(got) != 1 || got[0].Name != "en0" {
		t.Fatalf("unexpected stats: %+v", got)
	}
}

func TestCollectNetworkFirstSampleReturnsZeroRateInterfaces(t *testing.T) {
	original := ioCountersFunc
	ioCountersFunc = func(bool) ([]gopsutilnet.IOCountersStat, error) {
		return []gopsutilnet.IOCountersStat{
			{Name: "en0", BytesRecv: 1000, BytesSent: 2000},
		}, nil
	}
	t.Cleanup(func() { ioCountersFunc = original })

	c := &Collector{}
	got := c.collectNetwork(time.Now())
	if len(got) != 1 {
		t.Fatalf("expected first sample to render one interface, got %+v", got)
	}
	if got[0].RxRateMBs != 0 || got[0].TxRateMBs != 0 {
		t.Fatalf("expected first sample zero rates, got %+v", got[0])
	}
	if len(c.rxHistoryBuf.Slice()) != 1 || len(c.txHistoryBuf.Slice()) != 1 {
		t.Fatalf("expected history to be seeded on first sample")
	}
}

func TestCollectNetworkUsesPrimedCountersForInitialRates(t *testing.T) {
	original := ioCountersFunc
	calls := 0
	samples := [][]gopsutilnet.IOCountersStat{
		{{Name: "en0", BytesRecv: 1024 * 1024, BytesSent: 0}},
		{{Name: "en0", BytesRecv: 2 * 1024 * 1024, BytesSent: 512 * 1024}},
	}
	ioCountersFunc = func(bool) ([]gopsutilnet.IOCountersStat, error) {
		if calls >= len(samples) {
			return samples[len(samples)-1], nil
		}
		got := samples[calls]
		calls++
		return got, nil
	}
	t.Cleanup(func() { ioCountersFunc = original })

	c := NewCollector(ProcessWatchOptions{})
	got := c.collectNetwork(c.lastNetAt.Add(time.Second))
	if len(got) != 1 {
		t.Fatalf("expected one interface, got %+v", got)
	}
	if got[0].RxRateMBs != 1.0 {
		t.Fatalf("expected 1 MB/s down, got %v", got[0].RxRateMBs)
	}
	if got[0].TxRateMBs != 0.5 {
		t.Fatalf("expected 0.5 MB/s up, got %v", got[0].TxRateMBs)
	}
}

func TestCollectNetworkClampsCounterReset(t *testing.T) {
	original := ioCountersFunc
	ioCountersFunc = func(bool) ([]gopsutilnet.IOCountersStat, error) {
		return []gopsutilnet.IOCountersStat{
			{Name: "en0", BytesRecv: 10, BytesSent: 20},
		}, nil
	}
	t.Cleanup(func() { ioCountersFunc = original })

	base := time.Now()
	c := &Collector{
		prevNet: map[string]gopsutilnet.IOCountersStat{
			"en0": {Name: "en0", BytesRecv: 1024 * 1024, BytesSent: 1024 * 1024},
		},
		lastNetAt:    base,
		rxHistoryBuf: NewRingBuffer(NetworkHistorySize),
		txHistoryBuf: NewRingBuffer(NetworkHistorySize),
	}

	got := c.collectNetwork(base.Add(time.Second))
	if len(got) != 1 {
		t.Fatalf("expected one interface, got %+v", got)
	}
	if got[0].RxRateMBs != 0 || got[0].TxRateMBs != 0 {
		t.Fatalf("expected reset counters to clamp to zero, got %+v", got[0])
	}
}

func TestTunnelInterfaceIsNotReportedAsAProxy(t *testing.T) {
	// A machine with no configured proxy but an active utun (iCloud Private
	// Relay, a corporate VPN, or a TUN-mode client) must not be told it has a
	// proxy. The reading is still surfaced, just honestly labelled.
	original := ioCountersFunc
	ioCountersFunc = func(bool) ([]gopsutilnet.IOCountersStat, error) {
		return []gopsutilnet.IOCountersStat{
			{Name: "en0", BytesRecv: 100},
			{Name: "utun4", BytesRecv: 20, BytesSent: 30},
		}, nil
	}
	t.Cleanup(func() { ioCountersFunc = original })

	got := collectProxyFromTunInterfaces()
	if !got.Enabled || !got.IsTunnel || got.Type != "TUN" || got.Host != "utun4" {
		t.Fatalf("unexpected tunnel status: %+v", got)
	}
	card := renderNetworkCard(
		[]NetworkStatus{{Name: "en0", IP: "192.0.2.10"}},
		NetworkHistory{}, got, 40,
	)
	rendered := strings.Join(card.lines, "\n")
	if !strings.Contains(rendered, "Tunnel") || strings.Contains(rendered, "Proxy Tunnel") {
		t.Fatalf("tunnel must be rendered without a proxy claim: %q", rendered)
	}
}

func TestTunnelHintDoesNotExpandProxyJSONContract(t *testing.T) {
	encoded, err := json.Marshal(ProxyStatus{
		Enabled:  true,
		Type:     "TUN",
		Host:     "utun4",
		IsTunnel: true,
	})
	if err != nil {
		t.Fatalf("json.Marshal() error = %v", err)
	}
	const want = `{"enabled":true,"type":"TUN","host":"utun4"}`
	if string(encoded) != want {
		t.Fatalf("proxy JSON contract changed: got %s, want %s", encoded, want)
	}
}

func TestCollectNetworkDefaultTunnel(t *testing.T) {
	originalIO, originalRun := ioCountersFunc, runCmd
	t.Cleanup(func() { ioCountersFunc, runCmd = originalIO, originalRun })
	const mb = 1024 * 1024
	now := time.Now()
	route := "utun4"
	routeErr := false
	runCmd = func(ctx context.Context, name string, args ...string) (string, error) {
		if name != "route" || strings.Join(args, " ") != "-n get default" {
			t.Fatalf("unexpected probe %s %v", name, args)
		}
		if _, ok := ctx.Deadline(); !ok {
			t.Fatal("route probe has no deadline")
		}
		if routeErr {
			return "", errors.New("no default route")
		}
		return "   route to: default\n  interface: " + route + "\n      flags: <UP,GATEWAY>\n", nil
	}
	names := []string{"en0", "en4", "en6", "utun4", "ppp0", "ipsec0", "utun9"}
	counters := make([]gopsutilnet.IOCountersStat, len(names))
	for i, name := range names {
		counters[i] = gopsutilnet.IOCountersStat{Name: name, BytesRecv: 100 * mb, BytesSent: 100 * mb}
	}
	ioCountersFunc = func(bool) ([]gopsutilnet.IOCountersStat, error) {
		return append([]gopsutilnet.IOCountersStat(nil), counters...), nil
	}
	c := &Collector{prevNet: make(map[string]gopsutilnet.IOCountersStat), cachedNetIPs: map[string]string{"en0": "192.0.2.1"}, lastNetIPAt: now}
	c.primeNetworkCounters(now)
	for _, step := range []struct {
		route  string
		fail   bool
		wantRx float64
	}{
		{"utun4", false, 2}, {"ppp0", false, 3}, {"ipsec0", false, 4}, {"en0", false, 30}, {"utun4", true, 30},
	} {
		route, routeErr = step.route, step.fail
		for i := range counters {
			rate := uint64(10)
			if i >= 3 {
				rate = uint64(i - 1)
			}
			counters[i].BytesRecv += rate * mb
			counters[i].BytesSent += mb
		}
		now = now.Add(time.Second)
		got := c.collectNetworkFull(now)
		wantTunnel := route != "en0" && !routeErr
		found := false
		for _, n := range got {
			if !strings.HasPrefix(n.Name, "en") {
				if !wantTunnel || n.Name != route {
					t.Fatalf("unexpected idle/non-default tunnel: %+v", got)
				}
				found = true
			}
		}
		if found != wantTunnel {
			t.Fatalf("default route %s missing from counters: %+v", route, got)
		}
		rx := c.rxHistoryBuf.Slice()
		if rx[len(rx)-1] != step.wantRx {
			t.Fatalf("route %s: history = %v, want %v", route, rx, step.wantRx)
		}
		card := renderNetworkCard(got, NetworkHistory{}, ProxyStatus{}, 40)
		if !strings.Contains(card.lines[0], formatRate(step.wantRx)) {
			t.Fatalf("card and history disagree: %v", card.lines)
		}
		encoded, err := json.Marshal(got)
		if err != nil {
			t.Fatal(err)
		}
		var rows []map[string]any
		if err := json.Unmarshal(encoded, &rows); err != nil {
			t.Fatal(err)
		}
		for _, row := range rows {
			if len(row) != 4 {
				t.Fatalf("network JSON shape changed: %s", encoded)
			}
		}
	}
}

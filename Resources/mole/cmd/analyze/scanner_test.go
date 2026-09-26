//go:build darwin

package main

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"testing"
)

func writeFileWithSize(t testing.TB, path string, size int) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatalf("mkdir %s: %v", path, err)
	}
	content := make([]byte, size)
	if err := os.WriteFile(path, content, 0o644); err != nil {
		t.Fatalf("write %s: %v", path, err)
	}
}

func TestGetDirectoryLogicalSizeWithExclude(t *testing.T) {
	base := t.TempDir()
	homeFile := filepath.Join(base, "fileA")
	libFile := filepath.Join(base, "Library", "fileB")
	projectLibFile := filepath.Join(base, "Projects", "Library", "fileC")

	writeFileWithSize(t, homeFile, 100)
	writeFileWithSize(t, libFile, 200)
	writeFileWithSize(t, projectLibFile, 300)

	total, err := getDirectoryLogicalSizeWithExclude(base, "")
	if err != nil {
		t.Fatalf("getDirectoryLogicalSizeWithExclude (no exclude) error: %v", err)
	}
	if total != 600 {
		t.Fatalf("expected total 600 bytes, got %d", total)
	}

	excluding, err := getDirectoryLogicalSizeWithExclude(base, filepath.Join(base, "Library"))
	if err != nil {
		t.Fatalf("getDirectoryLogicalSizeWithExclude (exclude Library) error: %v", err)
	}
	if excluding != 400 {
		t.Fatalf("expected 400 bytes when excluding top-level Library, got %d", excluding)
	}
}

func TestGetDirectorySizeFromDuSkippingImmediateChildDoesNotMeasureExcludedPath(t *testing.T) {
	base := t.TempDir()
	excluded := filepath.Join(base, "Library")
	included := filepath.Join(base, "Documents")
	if err := os.MkdirAll(excluded, 0o755); err != nil {
		t.Fatalf("mkdir excluded: %v", err)
	}
	if err := os.MkdirAll(included, 0o755); err != nil {
		t.Fatalf("mkdir included: %v", err)
	}

	var measured []string
	size, err := getDirectorySizeFromDuSkippingImmediateChild(base, excluded, func(path string) (int64, error) {
		measured = append(measured, path)
		return 100, nil
	})
	if err != nil {
		t.Fatalf("getDirectorySizeFromDuSkippingImmediateChild: %v", err)
	}
	if size < 100 {
		t.Fatalf("expected included directory size in total, got %d", size)
	}
	if len(measured) != 1 || measured[0] != included {
		t.Fatalf("expected to measure only %s, measured %#v", included, measured)
	}
}

func TestGetDirectorySizeFromDuWithIgnoresSkipsCloudPlaceholderTree(t *testing.T) {
	base := t.TempDir()
	writeFileWithSize(t, filepath.Join(base, "Application Support", "state.dat"), 4096)
	writeFileWithSize(t, filepath.Join(base, "Mobile Documents", "cloud.dat"), 1024*1024)

	withoutIgnore, err := getDirectorySizeFromDuWithExcludeAndIgnores(context.Background(), base, "", nil)
	if err != nil {
		t.Fatalf("getDirectorySizeFromDuWithExcludeAndIgnores without ignore: %v", err)
	}
	withIgnore, err := getDirectorySizeFromDuWithExcludeAndIgnores(context.Background(), base, "", []string{"Mobile Documents"})
	if err != nil {
		t.Fatalf("getDirectorySizeFromDuWithExcludeAndIgnores with ignore: %v", err)
	}
	if withIgnore >= withoutIgnore {
		t.Fatalf("expected ignored Mobile Documents to reduce size, got ignored=%d without=%d", withIgnore, withoutIgnore)
	}
	if withIgnore <= 0 {
		t.Fatalf("expected non-zero size for included files, got %d", withIgnore)
	}
}

func TestValidateDuIgnoreNameRejectsPathPatterns(t *testing.T) {
	for _, name := range []string{"", "../Library", "Library/Developer", "bad\x00name"} {
		if err := validateDuIgnoreName(name); err == nil {
			t.Fatalf("expected %q to be rejected", name)
		}
	}
	if err := validateDuIgnoreName("Mobile Documents"); err != nil {
		t.Fatalf("expected basename ignore to be accepted: %v", err)
	}
}

func BenchmarkGetDirectorySizeFromDuWithExcludeHomeLibrary(b *testing.B) {
	base := b.TempDir()
	libraryDir := filepath.Join(base, "Library")
	for dirIdx := range 250 {
		for fileIdx := range 20 {
			writeFileWithSize(
				b,
				filepath.Join(libraryDir, "bulk", fmt.Sprintf("dir-%03d", dirIdx), "bucket", fmt.Sprintf("file-%03d.dat", fileIdx)),
				16,
			)
		}
	}
	writeFileWithSize(b, filepath.Join(base, "Documents", "keep.dat"), 4096)

	excludePath := filepath.Join(base, "Library")
	b.ReportAllocs()
	b.ResetTimer()

	for b.Loop() {
		size, err := getDirectorySizeFromDuWithExclude(context.Background(), base, excludePath)
		if err != nil {
			b.Fatalf("getDirectorySizeFromDuWithExclude: %v", err)
		}
		if size <= 0 {
			b.Fatalf("expected non-zero size, got %d", size)
		}
	}
}

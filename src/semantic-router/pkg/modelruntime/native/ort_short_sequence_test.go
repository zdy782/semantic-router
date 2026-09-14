package native

import (
	"context"
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"

	ort "github.com/vllm-project/semantic-router/onnx-binding/instance"
	"github.com/vllm-project/semantic-router/src/semantic-router/pkg/config"
)

func TestORTShortSequenceIdentityAndOperatingPointRejection(t *testing.T) {
	artifact := t.TempDir()
	if err := os.WriteFile(filepath.Join(artifact, "model.onnx"), []byte("identity fixture"), 0o600); err != nil {
		t.Fatal(err)
	}
	spec := config.ResolvedModelBinding{Binding: config.ModelBinding{Adapter: "modernbert"}, Deployment: config.ModelDeployment{Artifact: artifact, Provider: "ort", Device: "migraphx:0", Input: config.ModelInputBudget{MaxTokens: 8192}}}
	runtime := New(nil)
	loads := 0
	for _, short := range []int{0, 512, 512, 1024} {
		spec.Deployment.ShortSequenceTokens = short
		resource, err := runtime.ortResource(context.Background(), spec, "sequence", func(options ort.Options) (io.Closer, error) {
			loads++
			if options.ShortSequenceTokens != short || options.MaxInputTokens != 8192 || options.AllowCPUFallback {
				t.Fatalf("changed logical/provider contract: %+v", options)
			}
			return io.NopCloser(strings.NewReader("")), nil
		})
		if err != nil {
			t.Fatal(err)
		}
		t.Cleanup(func() { _ = resource.Close() })
	}
	if loads != 3 {
		t.Fatalf("short session must separate resource identity; got %d loads", loads)
	}
	// Reject before reading even a missing policy or loading a native library.
	spec.Binding.OperatingPoint = &config.OperatingPointReference{Path: "missing.json"}
	if _, err := runtime.OperatingPoint(context.Background(), spec, nil); err == nil || !strings.Contains(err.Error(), "short_sequence_tokens") {
		t.Fatalf("got %v", err)
	}
}

func TestORTShortSequenceCapabilityRequiresBothExactShapes(t *testing.T) {
	deployment := config.ModelDeployment{ShortSequenceTokens: 512}
	info := ort.Info{Task: "sequence_classification", EffectiveLimit: 8192}
	for _, length := range []int64{512, 8192} {
		info.Sessions = append(info.Sessions, ort.SessionEvidence{Graph: "model.onnx", RuntimeBuild: "runtime", Artifacts: []ort.ArtifactDigest{{Role: "graph", SHA256: "identity"}}, ExecutionInputs: []ort.ExecutionInput{
			{Name: "input_ids", Dtype: "int64", Shape: []int64{1, length}},
			{Name: "attention_mask", Dtype: "int64", Shape: []int64{1, length}},
		}})
	}
	if err := validateORTShortSessions(deployment, info); err != nil {
		t.Fatal(err)
	}
	for name, change := range map[string]func(*ort.Info){
		"missing bucket":  func(i *ort.Info) { i.Sessions = i.Sessions[:1] },
		"wrong length":    func(i *ort.Info) { i.EffectiveLimit = 4096 },
		"wrong task":      func(i *ort.Info) { i.Task = "embedding" },
		"changed graph":   func(i *ort.Info) { i.Sessions[1].Graph = "other.onnx" },
		"changed runtime": func(i *ort.Info) { i.Sessions[1].RuntimeBuild = "other-runtime" },
		"missing mask":    func(i *ort.Info) { i.Sessions[1].ExecutionInputs = i.Sessions[1].ExecutionInputs[:1] },
	} {
		t.Run(name, func(t *testing.T) {
			bad := info
			bad.Sessions = append([]ort.SessionEvidence(nil), info.Sessions...)
			change(&bad)
			if validateORTShortSessions(deployment, bad) == nil {
				t.Fatal("incorrect evidence accepted")
			}
		})
	}
}

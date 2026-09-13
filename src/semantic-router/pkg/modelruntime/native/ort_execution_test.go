package native

import (
	"strings"
	"testing"

	ort "github.com/vllm-project/semantic-router/onnx-binding/instance"
	"github.com/vllm-project/semantic-router/src/semantic-router/pkg/config"
)

func TestORTROCmOptionsAndObservedExecutionMustAgree(t *testing.T) {
	spec := config.ResolvedModelBinding{Binding: config.ModelBinding{Contract: config.RemoteClassifierContractLabelScores, Head: "onnx/model_fa_fp16.onnx"}, Deployment: config.ModelDeployment{Provider: "ort", Artifact: "model", Device: "rocm:3", Precision: "native", CustomOpsProfile: "ck_flash_attention", Input: config.ModelInputBudget{MaxTokens: 32768}}}
	options, err := ortOptions(spec)
	if err != nil {
		t.Fatal(err)
	}
	if options.Provider != "rocm" || options.DeviceID != 3 || options.AllowCPUFallback || options.CustomOpsProfile != "ck_flash_attention" || options.MaxInputTokens != 32768 {
		t.Fatalf("wrong options: %+v", options)
	}
	session := ort.SessionEvidence{Provider: "ROCMExecutionProvider", DeviceID: 3, Precision: "native", CPUFallbackDisabled: true, CustomOpsProfile: "ck_flash_attention", CustomOpsLibrary: "/usr/local/lib/libort_ck_flash_attn.so.1", CustomOpsSHA256: strings.Repeat("ab", 32)}
	info := ort.Info{ModelLimit: 32768, TaskLimit: 32768, Labels: []string{"a", "b"}, Sessions: []ort.SessionEvidence{session}}
	if _, err := ortCapability(spec, info); err != nil {
		t.Fatal(err)
	}
	for name, change := range map[string]func(*ort.SessionEvidence){
		"fallback":  func(s *ort.SessionEvidence) { s.CPUFallbackDisabled = false },
		"device":    func(s *ort.SessionEvidence) { s.DeviceID = 0 },
		"precision": func(s *ort.SessionEvidence) { s.Precision = "fp16" },
		"profile":   func(s *ort.SessionEvidence) { s.CustomOpsProfile = "none" },
		"library":   func(s *ort.SessionEvidence) { s.CustomOpsLibrary = "/tmp/untrusted.so" },
		"hash":      func(s *ort.SessionEvidence) { s.CustomOpsSHA256 = "unknown" },
	} {
		t.Run(name, func(t *testing.T) {
			bad := session
			change(&bad)
			info.Sessions = []ort.SessionEvidence{bad}
			if _, err := ortCapability(spec, info); err == nil {
				t.Fatal("accepted execution without matching evidence")
			}
		})
	}
	for _, device := range []string{"rocm:-1", "rocm:bad", "cpu"} {
		bad := spec
		bad.Deployment.Device = device
		if _, err := ortOptions(bad); err == nil {
			t.Fatalf("accepted invalid CK device %q", device)
		}
	}
	spec.Deployment.Precision = "fp16"
	if _, err := ortOptions(spec); err == nil {
		t.Fatal("silently enabled ROCm graph conversion")
	}
}

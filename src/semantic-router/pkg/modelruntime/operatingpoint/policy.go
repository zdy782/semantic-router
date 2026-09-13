// Package operatingpoint validates frozen independent-score interpretation.
// It owns no model resources and performs no tokenization or inference.
package operatingpoint

import (
	"bytes"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"math"
	"reflect"
	"slices"
	"strings"

	"github.com/vllm-project/semantic-router/src/semantic-router/pkg/modelruntime/binding"
	"github.com/vllm-project/semantic-router/src/semantic-router/pkg/modelruntime/tasks"
)

// Definition is the versioned runtime sidecar. Exporters write identities of the
// final inference files; training receipts and evaluation outcomes do not belong here.
type Definition struct {
	Version            int         `json:"version"`
	ModelWeightsSHA256 string      `json:"model_weights_sha256"`
	ModelConfigSHA256  string      `json:"model_config_sha256"`
	TokenizerSHA256    string      `json:"tokenizer_sha256"`
	ScoreType          string      `json:"score_type"`
	Labels             []string    `json:"labels"`
	Thresholds         []float32   `json:"thresholds"`
	Comparison         string      `json:"comparison"`
	Input              InputPolicy `json:"input_policy"`
	Executions         []Execution `json:"executions"`
}

type Execution struct {
	Provider    string `json:"provider"`
	Precision   string `json:"precision"`
	WeightsFile string `json:"weights_file"`
}

type InputPolicy struct {
	Strategy                 string   `json:"strategy"`
	WindowTokens             int      `json:"window_tokens_including_special_tokens"`
	ContentTokens            int      `json:"content_tokens_per_window"`
	Stride                   int      `json:"stride_content_tokens"`
	Overlap                  int      `json:"overlap_content_tokens"`
	MaxDocumentTokens        int      `json:"max_document_tokens_including_special_tokens"`
	Aggregation              string   `json:"aggregation"`
	Positions                string   `json:"positions"`
	PaddingSide              string   `json:"padding_side"`
	PadTokenID               *uint32  `json:"pad_token_id"`
	PaddingAttentionMask     *int     `json:"padding_attention_mask"`
	SpecialPrefixIDs         []uint32 `json:"special_prefix_ids"`
	SpecialSuffixIDs         []uint32 `json:"special_suffix_ids"`
	ReferenceWindowBatchSize int      `json:"reference_window_batch_size"`
	BatchOrder               string   `json:"batch_order"`
	Tokenization             string   `json:"tokenization"`
	Overflow                 string   `json:"overflow"`
}

// Policy is immutable after decoding. Accessors return copies of mutable data.
type Policy struct {
	definition Definition
	digest     string
}

func Decode(data []byte, digest string) (*Policy, error) {
	if err := rejectDuplicateKeys(json.NewDecoder(bytes.NewReader(data))); err != nil {
		return nil, err
	}
	var version struct {
		Version int `json:"version"`
	}
	if err := json.Unmarshal(data, &version); err != nil {
		return nil, fmt.Errorf("decode operating point: %w", err)
	}
	if version.Version != 2 {
		return nil, fmt.Errorf("operating point version %d is unsupported; version 2 requires config, tokenizer and execution identities", version.Version)
	}
	if err := requireExactFields(data, reflect.TypeOf(Definition{})); err != nil {
		return nil, err
	}
	decoder := json.NewDecoder(bytes.NewReader(data))
	decoder.DisallowUnknownFields()
	var d Definition
	if err := decoder.Decode(&d); err != nil {
		return nil, fmt.Errorf("decode operating point: %w", err)
	}
	if err := decoder.Decode(new(any)); err != io.EOF {
		return nil, fmt.Errorf("operating point must contain one JSON object")
	}
	for _, hash := range []string{digest, d.ModelWeightsSHA256, d.ModelConfigSHA256, d.TokenizerSHA256} {
		if !validSHA256(hash) {
			return nil, fmt.Errorf("operating point requires complete lowercase SHA256 identities")
		}
	}
	if d.ScoreType != "independent_sigmoid" || d.Comparison != "score >= threshold" {
		return nil, fmt.Errorf("unsupported operating point score semantics")
	}
	if len(d.Labels) < 2 || len(d.Labels) != len(d.Thresholds) {
		return nil, fmt.Errorf("operating point requires one threshold per label")
	}
	seen := map[string]bool{}
	for i, label := range d.Labels {
		if label == "" || strings.TrimSpace(label) != label || seen[label] {
			return nil, fmt.Errorf("operating point labels must be nonempty and unique")
		}
		seen[label] = true
		value := d.Thresholds[i]
		if math.IsNaN(float64(value)) || math.IsInf(float64(value), 0) || value < 0 || value > 1 {
			return nil, fmt.Errorf("operating point threshold is outside [0,1]")
		}
	}
	if len(d.Executions) != 1 || d.Executions[0] != (Execution{Provider: "candle", Precision: "float32", WeightsFile: "model.safetensors"}) {
		return nil, fmt.Errorf("operating point currently supports only an explicitly declared Candle float32 model.safetensors execution; ORT needs a qualified graph contract")
	}
	w := d.Input
	if w.Strategy != "overlapping_content_windows" || w.Aggregation != "per-label maximum sigmoid over all covering windows" || w.Positions != "reset for each window" || w.Overflow != "reject" || w.PaddingSide != "right" || w.PadTokenID == nil || w.PaddingAttentionMask == nil || *w.PaddingAttentionMask != 0 {
		return nil, fmt.Errorf("unsupported operating point window semantics")
	}
	if w.ContentTokens <= 0 || w.WindowTokens != w.ContentTokens+len(w.SpecialPrefixIDs)+len(w.SpecialSuffixIDs) || w.Overlap < 0 || w.Overlap >= w.ContentTokens || w.Stride != w.ContentTokens-w.Overlap || w.MaxDocumentTokens < w.WindowTokens || w.ReferenceWindowBatchSize < 1 {
		return nil, fmt.Errorf("inconsistent operating point window geometry")
	}
	if w.BatchOrder != "ascending actual window token count, stable original order on ties" || w.Tokenization != "Tokenize once without truncation; slice original content token IDs and restore the tokenizer special-token envelope for each window." {
		return nil, fmt.Errorf("unsupported reference window preparation")
	}
	return &Policy{definition: d, digest: digest}, nil
}

// All v2 fields are required, including zero overlap and empty special-token
// envelopes. Use the schema's struct tags: encoding/json alone accepts omitted
// fields and case-folded aliases, which other consumers may interpret differently.
func requireExactFields(data []byte, shape reflect.Type) error {
	if shape.Kind() == reflect.Slice && shape.Elem().Kind() == reflect.Struct {
		var entries []json.RawMessage
		if err := json.Unmarshal(data, &entries); err != nil {
			return err
		}
		for _, entry := range entries {
			if err := requireExactFields(entry, shape.Elem()); err != nil {
				return err
			}
		}
		return nil
	}
	if shape.Kind() != reflect.Struct {
		return nil
	}
	var fields map[string]json.RawMessage
	if err := json.Unmarshal(data, &fields); err != nil {
		return err
	}
	for i := 0; i < shape.NumField(); i++ {
		field := shape.Field(i)
		key := field.Tag.Get("json")
		raw, exists := fields[key]
		if !exists {
			return fmt.Errorf("operating point requires field %q", key)
		}
		if err := requireExactFields(raw, field.Type); err != nil {
			return err
		}
		delete(fields, key)
	}
	if len(fields) != 0 {
		return fmt.Errorf("operating point contains unknown or noncanonical field names")
	}
	return nil
}

func validSHA256(value string) bool {
	decoded, err := hex.DecodeString(value)
	return err == nil && len(decoded) == 32 && strings.ToLower(value) == value
}
func (p *Policy) Digest() string        { return p.digest }
func (p *Policy) Labels() []string      { return slices.Clone(p.definition.Labels) }
func (p *Policy) Thresholds() []float32 { return slices.Clone(p.definition.Thresholds) }
func (p *Policy) Window() tasks.TextWindowsRequest {
	w := p.definition.Input
	return tasks.TextWindowsRequest{Size: w.WindowTokens, Overlap: w.Overlap}
}
func (p *Policy) MaxTokens() int { return p.definition.Input.MaxDocumentTokens }

func (p *Policy) ValidateCapability(c binding.Capability) error {
	if c.Contract != "label_scores.v1" || c.Provider != "candle" || c.Precision != "float32" || !slices.Equal(c.Labels, p.definition.Labels) || c.Limits.EffectiveTokens() != p.MaxTokens() || c.Limits.Overflow != "window" {
		return fmt.Errorf("%w: actual owned head/execution differs from operating point", binding.ErrCapability)
	}
	return nil
}

// Reduce preserves independent scores and requires the exact declared covering
// windows, including an odd tail. A partial scan can never become a safe result.
func (p *Policy) Reduce(result tasks.WindowedLabelScores) ([]float32, error) {
	w := p.definition.Input
	spans := make([][2]int, len(result.Windows))
	scores := make([]float32, len(p.definition.Labels))
	for i, window := range result.Windows {
		start := i * w.Stride
		empty := i == 0 && result.ContentTokens == 0
		if (start >= result.ContentTokens && !empty) || window.Start != start || window.End != min(start+w.ContentTokens, result.ContentTokens) || len(window.Scores) != len(scores) {
			return nil, fmt.Errorf("%w: windows differ from frozen geometry", binding.ErrInvalidResult)
		}
		if err := tasks.ValidateLabelScores(window.Scores); err != nil {
			return nil, fmt.Errorf("%w: %w", binding.ErrInvalidResult, err)
		}
		spans[i] = [2]int{window.Start, window.End}
		for j, value := range window.Scores {
			scores[j] = max(scores[j], value)
		}
	}
	if err := tasks.ValidateWindowCoverage(result.ContentTokens, spans, result.Input); err != nil {
		return nil, fmt.Errorf("%w: %w", binding.ErrInvalidResult, err)
	}
	if result.Input.OriginalTokens != result.ContentTokens+len(w.SpecialPrefixIDs)+len(w.SpecialSuffixIDs) || result.Input.OriginalTokens > w.MaxDocumentTokens {
		return nil, fmt.Errorf("%w: document input budget or special-token envelope differs", binding.ErrInvalidResult)
	}
	return scores, nil
}

// encoding/json accepts duplicate keys by default. Policy identities must have
// one unambiguous interpretation across exporter and runtime implementations.
func rejectDuplicateKeys(decoder *json.Decoder) error {
	token, err := decoder.Token()
	if err != nil {
		return err
	}
	if token == nil {
		return fmt.Errorf("operating point fields cannot be null")
	}
	delim, ok := token.(json.Delim)
	if !ok {
		return nil
	}
	switch delim {
	case '{':
		seen := map[string]bool{}
		for decoder.More() {
			key, keyErr := decoder.Token()
			if keyErr != nil {
				return keyErr
			}
			name, ok := key.(string)
			if !ok || seen[name] {
				return fmt.Errorf("duplicate or invalid operating point key %q", name)
			}
			seen[name] = true
			if parseErr := rejectDuplicateKeys(decoder); parseErr != nil {
				return parseErr
			}
		}
	case '[':
		for decoder.More() {
			if parseErr := rejectDuplicateKeys(decoder); parseErr != nil {
				return parseErr
			}
		}
	default:
		return fmt.Errorf("unexpected JSON delimiter")
	}
	_, err = decoder.Token()
	return err
}

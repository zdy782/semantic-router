package native

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"path/filepath"
	"unicode/utf8"

	candle "github.com/vllm-project/semantic-router/candle-binding"
	ort "github.com/vllm-project/semantic-router/onnx-binding/instance"
	"github.com/vllm-project/semantic-router/src/semantic-router/pkg/config"
	"github.com/vllm-project/semantic-router/src/semantic-router/pkg/modelruntime/binding"
	"github.com/vllm-project/semantic-router/src/semantic-router/pkg/modelruntime/tasks"
)

// RelevanceScorer owns a recipe's reference to a fixed native exit. Native
// resources share the existing pool; a request cannot select another head.
type RelevanceScorer struct {
	task      *binding.Resolved[[]tasks.QueryDocument, tasks.RelevanceScores]
	selection config.PairScorerSelection
	identity  string
}

func (s *RelevanceScorer) Close() error                          { return s.task.Close() }
func (s *RelevanceScorer) CacheIdentity() string                 { return s.identity }
func (s *RelevanceScorer) Selection() config.PairScorerSelection { return s.selection }
func (s *RelevanceScorer) ScorePairs(ctx context.Context, recipe string, pairs []tasks.QueryDocument) (tasks.RelevanceScores, error) {
	return s.task.Call(ctx, recipe, pairs)
}

func (r *Runtime) relevanceTask() (*binding.Task[[]tasks.QueryDocument, tasks.RelevanceScores], error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	if task, err := binding.Lookup[[]tasks.QueryDocument, tasks.RelevanceScores](r.registry, config.RelevanceScoresContract); err == nil {
		return task, nil
	}
	return binding.Register(r.registry, config.RelevanceScoresContract, func(pairs []tasks.QueryDocument) error {
		if len(pairs) == 0 {
			return fmt.Errorf("at least one query/document pair is required")
		}
		for _, pair := range pairs {
			if !utf8.ValidString(pair.Query) || !utf8.ValidString(pair.Document) {
				return fmt.Errorf("query and document must be valid UTF-8")
			}
			if err := validateText(pair.Query); err != nil {
				return err
			}
			if err := validateText(pair.Document); err != nil {
				return err
			}
		}
		return nil
	}, tasks.ValidateRelevanceScores)
}

// Relevance prepares and warms a complete encoder/head artifact. Artifact
// fingerprints include encoder, task heads, tokenizer and mathematical config.
// A Runtime memoizes these fingerprints and treats its artifacts as immutable;
// replacing bytes requires a new Runtime generation. Ranking caches are local
// to that router process, rather than persisted across software releases.
func (r *Runtime) Relevance(ctx context.Context, spec config.ResolvedModelBinding) (_ *RelevanceScorer, callErr error) {
	defer func() { observePreparationFailure(spec, callErr) }()
	if spec.Binding.Contract != config.RelevanceScoresContract || spec.Binding.Adapter != "vela_reranker" || spec.Deployment.WithDefaults().Input.Overflow != "reject" {
		return nil, fmt.Errorf("%w: relevance scorer requires its raw-logit adapter and reject input policy", binding.ErrCapability)
	}
	selection := config.PairScorerSelection{}
	if spec.Binding.PairScorer != nil {
		selection = *spec.Binding.PairScorer
	}
	if selection.Layer < 0 || selection.Dimension < 0 {
		return nil, fmt.Errorf("%w: negative scorer selection", binding.ErrCapability)
	}
	task, err := r.relevanceTask()
	if err != nil {
		return nil, err
	}
	var resource *binding.Resource
	var capability binding.Capability
	var actual config.PairScorerSelection
	var infer func(context.Context, io.Closer, []tasks.QueryDocument) (tasks.RelevanceScores, error)
	switch spec.Deployment.Provider {
	case "candle":
		resource, capability, actual, infer, err = r.candleRelevance(ctx, spec, selection)
	case "ort":
		resource, capability, actual, infer, err = r.ortRelevance(ctx, spec, selection)
	default:
		err = fmt.Errorf("%w: relevance provider unavailable", binding.ErrCapability)
	}
	if err != nil {
		return nil, err
	}
	if actual.Layer <= 0 || actual.Dimension <= 0 || (selection.Layer != 0 && selection.Layer != actual.Layer) || (selection.Dimension != 0 && selection.Dimension != actual.Dimension) {
		_ = resource.Close()
		return nil, fmt.Errorf("%w: loaded pair scorer selection differs from its binding", binding.ErrCapability)
	}
	// Content and effective semantics separate cached ranking from a prior
	// generation at the same path. Artifact hashes are captured during load.
	revision, err := r.artifactRevision(ctx, spec.Deployment.Artifact)
	if err != nil {
		_ = resource.Close()
		return nil, err
	}
	headRevision := ""
	if spec.Deployment.Provider == "ort" && spec.Binding.Head != "" {
		path := spec.Binding.Head
		if !filepath.IsAbs(path) {
			path = filepath.Join(spec.Deployment.Artifact, path)
		}
		headRevision, err = r.artifactRevision(ctx, filepath.Dir(path))
		if err != nil {
			_ = resource.Close()
			return nil, err
		}
	}
	executionEvidence := []relevanceExecution{}
	err = resource.Use(ctx, func(value io.Closer) error {
		switch model := value.(type) {
		case *candle.PairScorer:
			info, infoErr := model.Info()
			if infoErr != nil {
				return nativeError(infoErr)
			}
			executionEvidence = append(executionEvidence, relevanceExecution{Provider: "candle", Device: info.Device, Precision: info.Precision, MathContract: "candle.modernbert.pair_scores.v1"})
		case *ort.PairScorer:
			info, infoErr := model.Info()
			if infoErr != nil {
				return ortError(infoErr)
			}
			for _, session := range info.Sessions {
				graphHash, hashErr := r.artifactRevision(ctx, session.Graph)
				if hashErr != nil {
					return hashErr
				}
				externalHash, hashErr := r.artifactRevision(ctx, filepath.Dir(session.Graph))
				if hashErr != nil {
					return hashErr
				}
				executionEvidence = append(executionEvidence, ortRelevanceExecution(session, capability.Device, graphHash, externalHash))
			}
		default:
			return fmt.Errorf("%w: unexpected pair scorer resource", binding.ErrCapability)
		}
		return nil
	})
	if err != nil {
		_ = resource.Close()
		return nil, err
	}
	descriptor, err := json.Marshal(struct {
		Version                         int
		Artifact, HeadArtifact, Adapter string
		Selection                       config.PairScorerSelection
		MaxTokens                       int
		Overflow                        string
		Semantics                       tasks.ScoreSemantics
		Execution                       []relevanceExecution
	}{1, revision, headRevision, spec.Binding.Adapter, actual, capability.Limits.EffectiveTokens(), capability.Limits.Overflow, tasks.RelevanceScoreSemantics(), executionEvidence})
	if err != nil {
		_ = resource.Close()
		return nil, err
	}
	bound, err := finishNativeTask(ctx, spec, task, capability, resource, infer, []tasks.QueryDocument{{Query: "warmup", Document: "warmup"}})
	if err != nil {
		return nil, err
	}
	digest := sha256.Sum256(descriptor)
	return &RelevanceScorer{task: bound, selection: actual, identity: hex.EncodeToString(digest[:])}, nil
}

type relevanceInfer = func(context.Context, io.Closer, []tasks.QueryDocument) (tasks.RelevanceScores, error)

func (r *Runtime) candleRelevance(ctx context.Context, spec config.ResolvedModelBinding, selection config.PairScorerSelection) (*binding.Resource, binding.Capability, config.PairScorerSelection, relevanceInfer, error) {
	var capability binding.Capability
	var actual config.PairScorerSelection
	options := candleOptions(spec)
	options.ModelType = "" // The dedicated loader validates actual ModernBERT config.
	if spec.Binding.Head != "" {
		return nil, capability, actual, nil, fmt.Errorf("%w: Candle pair heads must reside in the model artifact", binding.ErrCapability)
	}
	revision, err := r.artifactRevision(ctx, options.ModelPath)
	if err != nil {
		return nil, capability, actual, nil, err
	}
	execution, err := json.Marshal(struct {
		Options   candle.InstanceOptions
		Selection config.PairScorerSelection
	}{options, selection})
	if err != nil {
		return nil, capability, actual, nil, err
	}
	id := binding.ResourceIdentity{Artifact: options.ModelPath, Revision: revision, Provider: "candle", Device: options.Device, Precision: options.Precision, Execution: "relevance:" + string(execution)}
	budget, gate := resourceAdmission(spec)
	resource, err := r.Pool.Acquire(ctx, id, budget, gate, func(context.Context) (io.Closer, error) {
		model, loadErr := candle.LoadPairScorer(options, candle.PairScorerSelection{Layer: selection.Layer, Dimension: selection.Dimension})
		if loadErr != nil {
			return nil, nativeError(loadErr)
		}
		return model, nil
	})
	if err != nil {
		return nil, capability, actual, nil, err
	}
	err = resource.Use(ctx, func(value io.Closer) error {
		info, infoErr := value.(*candle.PairScorer).Info()
		if infoErr != nil {
			return nativeError(infoErr)
		}
		if info.PairScorer == nil {
			return fmt.Errorf("%w: missing actual pair scorer selection", binding.ErrCapability)
		}
		actual = config.PairScorerSelection{Layer: info.PairScorer.Layer, Dimension: info.PairScorer.Dimension}
		capability = candleCapability(spec, info)
		return nil
	})
	if err != nil {
		_ = resource.Close()
		return nil, capability, actual, nil, err
	}
	infer := func(_ context.Context, value io.Closer, pairs []tasks.QueryDocument) (tasks.RelevanceScores, error) {
		input := make([]candle.TextPair, len(pairs))
		for i, pair := range pairs {
			input[i] = candle.TextPair{Query: pair.Query, Document: pair.Document}
		}
		output, inferErr := value.(*candle.PairScorer).ScorePairs(input)
		result := tasks.RelevanceScores{Scores: output.Scores, Inputs: make([]tasks.InputUsage, len(output.Inputs))}
		for i, usage := range output.Inputs {
			result.Inputs[i] = *candleInputUsage(usage)
		}
		return result, nativeError(inferErr)
	}
	return resource, capability, actual, infer, nil
}

func (r *Runtime) ortRelevance(ctx context.Context, spec config.ResolvedModelBinding, selection config.PairScorerSelection) (*binding.Resource, binding.Capability, config.PairScorerSelection, relevanceInfer, error) {
	var capability binding.Capability
	var actual config.PairScorerSelection
	selectionJSON, err := json.Marshal(selection)
	if err != nil {
		return nil, capability, actual, nil, err
	}
	resource, err := r.ortResource(ctx, spec, "relevance:"+string(selectionJSON), func(options ort.Options) (io.Closer, error) {
		model, loadErr := ort.LoadPairScorer(options, ort.PairScorerSelection{Layer: selection.Layer, Dimension: selection.Dimension})
		if loadErr != nil {
			return nil, loadErr
		}
		return model, nil
	})
	if err != nil {
		return nil, capability, actual, nil, err
	}
	err = resource.Use(ctx, func(value io.Closer) error {
		info, infoErr := value.(*ort.PairScorer).Info()
		if infoErr != nil {
			return ortError(infoErr)
		}
		if info.PairScorer == nil {
			return fmt.Errorf("%w: missing actual ONNX pair scorer selection", binding.ErrCapability)
		}
		actual = config.PairScorerSelection{Layer: info.PairScorer.Layer, Dimension: info.PairScorer.Dimension}
		capability, infoErr = ortCapability(spec, info)
		return infoErr
	})
	if err != nil {
		_ = resource.Close()
		return nil, capability, actual, nil, err
	}
	infer := func(_ context.Context, value io.Closer, pairs []tasks.QueryDocument) (tasks.RelevanceScores, error) {
		input := make([]ort.TextPair, len(pairs))
		for i, pair := range pairs {
			input[i] = ort.TextPair{Query: pair.Query, Document: pair.Document}
		}
		output, inferErr := value.(*ort.PairScorer).ScorePairs(input)
		result := tasks.RelevanceScores{Scores: output.Scores, Inputs: make([]tasks.InputUsage, len(output.Inputs))}
		for i, usage := range output.Inputs {
			result.Inputs[i] = *ortInputUsage(usage)
		}
		return result, ortError(inferErr)
	}
	return resource, capability, actual, infer, nil
}

// Observational IDs, profiling paths and counters do not identify model math.
// Artifact fingerprints bind relative names and bytes, not bare file SHA256.
// Candle exposes a math contract version, not an attested runtime build ID.
type relevanceExecution struct {
	GraphFingerprint, ExternalArtifactFingerprint string
	CompilerFlags                                 map[string]string
	MathContract                                  string
	Provider, Device, Precision, RuntimeBuild     string
	CustomOpsProfile, CustomOpsSHA256             string
	CPUFallbackDisabled                           bool
}

func ortRelevanceExecution(session ort.SessionEvidence, device, graphHash, externalHash string) relevanceExecution {
	return relevanceExecution{
		GraphFingerprint: graphHash, ExternalArtifactFingerprint: externalHash,
		Provider: session.Provider, Device: device, Precision: session.Precision,
		RuntimeBuild: session.RuntimeBuild, CompilerFlags: session.CompilerFlags,
		CustomOpsProfile: session.CustomOpsProfile, CustomOpsSHA256: session.CustomOpsSHA256,
		CPUFallbackDisabled: session.CPUFallbackDisabled,
	}
}

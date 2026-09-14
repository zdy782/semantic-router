# =============================================================================
# SIGNALS
# =============================================================================

# =============================================================================
# ROUTES
# =============================================================================

# =============================================================================
# RECIPE balance
# =============================================================================

RECIPE balance (description = "Everyday routing with measured tradeoffs between quality, responsiveness, and cost.") {
  # =============================================================================
  # ROUTING PROFILE
  # =============================================================================

  ROUTING {
    candidate_requirements: { capabilities: "declared", context: "known_limits" }
    strategy: priority
  }

  # =============================================================================
  # SIGNALS
  # =============================================================================

  SIGNAL domain health {
    description: "Medical and health information."
    mmlu_categories: ["health"]
  }

  SIGNAL domain law {
    description: "Legal information and interpretation."
    mmlu_categories: ["law"]
  }

  SIGNAL domain business {
    description: "Business information and commercial decisions."
    mmlu_categories: ["business"]
  }

  SIGNAL domain economics {
    description: "Economic information and financial decisions."
    mmlu_categories: ["economics"]
  }

  SIGNAL keyword deliberate {
    operator: "OR"
    keywords: ["analyze the tradeoffs", "from first principles", "root cause", "reason step by step", "compare the alternatives carefully", "分析取舍", "第一性原理", "根因分析", "逐步推理", "analizar las ventajas y desventajas", "causa raíz", "analyser les compromis", "cause racine", "トレードオフを分析", "根本原因", "kompromisse analysieren", "ursache analysieren", "analisar as compensações", "causa raiz", "트레이드오프를 분석", "근본 원인", "حلل المفاضلات", "السبب الجذري", "समझौतों का विश्लेषण", "मूल कारण", "проанализируй компромиссы", "первопричина"]
    method: "regex"
  }

  SIGNAL keyword verify {
    operator: "OR"
    keywords: ["verify the answer", "cite sources", "fact-check", "check the evidence", "核实答案", "引用来源", "verificar la respuesta", "citer les sources", "答えを検証", "quellen zitieren", "verificar a resposta", "답변을 검증", "تحقق من الإجابة", "उत्तर सत्यापित करें", "проверь ответ"]
    method: "regex"
  }

  SIGNAL keyword no_analysis {
    operator: "OR"
    keywords: ["do not analyze", "don't analyze", "without analysis", "不要分析", "无需分析", "no analices", "sans analyse", "分析しない", "nicht analysieren", "sem análise", "분석하지 마", "دون تحليل", "विश्लेषण मत करो", "без анализа"]
    method: "regex"
  }

  SIGNAL keyword correction {
    operator: "OR"
    keywords: ["that's wrong", "wrong answer", "\\b(is|was|were) wrong\\b", "\\banswer was incorrect\\b", "\\bcorrect (it|this|the answer)\\b", "please correct the answer", "try again", "回答错了", "请纠正答案", "la respuesta es incorrecta", "corrige la respuesta", "la réponse est incorrecte", "corrige la réponse", "回答が間違っています", "bitte korrigiere die antwort", "a resposta está errada", "답변이 틀렸습니다", "الإجابة خاطئة", "उत्तर गलत है", "ответ неверный"]
    method: "regex"
  }

  SIGNAL embedding consequential {
    threshold: 0.7
    candidates: ["Advise whether this medical treatment is appropriate for my symptoms and medications.", "Assess the legal risks before I sign this contract.", "Evaluate the financial risks before I invest my savings.", "根据我的症状和用药情况评估治疗建议。", "在我签署合同前分析法律风险。", "Evalúa los riesgos médicos de combinar estos medicamentos.", "Évalue les risques juridiques avant de signer ce contrat.", "قيّم مخاطر هذا القرار المالي قبل استثمار مدخراتي."]
    aggregation_method: "max"
  }

  SIGNAL fact_check needs_fact_check {
    description: "The task calls for checking factual claims; this signal does not verify an answer."
  }

  SIGNAL user_feedback wrong_answer {
    description: "The user rejects the correctness of an earlier answer."
  }

  SIGNAL reask repeat {
    threshold: 0.8
    lookback_turns: 1
  }

  SIGNAL structure quoted_request {
    description: "Vocabulary mentioned for explanation or translation is not an execution request."
    feature: { source: { pattern: "(?i)(\\b(define|translate|explain)\\b.{0,48}\\b(phrase|term|expression)\\b|(définis|traduis|explique).{0,48}(expression|terme)|(define|traduce|explica).{0,48}(frase|expresión|término)|(definiere|übersetze|erkläre).{0,48}(ausdruck|begriff)|(defina|traduza|explique).{0,48}(frase|expressão|ter(?:mo))|(정의|번역|설명).{0,16}(문구|표현|용어|“|「)|(عرّف|ترجم|اشرح).{0,32}(العبارة|التعبير|المصطلح)|(परिभाषित|अनुवाद|समझाइए).{0,32}(वाक्यांश|अभिव्यक्ति|शब्द)|(определи|переведи|объясни).{0,48}(фразу|выражение|термин)|(定义|翻译|解释).{0,16}(短语|词语|“|「)|(説明|翻訳).{0,16}(表現|語句|「)|([\"“「][^\"”」]{1,120}[\"”」]).{0,80}(define|translate|explain|설명|정의|번역|اشرح|عرّف|ترجم|समझाइए|परिभाषित|अनुवाद|объясни|определи|переведи|解释|定义|翻译|説明|翻訳))", type: "regex" }, type: "exists" }
  }

  SIGNAL conversation has_answer {
    feature: { source: { role: "assistant", type: "message" }, type: "exists" }
  }

  SIGNAL conversation tool_loop {
    feature: { source: { type: "active_tool_loop" }, type: "exists" }
  }

  SIGNAL conversation tool_required {
    feature: { source: { type: "tool_choice_required" }, type: "exists" }
  }

  SIGNAL complexity difficulty {
    threshold: 0.08
    description: "Separate direct tasks from analysis and synthesis. Length and language do not determine difficulty."
    hard: { candidates: ["Analyze a production failure from several competing root causes.", "Design a distributed system and justify its consistency tradeoffs.", "Synthesize conflicting evidence into a defensible recommendation.", "分析复杂生产故障中的多个竞争性根因并提出可靠方案。", "Analiza varias causas raíz y sintetiza una recomendación defendible.", "حلّل عدة أسباب جذرية متنافسة وقدّم توصية قابلة للدفاع."] }
    easy: { candidates: ["Give a short definition of a common term.", "Summarize one paragraph in a single sentence.", "Explain a basic concept with one example.", "用一句话解释一个常见概念。", "Explica un concepto cotidiano con un ejemplo.", "اشرح مفهوماً شائعاً بمثال بسيط."] }
  }

  PROJECTION score recovery {
    method: "weighted_sum"
    inputs: [{ type: "user_feedback", weight: 1, name: "wrong_answer" }, { type: "reask", weight: 0.5, name: "repeat" }, { type: "keyword", weight: 0.5, name: "correction" }]
  }

  PROJECTION mapping recovery_band {
    source: "recovery"
    method: "threshold_bands"
    outputs: [{ name: "retry", gte: 1 }]
  }

  # =============================================================================
  # PLUGINS
  # =============================================================================

  PLUGIN request_params request_params {}

  # =============================================================================
  # ROUTES
  # =============================================================================

  ROUTE reasoning (description = "Use a stronger quality pool for hard tasks, factual stakes, or answer recovery.", on_unknown = "no_match") {
    PRIORITY 300
    WHEN (complexity("difficulty:hard") AND NOT keyword("no_analysis") OR (keyword("deliberate") OR keyword("verify")) AND NOT keyword("no_analysis") AND NOT structure("quoted_request") OR projection("retry") AND (conversation("has_answer") OR keyword("correction")) AND NOT structure("quoted_request") OR embedding("consequential") AND fact_check("needs_fact_check") AND (domain("health") OR domain("law") OR domain("business") OR domain("economics")))
    ALGORITHM multi_factor {
      latency_metric: "tpot"
      latency_percentile: 95
      minimum_candidates: 1
      objective: { priorities: [{ factor: "quality", tolerance: 0.03 }, { factor: "latency", tolerance: 0.1 }, { factor: "cost" }, { factor: "load" }], strategy: "lexicographic" }
      on_no_candidates: "fail"
      quality: { index: "vllm-sr/reasoning@1.0.0", on_missing: "exclude" }
    }
    PLUGIN request_params {
      default_max_tokens: 8192
    }
  }

  ROUTE simple (description = "Use an efficient model when the task is positively identified as simple.", on_unknown = "no_match") {
    PRIORITY 100
    WHEN complexity("difficulty:easy") AND NOT conversation("has_answer") AND NOT conversation("tool_loop") AND NOT conversation("tool_required") AND NOT (embedding("consequential") AND fact_check("needs_fact_check") AND (domain("health") OR domain("law") OR domain("business") OR domain("economics")))
    ALGORITHM multi_factor {
      latency_metric: "ttft"
      latency_percentile: 95
      minimum_candidates: 1
      objective: { priorities: [{ factor: "quality", tolerance: 0.12 }, { factor: "cost", tolerance: 0.05 }, { factor: "latency", tolerance: 0.1 }, { factor: "load" }], strategy: "lexicographic" }
      on_no_candidates: "fail"
      quality: { index: "vllm-sr/general@1.0.0", on_missing: "exclude" }
    }
    PLUGIN request_params {
      default_max_tokens: 4096
    }
  }

  ROUTE medium (description = "Keep ambiguous, conversational, and ordinary tool requests in a balanced pool.") {
    PRIORITY 10
    ALGORITHM multi_factor {
      latency_metric: "ttft"
      latency_percentile: 95
      minimum_candidates: 1
      objective: { priorities: [{ factor: "quality", tolerance: 0.07 }, { factor: "latency", tolerance: 0.1 }, { factor: "cost", tolerance: 0.05 }, { factor: "load" }], strategy: "lexicographic" }
      on_no_candidates: "fail"
      quality: { index: "vllm-sr/general@1.0.0", on_missing: "exclude" }
    }
    PLUGIN request_params {
      default_max_tokens: 4096
    }
  }

}

# =============================================================================
# RECIPE speed
# =============================================================================

RECIPE speed (description = "Responsive single-model answers, with separate priorities for interaction and sustained generation.") {
  # =============================================================================
  # ROUTING PROFILE
  # =============================================================================

  ROUTING {
    candidate_requirements: { capabilities: "declared", context: "known_limits" }
    strategy: priority
  }

  # =============================================================================
  # SIGNALS
  # =============================================================================

  SIGNAL keyword deliberate {
    operator: "OR"
    keywords: ["analyze the tradeoffs", "from first principles", "root cause", "reason step by step", "compare the alternatives carefully", "分析取舍", "第一性原理", "根因分析", "逐步推理", "analizar las ventajas y desventajas", "causa raíz", "analyser les compromis", "cause racine", "トレードオフを分析", "根本原因", "kompromisse analysieren", "ursache analysieren", "analisar as compensações", "causa raiz", "트레이드오프를 분석", "근본 원인", "حلل المفاضلات", "السبب الجذري", "समझौतों का विश्लेषण", "मूल कारण", "проанализируй компромиссы", "первопричина"]
    method: "regex"
  }

  SIGNAL keyword verify {
    operator: "OR"
    keywords: ["verify the answer", "cite sources", "fact-check", "check the evidence", "核实答案", "引用来源", "verificar la respuesta", "citer les sources", "答えを検証", "quellen zitieren", "verificar a resposta", "답변을 검증", "تحقق من الإجابة", "उत्तर सत्यापित करें", "проверь ответ"]
    method: "regex"
  }

  SIGNAL keyword no_analysis {
    operator: "OR"
    keywords: ["do not analyze", "don't analyze", "without analysis", "不要分析", "无需分析", "no analices", "sans analyse", "分析しない", "nicht analysieren", "sem análise", "분석하지 마", "دون تحليل", "विश्लेषण मत करो", "без анализа"]
    method: "regex"
  }

  SIGNAL keyword tool_intent {
    operator: "OR"
    keywords: ["\\b(use|using|call|invoke|run)\\b.{0,48}\\b(tool|function)\\b", "\\b(use|using|call|invoke|run)\\b.{0,48}\\b(calculator|browser|search|lookup|retriever|api|database)\\b", "\\b(search|look up|fetch|query)\\b.{0,48}\\b(tool|function|integration)\\b", "(使用|调用|运行).{0,24}(工具|函数)", "(usar|llamar|invocar).{0,48}(herramienta|función)", "(utiliser|appeler|invoquer).{0,48}(outil|fonction)", "(ツール|関数).{0,24}(使用|呼び出)", "(werkzeug|funktion).{0,48}(verwenden|aufrufen)", "(usar|chamar|invocar).{0,48}(ferramenta|função)", "(도구|함수).{0,24}(사용|호출)", "(استخدم|استدع).{0,32}(الأداة|الدالة)", "(टूल|फ़ंक्शन).{0,32}(उपयोग|कॉल)", "(используй|вызови).{0,48}(инструмент|функци)"]
    method: "regex"
  }

  SIGNAL structure quoted_request {
    description: "Vocabulary mentioned for explanation or translation is not an execution request."
    feature: { source: { pattern: "(?i)(\\b(define|translate|explain)\\b.{0,48}\\b(phrase|term|expression)\\b|(définis|traduis|explique).{0,48}(expression|terme)|(define|traduce|explica).{0,48}(frase|expresión|término)|(definiere|übersetze|erkläre).{0,48}(ausdruck|begriff)|(defina|traduza|explique).{0,48}(frase|expressão|ter(?:mo))|(정의|번역|설명).{0,16}(문구|표현|용어|“|「)|(عرّف|ترجم|اشرح).{0,32}(العبارة|التعبير|المصطلح)|(परिभाषित|अनुवाद|समझाइए).{0,32}(वाक्यांश|अभिव्यक्ति|शब्द)|(определи|переведи|объясни).{0,48}(фразу|выражение|термин)|(定义|翻译|解释).{0,16}(短语|词语|“|「)|(説明|翻訳).{0,16}(表現|語句|「)|([\"“「][^\"”」]{1,120}[\"”」]).{0,80}(define|translate|explain|설명|정의|번역|اشرح|عرّف|ترجم|समझाइए|परिभाषित|अनुवाद|объясни|определи|переведи|解释|定义|翻译|説明|翻訳))", type: "regex" }, type: "exists" }
  }

  SIGNAL conversation tool_loop {
    feature: { source: { type: "active_tool_loop" }, type: "exists" }
  }

  SIGNAL conversation tool_required {
    feature: { source: { type: "tool_choice_required" }, type: "exists" }
  }

  SIGNAL conversation tool_disabled {
    feature: { source: { type: "tool_choice_none" }, type: "exists" }
  }

  SIGNAL conversation has_tools {
    feature: { source: { type: "tool_definition" }, type: "count" }
    predicate: { gte: 1 }
  }

  SIGNAL complexity difficulty {
    threshold: 0.08
    description: "Separate direct tasks from analysis and synthesis. Length and language do not determine difficulty."
    hard: { candidates: ["Analyze a production failure from several competing root causes.", "Design a distributed system and justify its consistency tradeoffs.", "Synthesize conflicting evidence into a defensible recommendation.", "分析复杂生产故障中的多个竞争性根因并提出可靠方案。", "Analiza varias causas raíz y sintetiza una recomendación defendible.", "حلّل عدة أسباب جذرية متنافسة وقدّم توصية قابلة للدفاع."] }
    easy: { candidates: ["Give a short definition of a common term.", "Summarize one paragraph in a single sentence.", "Explain a basic concept with one example.", "用一句话解释一个常见概念。", "Explica un concepto cotidiano con un ejemplo.", "اشرح مفهوماً شائعاً بمثال بسيط."] }
  }

  # =============================================================================
  # PLUGINS
  # =============================================================================

  PLUGIN request_params request_params {}

  # =============================================================================
  # ROUTES
  # =============================================================================

  ROUTE tools (description = "Prefer responsive tool-capable models for active or explicitly requested tool use.", on_unknown = "no_match") {
    PRIORITY 300
    WHEN (conversation("tool_loop") OR conversation("has_tools") AND NOT conversation("tool_disabled") AND (conversation("tool_required") OR keyword("tool_intent") AND NOT structure("quoted_request")))
    ALGORITHM multi_factor {
      latency_metric: "ttft"
      latency_percentile: 95
      minimum_candidates: 1
      objective: { priorities: [{ factor: "quality", tolerance: 0.1 }, { factor: "latency", tolerance: 0.05 }, { factor: "load" }, { factor: "cost" }], strategy: "lexicographic" }
      on_no_candidates: "fail"
      quality: { index: "vllm-sr/agentic@1.0.0", on_missing: "exclude" }
    }
    PLUGIN request_params {
      default_max_tokens: 4096
    }
  }

  ROUTE reasoning (description = "Preserve reasoning quality while preferring fast token generation.", on_unknown = "match") {
    PRIORITY 200
    WHEN (complexity("difficulty:hard") AND NOT keyword("no_analysis") OR (keyword("deliberate") OR keyword("verify")) AND NOT keyword("no_analysis") AND NOT structure("quoted_request"))
    ALGORITHM multi_factor {
      latency_metric: "tpot"
      latency_percentile: 95
      minimum_candidates: 1
      objective: { priorities: [{ factor: "quality", tolerance: 0.07 }, { factor: "latency", tolerance: 0.05 }, { factor: "load" }, { factor: "cost" }], strategy: "lexicographic" }
      on_no_candidates: "fail"
      quality: { index: "vllm-sr/reasoning@1.0.0", on_missing: "exclude" }
    }
    PLUGIN request_params {
      default_max_tokens: 8192
    }
  }

  ROUTE fast (description = "Prefer a fast first token among models close in general quality.") {
    PRIORITY 10
    ALGORITHM multi_factor {
      latency_metric: "ttft"
      latency_percentile: 95
      minimum_candidates: 1
      objective: { priorities: [{ factor: "quality", tolerance: 0.12 }, { factor: "latency", tolerance: 0.05 }, { factor: "load" }, { factor: "cost" }], strategy: "lexicographic" }
      on_no_candidates: "fail"
      quality: { index: "vllm-sr/general@1.0.0", on_missing: "exclude" }
    }
    PLUGIN request_params {
      default_max_tokens: 4096
    }
  }

}

# =============================================================================
# RECIPE cost
# =============================================================================

RECIPE cost (description = "Lower serving cost with bounded quality tradeoffs and targeted escalation.") {
  # =============================================================================
  # ROUTING PROFILE
  # =============================================================================

  ROUTING {
    candidate_requirements: { capabilities: "declared", context: "known_limits" }
    strategy: priority
  }

  # =============================================================================
  # SIGNALS
  # =============================================================================

  SIGNAL keyword deliberate {
    operator: "OR"
    keywords: ["analyze the tradeoffs", "from first principles", "root cause", "reason step by step", "compare the alternatives carefully", "分析取舍", "第一性原理", "根因分析", "逐步推理", "analizar las ventajas y desventajas", "causa raíz", "analyser les compromis", "cause racine", "トレードオフを分析", "根本原因", "kompromisse analysieren", "ursache analysieren", "analisar as compensações", "causa raiz", "트레이드오프를 분석", "근본 원인", "حلل المفاضلات", "السبب الجذري", "समझौतों का विश्लेषण", "मूल कारण", "проанализируй компромиссы", "первопричина"]
    method: "regex"
  }

  SIGNAL keyword verify {
    operator: "OR"
    keywords: ["verify the answer", "cite sources", "fact-check", "check the evidence", "核实答案", "引用来源", "verificar la respuesta", "citer les sources", "答えを検証", "quellen zitieren", "verificar a resposta", "답변을 검증", "تحقق من الإجابة", "उत्तर सत्यापित करें", "проверь ответ"]
    method: "regex"
  }

  SIGNAL keyword no_analysis {
    operator: "OR"
    keywords: ["do not analyze", "don't analyze", "without analysis", "不要分析", "无需分析", "no analices", "sans analyse", "分析しない", "nicht analysieren", "sem análise", "분석하지 마", "دون تحليل", "विश्लेषण मत करो", "без анализа"]
    method: "regex"
  }

  SIGNAL keyword tool_intent {
    operator: "OR"
    keywords: ["\\b(use|using|call|invoke|run)\\b.{0,48}\\b(tool|function)\\b", "\\b(use|using|call|invoke|run)\\b.{0,48}\\b(calculator|browser|search|lookup|retriever|api|database)\\b", "\\b(search|look up|fetch|query)\\b.{0,48}\\b(tool|function|integration)\\b", "(使用|调用|运行).{0,24}(工具|函数)", "(usar|llamar|invocar).{0,48}(herramienta|función)", "(utiliser|appeler|invoquer).{0,48}(outil|fonction)", "(ツール|関数).{0,24}(使用|呼び出)", "(werkzeug|funktion).{0,48}(verwenden|aufrufen)", "(usar|chamar|invocar).{0,48}(ferramenta|função)", "(도구|함수).{0,24}(사용|호출)", "(استخدم|استدع).{0,32}(الأداة|الدالة)", "(टूल|फ़ंक्शन).{0,32}(उपयोग|कॉल)", "(используй|вызови).{0,48}(инструмент|функци)"]
    method: "regex"
  }

  SIGNAL keyword correction {
    operator: "OR"
    keywords: ["that's wrong", "wrong answer", "\\b(is|was|were) wrong\\b", "\\banswer was incorrect\\b", "\\bcorrect (it|this|the answer)\\b", "please correct the answer", "try again", "回答错了", "请纠正答案", "la respuesta es incorrecta", "corrige la respuesta", "la réponse est incorrecte", "corrige la réponse", "回答が間違っています", "bitte korrigiere die antwort", "a resposta está errada", "답변이 틀렸습니다", "الإجابة خاطئة", "उत्तर गलत है", "ответ неверный"]
    method: "regex"
  }

  SIGNAL reask repeat {
    threshold: 0.8
    lookback_turns: 1
  }

  SIGNAL structure quoted_request {
    description: "Vocabulary mentioned for explanation or translation is not an execution request."
    feature: { source: { pattern: "(?i)(\\b(define|translate|explain)\\b.{0,48}\\b(phrase|term|expression)\\b|(définis|traduis|explique).{0,48}(expression|terme)|(define|traduce|explica).{0,48}(frase|expresión|término)|(definiere|übersetze|erkläre).{0,48}(ausdruck|begriff)|(defina|traduza|explique).{0,48}(frase|expressão|ter(?:mo))|(정의|번역|설명).{0,16}(문구|표현|용어|“|「)|(عرّف|ترجم|اشرح).{0,32}(العبارة|التعبير|المصطلح)|(परिभाषित|अनुवाद|समझाइए).{0,32}(वाक्यांश|अभिव्यक्ति|शब्द)|(определи|переведи|объясни).{0,48}(фразу|выражение|термин)|(定义|翻译|解释).{0,16}(短语|词语|“|「)|(説明|翻訳).{0,16}(表現|語句|「)|([\"“「][^\"”」]{1,120}[\"”」]).{0,80}(define|translate|explain|설명|정의|번역|اشرح|عرّف|ترجم|समझाइए|परिभाषित|अनुवाद|объясни|определи|переведи|解释|定义|翻译|説明|翻訳))", type: "regex" }, type: "exists" }
  }

  SIGNAL conversation tool_loop {
    feature: { source: { type: "active_tool_loop" }, type: "exists" }
  }

  SIGNAL conversation tool_required {
    feature: { source: { type: "tool_choice_required" }, type: "exists" }
  }

  SIGNAL conversation tool_disabled {
    feature: { source: { type: "tool_choice_none" }, type: "exists" }
  }

  SIGNAL conversation has_tools {
    feature: { source: { type: "tool_definition" }, type: "count" }
    predicate: { gte: 1 }
  }

  SIGNAL conversation has_answer {
    feature: { source: { role: "assistant", type: "message" }, type: "exists" }
  }

  SIGNAL complexity difficulty {
    threshold: 0.08
    description: "Separate direct tasks from analysis and synthesis. Length and language do not determine difficulty."
    hard: { candidates: ["Analyze a production failure from several competing root causes.", "Design a distributed system and justify its consistency tradeoffs.", "Synthesize conflicting evidence into a defensible recommendation.", "分析复杂生产故障中的多个竞争性根因并提出可靠方案。", "Analiza varias causas raíz y sintetiza una recomendación defendible.", "حلّل عدة أسباب جذرية متنافسة وقدّم توصية قابلة للدفاع."] }
    easy: { candidates: ["Give a short definition of a common term.", "Summarize one paragraph in a single sentence.", "Explain a basic concept with one example.", "用一句话解释一个常见概念。", "Explica un concepto cotidiano con un ejemplo.", "اشرح مفهوماً شائعاً بمثال بسيط."] }
  }

  # =============================================================================
  # PLUGINS
  # =============================================================================

  PLUGIN request_params request_params {}

  # =============================================================================
  # ROUTES
  # =============================================================================

  ROUTE tools (description = "Choose a cost-efficient tool model without changing the client tool protocol.", on_unknown = "no_match") {
    PRIORITY 300
    WHEN (conversation("tool_loop") OR conversation("has_tools") AND NOT conversation("tool_disabled") AND (conversation("tool_required") OR keyword("tool_intent") AND NOT structure("quoted_request")))
    ALGORITHM multi_factor {
      latency_metric: "ttft"
      latency_percentile: 95
      minimum_candidates: 1
      objective: { priorities: [{ factor: "quality", tolerance: 0.1 }, { factor: "cost" }, { factor: "latency", tolerance: 0.1 }, { factor: "load" }], strategy: "lexicographic" }
      on_no_candidates: "fail"
      quality: { index: "vllm-sr/agentic@1.0.0", on_missing: "exclude" }
    }
    PLUGIN request_params {
      default_max_tokens: 4096
    }
  }

  ROUTE reasoning (description = "Spend more only for hard tasks or a repeated request for correction.", on_unknown = "match") {
    PRIORITY 200
    WHEN (complexity("difficulty:hard") AND NOT keyword("no_analysis") OR (keyword("deliberate") OR keyword("verify")) AND NOT keyword("no_analysis") AND NOT structure("quoted_request") OR conversation("has_answer") AND reask("repeat") AND keyword("correction") AND NOT structure("quoted_request"))
    ALGORITHM multi_factor {
      latency_metric: "tpot"
      latency_percentile: 95
      minimum_candidates: 1
      objective: { priorities: [{ factor: "quality", tolerance: 0.07 }, { factor: "cost" }, { factor: "latency", tolerance: 0.1 }, { factor: "load" }], strategy: "lexicographic" }
      on_no_candidates: "fail"
      quality: { index: "vllm-sr/reasoning@1.0.0", on_missing: "exclude" }
    }
    PLUGIN request_params {
      default_max_tokens: 8192
    }
  }

  ROUTE economy (description = "Prefer the lowest estimated request cost within the general-quality band.") {
    PRIORITY 10
    ALGORITHM multi_factor {
      latency_metric: "ttft"
      latency_percentile: 95
      minimum_candidates: 1
      objective: { priorities: [{ factor: "quality", tolerance: 0.15 }, { factor: "cost" }, { factor: "latency", tolerance: 0.1 }, { factor: "load" }], strategy: "lexicographic" }
      on_no_candidates: "fail"
      quality: { index: "vllm-sr/general@1.0.0", on_missing: "exclude" }
    }
    PLUGIN request_params {
      default_max_tokens: 4096
    }
  }

}

# =============================================================================
# RECIPE accuracy
# =============================================================================

RECIPE accuracy (description = "Quality-first answers with deliberate, bounded use of independent analyses and workflows.") {
  # =============================================================================
  # ROUTING PROFILE
  # =============================================================================

  ROUTING {
    candidate_requirements: { capabilities: "declared", context: "known_limits" }
    strategy: priority
  }

  # =============================================================================
  # SIGNALS
  # =============================================================================

  SIGNAL domain health {
    description: "Medical and health information."
    mmlu_categories: ["health"]
  }

  SIGNAL domain law {
    description: "Legal information and interpretation."
    mmlu_categories: ["law"]
  }

  SIGNAL domain business {
    description: "Business information and commercial decisions."
    mmlu_categories: ["business"]
  }

  SIGNAL domain economics {
    description: "Economic information and financial decisions."
    mmlu_categories: ["economics"]
  }

  SIGNAL keyword deliberate {
    operator: "OR"
    keywords: ["analyze the tradeoffs", "from first principles", "root cause", "reason step by step", "compare the alternatives carefully", "分析取舍", "第一性原理", "根因分析", "逐步推理", "analizar las ventajas y desventajas", "causa raíz", "analyser les compromis", "cause racine", "トレードオフを分析", "根本原因", "kompromisse analysieren", "ursache analysieren", "analisar as compensações", "causa raiz", "트레이드오프를 분석", "근본 원인", "حلل المفاضلات", "السبب الجذري", "समझौतों का विश्लेषण", "मूल कारण", "проанализируй компромиссы", "первопричина"]
    method: "regex"
  }

  SIGNAL keyword verify {
    operator: "OR"
    keywords: ["verify the answer", "cite sources", "fact-check", "check the evidence", "核实答案", "引用来源", "verificar la respuesta", "citer les sources", "答えを検証", "quellen zitieren", "verificar a resposta", "답변을 검증", "تحقق من الإجابة", "उत्तर सत्यापित करें", "проверь ответ"]
    method: "regex"
  }

  SIGNAL keyword no_analysis {
    operator: "OR"
    keywords: ["do not analyze", "don't analyze", "without analysis", "不要分析", "无需分析", "no analices", "sans analyse", "分析しない", "nicht analysieren", "sem análise", "분석하지 마", "دون تحليل", "विश्लेषण मत करो", "без анализа"]
    method: "regex"
  }

  SIGNAL keyword correction {
    operator: "OR"
    keywords: ["that's wrong", "wrong answer", "\\b(is|was|were) wrong\\b", "\\banswer was incorrect\\b", "\\bcorrect (it|this|the answer)\\b", "please correct the answer", "try again", "回答错了", "请纠正答案", "la respuesta es incorrecta", "corrige la respuesta", "la réponse est incorrecte", "corrige la réponse", "回答が間違っています", "bitte korrigiere die antwort", "a resposta está errada", "답변이 틀렸습니다", "الإجابة خاطئة", "उत्तर गलत है", "ответ неверный"]
    method: "regex"
  }

  SIGNAL keyword single {
    operator: "OR"
    keywords: ["\\b(one|single) model\\b", "\\b(no|without) parallel (models?|orchestration)\\b", "单个模型", "一个模型", "不要并行", "un seul modèle", "un solo modelo", "ein einzelnes modell", "um único modelo", "単一モデル", "하나의 모델", "نموذج واحد", "одной модели"]
    method: "regex"
  }

  SIGNAL keyword workflow {
    operator: "OR"
    keywords: ["break this into independent workstreams", "\\bbreak\\b.{0,160}\\bindependent workstreams\\b", "\\b(using?|with) tools?\\b.{0,160}\\bworkstreams\\b", "investigate, plan, and implement", "use tools to gather evidence and execute", "分解为独立工作流", "调查、规划并实现", "investigar, planificar e implementar", "enquêter, planifier et implémenter", "調査、計画、実装", "untersuchen, planen und implementieren", "investigar, planejar e implementar", "조사하고 계획하고 구현", "التحقيق والتخطيط والتنفيذ", "जाँच, योजना और कार्यान्वयन", "исследовать, спланировать и реализовать"]
    method: "regex"
  }

  SIGNAL keyword review {
    operator: "OR"
    keywords: ["independent expert opinions", "compare competing hypotheses", "adversarial debate and verdict", "比较多个假设并得出结论", "独立专家意见", "comparar hipótesis contrapuestas", "comparer des hypothèses concurrentes", "複数の仮説を比較", "konkurrierende hypothesen vergleichen", "comparar hipóteses concorrentes", "경쟁 가설을 비교", "قارن الفرضيات المتنافسة", "प्रतिस्पर्धी परिकल्पनाओं की तुलना", "сравнить конкурирующие гипотезы", "\\b(ask|consult)\\b.{0,40}\\bindependent experts?\\b"]
    method: "regex"
  }

  SIGNAL embedding consequential {
    threshold: 0.7
    candidates: ["Advise whether this medical treatment is appropriate for my symptoms and medications.", "Assess the legal risks before I sign this contract.", "Evaluate the financial risks before I invest my savings.", "根据我的症状和用药情况评估治疗建议。", "在我签署合同前分析法律风险。", "Evalúa los riesgos médicos de combinar estos medicamentos.", "Évalue les risques juridiques avant de signer ce contrat.", "قيّم مخاطر هذا القرار المالي قبل استثمار مدخراتي."]
    aggregation_method: "max"
  }

  SIGNAL embedding workflow_intent {
    threshold: 0.78
    candidates: ["Investigate the repository, implement the fix, run validation, and iterate until it works.", "调查代码库、实现修复、验证结果并迭代到完成。", "Investiga el repositorio, implementa la solución y valida los cambios.", "Enquête sur le dépôt, implémente la correction et valide le résultat.", "リポジトリを調査し、修正を実装して検証してください。", "Untersuche das Repository, implementiere die Korrektur und validiere sie.", "Investigue o repositório, implemente a correção e valide o resultado.", "저장소를 조사하고 수정 사항을 구현한 뒤 결과를 검증하세요.", "افحص المستودع ونفّذ الإصلاح وتحقق من النتيجة.", "रिपॉज़िटरी की जाँच करें, सुधार लागू करें और परिणाम सत्यापित करें।", "Исследуй репозиторий, реализуй исправление и проверь результат."]
    aggregation_method: "max"
  }

  SIGNAL embedding review_intent {
    threshold: 0.6
    candidates: ["Ask independent experts to solve the problem and synthesize the most reliable conclusion.", "汇总多个独立专家观点，解决分歧并得出可靠结论。", "Compara análisis independientes y sintetiza la conclusión más fiable.", "Compare des analyses indépendantes et synthétise la conclusion la plus fiable.", "複数の独立した分析を比較し、最も信頼できる結論を統合してください。", "Vergleiche unabhängige Analysen und synthetisiere die zuverlässigste Schlussfolgerung.", "Compare análises independentes e sintetize a conclusão mais confiável.", "독립적인 분석을 비교하고 가장 신뢰할 수 있는 결론을 종합하세요.", "قارن تحليلات مستقلة واستخلص النتيجة الأكثر موثوقية.", "स्वतंत्र विश्लेषणों की तुलना कर सबसे विश्वसनीय निष्कर्ष निकालें।", "Сравни независимые анализы и синтезируй самый надёжный вывод."]
    aggregation_method: "max"
  }

  SIGNAL fact_check needs_fact_check {
    description: "The task calls for checking factual claims; this signal does not verify an answer."
  }

  SIGNAL user_feedback wrong_answer {
    description: "The user rejects the correctness of an earlier answer."
  }

  SIGNAL reask repeat {
    threshold: 0.8
    lookback_turns: 1
  }

  SIGNAL structure quoted_request {
    description: "Vocabulary mentioned for explanation or translation is not an execution request."
    feature: { source: { pattern: "(?i)(\\b(define|translate|explain)\\b.{0,48}\\b(phrase|term|expression)\\b|(définis|traduis|explique).{0,48}(expression|terme)|(define|traduce|explica).{0,48}(frase|expresión|término)|(definiere|übersetze|erkläre).{0,48}(ausdruck|begriff)|(defina|traduza|explique).{0,48}(frase|expressão|ter(?:mo))|(정의|번역|설명).{0,16}(문구|표현|용어|“|「)|(عرّف|ترجم|اشرح).{0,32}(العبارة|التعبير|المصطلح)|(परिभाषित|अनुवाद|समझाइए).{0,32}(वाक्यांश|अभिव्यक्ति|शब्द)|(определи|переведи|объясни).{0,48}(фразу|выражение|термин)|(定义|翻译|解释).{0,16}(短语|词语|“|「)|(説明|翻訳).{0,16}(表現|語句|「)|([\"“「][^\"”」]{1,120}[\"”」]).{0,80}(define|translate|explain|설명|정의|번역|اشرح|عرّف|ترجم|समझाइए|परिभाषित|अनुवाद|объясни|определи|переведи|解释|定义|翻译|説明|翻訳))", type: "regex" }, type: "exists" }
  }

  SIGNAL conversation has_answer {
    feature: { source: { role: "assistant", type: "message" }, type: "exists" }
  }

  SIGNAL conversation tool_loop {
    feature: { source: { type: "active_tool_loop" }, type: "exists" }
  }

  SIGNAL conversation tool_required {
    feature: { source: { type: "tool_choice_required" }, type: "exists" }
  }

  SIGNAL conversation flow {
    feature: { source: { type: "flow_tool_state" }, type: "exists" }
  }

  SIGNAL complexity difficulty {
    threshold: 0.08
    description: "Separate direct tasks from analysis and synthesis. Length and language do not determine difficulty."
    hard: { candidates: ["Analyze a production failure from several competing root causes.", "Design a distributed system and justify its consistency tradeoffs.", "Synthesize conflicting evidence into a defensible recommendation.", "分析复杂生产故障中的多个竞争性根因并提出可靠方案。", "Analiza varias causas raíz y sintetiza una recomendación defendible.", "حلّل عدة أسباب جذرية متنافسة وقدّم توصية قابلة للدفاع."] }
    easy: { candidates: ["Give a short definition of a common term.", "Summarize one paragraph in a single sentence.", "Explain a basic concept with one example.", "用一句话解释一个常见概念。", "Explica un concepto cotidiano con un ejemplo.", "اشرح مفهوماً شائعاً بمثال بسيط."] }
  }

  PROJECTION score recovery {
    method: "weighted_sum"
    inputs: [{ type: "user_feedback", weight: 1, name: "wrong_answer" }, { type: "reask", weight: 0.5, name: "repeat" }, { type: "keyword", weight: 0.5, name: "correction" }]
  }

  PROJECTION mapping recovery_band {
    source: "recovery"
    method: "threshold_bands"
    outputs: [{ name: "retry", gte: 1 }]
  }

  # =============================================================================
  # PLUGINS
  # =============================================================================

  PLUGIN request_params request_params {}

  # =============================================================================
  # ROUTES
  # =============================================================================

  ROUTE agent (description = "Plan and execute an explicitly requested workflow, or resume Router-owned Flow state.", on_unknown = "no_match") {
    PRIORITY 400
    WHEN (conversation("flow") OR embedding("workflow_intent") AND keyword("workflow") AND NOT keyword("single") AND NOT conversation("tool_loop") AND NOT structure("quoted_request"))
    ALGORITHM workflows {
      include_intermediate_responses: false
      max_completion_tokens: 2048
      max_parallel: 2
      max_steps: 3
      min_successful_responses: 2
      minimum_candidates: 2
      mode: "dynamic"
      on_error: "skip"
      planner: { max_completion_tokens: 2048 }
      round_timeout_seconds: 180
      template: "micro_agent"
    }
    PLUGIN request_params {
      default_max_tokens: 4096
    }
  }

  ROUTE review (description = "Compare two independent model responses and synthesize them when explicitly requested.", on_unknown = "no_match") {
    PRIORITY 300
    WHEN embedding("review_intent") AND keyword("review") AND NOT keyword("single") AND NOT conversation("tool_loop") AND NOT structure("quoted_request")
    ALGORITHM fusion {
      include_analysis: false
      include_intermediate_responses: false
      max_completion_tokens: 2048
      max_concurrent: 2
      min_successful_responses: 2
      minimum_candidates: 2
      on_error: "skip"
      round_timeout_seconds: 180
    }
    PLUGIN request_params {
      default_max_tokens: 4096
    }
  }

  ROUTE reasoning (description = "Use the strongest reasoning evidence for hard, factual, corrective, or ongoing tool work.", on_unknown = "match") {
    PRIORITY 200
    WHEN (complexity("difficulty:hard") AND NOT keyword("no_analysis") OR (keyword("deliberate") OR keyword("verify")) AND NOT keyword("no_analysis") AND NOT structure("quoted_request") OR projection("retry") AND (conversation("has_answer") OR keyword("correction")) AND NOT structure("quoted_request") OR embedding("consequential") AND fact_check("needs_fact_check") AND (domain("health") OR domain("law") OR domain("business") OR domain("economics")) OR conversation("tool_loop") OR conversation("tool_required"))
    ALGORITHM multi_factor {
      latency_metric: "tpot"
      latency_percentile: 95
      minimum_candidates: 1
      objective: { priorities: [{ factor: "quality", tolerance: 0.02 }, { factor: "latency", tolerance: 0.1 }, { factor: "cost" }, { factor: "load" }], strategy: "lexicographic" }
      on_no_candidates: "fail"
      quality: { index: "vllm-sr/reasoning@1.0.0", on_missing: "exclude" }
    }
    PLUGIN request_params {
      default_max_tokens: 8192
    }
  }

  ROUTE simple (description = "Use a strong single model when extra analysis or orchestration has no explicit benefit.") {
    PRIORITY 10
    ALGORITHM multi_factor {
      latency_metric: "ttft"
      latency_percentile: 95
      minimum_candidates: 1
      objective: { priorities: [{ factor: "quality", tolerance: 0.02 }, { factor: "latency", tolerance: 0.1 }, { factor: "cost" }, { factor: "load" }], strategy: "lexicographic" }
      on_no_candidates: "fail"
      quality: { index: "vllm-sr/general@1.0.0", on_missing: "exclude" }
    }
    PLUGIN request_params {
      default_max_tokens: 8192
    }
  }

}

# =============================================================================
# RECIPE vault
# =============================================================================

RECIPE vault (description = "Keep private traffic inside the assigned deployment boundary, with tools and Router content storage disabled.") {
  # =============================================================================
  # ROUTING PROFILE
  # =============================================================================

  ROUTING {
    candidate_requirements: { capabilities: "declared", context: "known_limits" }
    data_policy: { replay: false }
    strategy: priority
  }

  # =============================================================================
  # SIGNALS
  # =============================================================================

  SIGNAL keyword confidential {
    operator: "OR"
    keywords: ["\\blocal processing only\\b", "\\bdo not send (this|it) to the cloud\\b", "\\bconfidential handling\\b", "\\binternal use only\\b", "\\bprivate repositor(y|ies)\\b", "\\bproprietary code\\b", "\\bdue diligence report\\b", "\\b\\d{3}-\\d{2}-\\d{4}\\b", "本地处理", "不要发到云端", "机密处理", "仅供内部使用", "私有仓库", "内部文档", "solo procesamiento local", "no enviar a la nube", "repositorio privado", "traitement local uniquement", "ne pas envoyer au cloud", "dépôt privé", "ローカル処理のみ", "クラウドに送信しない", "プライベートリポジトリ", "nur lokale verarbeitung", "nicht in die cloud senden", "privates repository", "processamento local apenas", "não enviar para a nuvem", "repositório privado", "로컬 처리만", "클라우드로 보내지 마", "비공개 저장소", "المعالجة المحلية فقط", "لا ترسل إلى السحابة", "مستودع خاص", "केवल स्थानीय प्रसंस्करण", "क्लाउड पर न भेजें", "निजी रिपॉज़िटरी", "только локальная обработка", "не отправлять в облако", "частный репозиторий", "\\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}\\b", "\\b(private|confidential|proprietary)\\s+(?:\\w+\\s+){0,2}(architecture|diagrams?|designs?|documents?|code|data|reports?|files?)\\b", "(私有|私密|机密|保密|专有|内部)(架构|图纸|设计|文档|代码|数据|报告|文件)", "\\b(documentos?|diagramas?|diseños?|datos|informes?|archivos?)\\b.{0,24}\\b(privados?|confidenciales?)\\b", "\\b(documents?|schémas?|données|rapports?|fichiers?)\\b.{0,24}\\b(privés?|confidentiel(?:le)?s?)\\b", "(機密|非公開|社外秘).{0,12}(設計|図面|文書|コード|データ)", "\\b(vertrauliche[nmrs]?|proprietäre[nmrs]?)\\s+(architektur|entwürfe|dokumente|daten|berichte|dateien)\\b", "\\b(documentos?|diagramas?|dados|relatórios?|arquivos?)\\b.{0,24}\\b(privados?|confidenciais)\\b", "(기밀|비공개|내부).{0,12}(설계|문서|코드|데이터|보고서)", "(مستند|تصميم|مخطط|بيانات|تقرير).{0,16}(سري|سرية|خاص|خاصة)", "(गोपनीय|निजी).{0,16}(दस्तावेज|डेटा|रिपोर्ट|डिज़ाइन)", "(конфиденциальн|закрыт|внутренн).{0,20}(документ|данны|отчёт|схем|архитектур)"]
    method: "regex"
  }

  SIGNAL jailbreak prompt_attack {
    threshold: 0.5
    include_history: true
  }

  SIGNAL safety unsafe {
    model: ""
    threshold: 0.5
  }

  SIGNAL pii personal_data {
    threshold: 0.7
    include_history: true
  }

  # =============================================================================
  # PLUGINS
  # =============================================================================

  PLUGIN memory memory {}

  PLUGIN request_params request_params {}

  PLUGIN response_cache response_cache {}

  PLUGIN tools tools {}

  # =============================================================================
  # ROUTES
  # =============================================================================

  ROUTE guard (description = "Decline detected prompt attacks or unsafe requests before calling a backend.", on_unknown = "fail_request") {
    PRIORITY 300
    WHEN (jailbreak("prompt_attack") OR safety("unsafe"))
    PLUGIN fast_response {
      message: "This request cannot be processed under the private routing policy."
    }
    PLUGIN tools {
      enabled: true
      mode: "none"
      strip_tool_history: true
    }
    PLUGIN memory {
      enabled: false
    }
    PLUGIN response_cache {
      enabled: false
    }
    EMIT retention {
      drop: true
    }
  }

  ROUTE sensitive (description = "Use the assigned sensitive-data pool for personal or confidential information.", on_unknown = "fail_request") {
    PRIORITY 200
    WHEN (pii("personal_data") OR keyword("confidential"))
    ALGORITHM multi_factor {
      latency_metric: "ttft"
      latency_percentile: 95
      minimum_candidates: 1
      objective: { priorities: [{ factor: "quality", tolerance: 0.02 }, { factor: "latency", tolerance: 0.1 }, { factor: "load" }], strategy: "lexicographic" }
      on_no_candidates: "fail"
      quality: { index: "vllm-sr/general@1.0.0", on_missing: "exclude" }
    }
    PLUGIN request_params {
      default_max_tokens: 4096
    }
    PLUGIN tools {
      enabled: true
      mode: "none"
      strip_tool_history: true
    }
    PLUGIN memory {
      enabled: false
    }
    PLUGIN response_cache {
      enabled: false
    }
    EMIT retention {
      drop: true
    }
  }

  ROUTE private (description = "Serve ordinary private requests from the approved model pool.") {
    PRIORITY 10
    ALGORITHM multi_factor {
      latency_metric: "ttft"
      latency_percentile: 95
      minimum_candidates: 1
      objective: { priorities: [{ factor: "quality", tolerance: 0.07 }, { factor: "cost", tolerance: 0.05 }, { factor: "latency", tolerance: 0.1 }, { factor: "load" }], strategy: "lexicographic" }
      on_no_candidates: "fail"
      quality: { index: "vllm-sr/general@1.0.0", on_missing: "exclude" }
    }
    PLUGIN request_params {
      default_max_tokens: 4096
    }
    PLUGIN tools {
      enabled: true
      mode: "none"
      strip_tool_history: true
    }
    PLUGIN memory {
      enabled: false
    }
    PLUGIN response_cache {
      enabled: false
    }
    EMIT retention {
      drop: true
    }
  }

}

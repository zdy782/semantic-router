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

  SIGNAL keyword answer_error {
    operator: "OR"
    keywords: ["(answer|response|result|solution|output|calculation|value).{0,64}(wrong|incorrect|erroneous|error|inconsistent|mistake)", "(wrong|incorrect|erroneous|inconsistent).{0,32}(answer|response|result|solution|output|calculation|value)", "(回答|答案|结果|解答|输出|计算|数值).{0,32}(错|不正确|不一致|有误)", "(الإجابة|الجواب|النتيجة|الناتج|الحساب|القيمة).{0,40}(خاط|خطأ|غير صحيح|غير متسق)", "(antwort|ergebnis|lösung|ausgabe|berechnung|wert).{0,48}(falsch|fehler|nicht korrekt|widersprüch)", "(respuesta|resultado|solución|salida|cálculo|valor).{0,48}(incorrect|erróne|error|equivoc|incoherent)", "(回答|答え|結果|解答|出力|計算|値).{0,32}(間違|誤り|誤って|不正確|矛盾)", "(réponse|résultat|solution|calcul).{0,48}(faux|fausse|incorrect|erron|erreur)", "(resposta|resultado|solução|cálculo).{0,48}(errad|incorret|erro|equivoc)", "(답변|답|계산|결과).{0,24}(틀|잘못|오류|맞지)", "(उत्तर|जवाब|गणना|परिणाम).{0,32}(गलत|त्रुटि|अशुद्ध)", "(ответ|решени|расчёт|результат).{0,48}(невер|неправиль|ошиб)"]
    method: "regex"
  }

  SIGNAL keyword answer_revision {
    operator: "OR"
    keywords: ["(?:^|[.!?;,:。！？；，、\\n])\\s*(?:(?:please|then|and|now)\\s+)*(?:(?:I want you to|I would like you to|could you|can you)\\s+)?(?:\\b(correct|fix|revise|replace|recheck|recalculate|recompute|redo|try again|check again)\\b)", "(?:^|[.!?;,:。！？；，、\\n])\\s*(?:请|然后|再|并|接着)*(?:(?:把|将).{0,24})?(?:(请|重新|再).{0,16}(检查|核对|计算|推导|修改|纠正|更正|修正)|纠正|更正|修正|重算|重做)", "(?:^|[.!?;,:。！？；，、\\n])\\s*(?:(?:من فضلك|ثم|رجاء)\\s+)*(?:(صحح|صحّح|صوّب|عدّل|راجع|أعد|اعد).{0,40}(الإجابة|الجواب|النتيجة|الناتج|الحساب|القيمة|حساب|فحص|النظر)|أعد الحساب)", "(?:^|[.!?;,:。！？；，、\\n])\\s*(?:(?:bitte|dann|und|jetzt)\\s+)*(?:(korrigiere|berichtige|überprüfe|prüfe|berechne|überarbeite|wiederhole))", "(?:^|[.!?;,:。！？；，、\\n])\\s*(?:(?:por favor|después|luego|ahora|y)\\s+)*(?:(corrige|corrija|rectifica|revisa|recalcula|vuelve a calcular|comprueba de nuevo))", "(?:^|[.!?;,:。！？；，、\\n])\\s*(?:まず|次に|そして)?(?:(訂正|修正|直して|やり直|再計算|確認して|見直して|検算))", "(?:^|[.!?;,:。！？；，、\\n])\\s*(?:s\\x27il vous plaît[, ]*|s\\x27il te plaît[, ]*|puis\\s+)?(corrigez|corrige|rectifiez|rectifie|recalculez|recalcule)\\b", "(?:^|[.!?;,:。！？；，、\\n])\\s*(?:por favor[, ]*)?(corrija|corrige|corrigir|retifique|recalcule)\\b", "(?:^|[.!?;,:。！？；，、\\n])\\s*(?:제발\\s*|다시\\s*)?(?:답변을\\s*|답을\\s*|결과를\\s*)?(수정|정정|고쳐|바로잡)", "(?:^|[.!?;,:।\\n])\\s*(?:कृपया\\s*)?(?:इसे\\s*|उत्तर\\s*|जवाब\\s*)?(सुधारें|सुधारो|सही करें|ठीक करें)", "(?:^|[.!?;,:。！？；，、\\n])\\s*(?:пожалуйста[, ]*)?(исправь|исправьте|скорректируй|скорректируйте|пересчитай|пересчитайте)"]
    method: "regex"
  }

  SIGNAL keyword no_revision {
    operator: "OR"
    keywords: ["(do not|don't|never).{0,24}(correct|fix|revise|replace|recheck|recalculate|redo)", "(不要|无需|不必).{0,12}(纠正|更正|修正|修改|重算|重做|核对)", "لا.{0,12}(تصحح|تعدّل|تعدل|تراجع|تعد الحساب)", "(nicht|keinesfalls).{0,24}(korrigieren|berichtigen|überarbeiten|ändern)|korrigiere.{0,24}nicht", "no.{0,12}(corrijas|corrija|rectifiques|revises|recalcules)", "(訂正|修正|変更|再計算).{0,8}(しないで|不要)|直さないで", "不要.{0,12}(重新检查|重新计算|检查|计算)|别.{0,12}(纠正|修正|重算)", "لا.{0,12}(تصحّح|تراجع|تعد حساب|تعد فحص)", "(prüfe|überprüfe|berechne|überarbeite|berichtige).{0,24}nicht", "no.{0,12}(corrijas|rectifiques|revises|recalcules|vuelvas a calcular)", "(やり直さない|見直さない|確認しない|再計算しない)", "ne.{0,24}(corrige|rectifie|recalcule).{0,16}pas", "não.{0,16}(corrija|corrige|corrigir|retifique|recalcule)", "(수정|정정|고치|고쳐|바로잡).{0,12}(하지 마|지 마|말아|필요 없)", "(सुधार|सही|ठीक).{0,12}(न करें|मत करो|मत करें)|मत.{0,12}(सुधार|करो)", "(?:^|[\\s.!?;,:])не\\s+(исправ|корректир|пересчит)"]
    method: "regex"
  }

  SIGNAL embedding consequential {
    prototype_scoring: { best_weight: 0.75, enabled: false, top_m: 2 }
    threshold: 0.7
    candidates: ["Help choose an action when a mistaken choice could cause material harm or an irreversible loss.", "Evaluate practical alternatives and recommend a course of action while accounting for consequential uncertainty.", "当错误选择可能造成实质伤害或不可逆损失时，帮助选择行动。", "评估现实可行的方案，并在考虑重大不确定性的基础上建议行动路线。", "ساعد في اختيار تصرف عندما قد يؤدي القرار الخاطئ إلى ضرر ملموس أو خسارة لا يمكن تداركها.", "قيّم البدائل العملية واقترح مساراً للعمل مع مراعاة عدم اليقين ذي العواقب المهمة.", "Hilf bei der Wahl einer Handlung, wenn eine falsche Entscheidung erheblichen Schaden oder einen unumkehrbaren Verlust verursachen könnte.", "Bewerte praktische Alternativen und empfehle ein Vorgehen unter Berücksichtigung folgenreicher Unsicherheit.", "Ayuda a elegir una acción cuando una decisión equivocada podría causar un daño importante o una pérdida irreversible.", "Evalúa alternativas prácticas y recomienda una línea de acción teniendo en cuenta la incertidumbre y sus consecuencias.", "誤った選択が重大な被害や取り返しのつかない損失を招く可能性があるとき、行動の選択を支援してください。", "現実的な選択肢を評価し、重大な結果につながる不確実性を考慮して行動方針を勧めてください。"]
    aggregation_method: "max"
  }

  SIGNAL embedding informational {
    prototype_scoring: { best_weight: 0.75, enabled: false, top_m: 2 }
    threshold: 0.7
    candidates: ["Explain the meaning of a concept neutrally without advising anyone to act.", "Describe background information for learning or quotation, without making a practical recommendation.", "客观解释一个概念的含义，不建议任何人采取行动。", "介绍用于学习或引用的背景信息，不提供现实行动建议。", "اشرح معنى مفهوم بشكل محايد من دون أن تنصح أحداً باتخاذ إجراء.", "قدّم معلومات خلفية للتعلم أو الاقتباس من دون تقديم توصية عملية.", "Erkläre die Bedeutung eines Begriffs neutral, ohne jemandem zu einer Handlung zu raten.", "Beschreibe Hintergrundinformationen zum Lernen oder Zitieren, ohne eine praktische Empfehlung zu geben.", "Explica el significado de un concepto de forma neutral sin aconsejar a nadie que actúe.", "Describe información de contexto para aprender o citar, sin hacer una recomendación práctica.", "誰かに行動を勧めることなく、概念の意味を中立的に説明してください。", "学習や引用のための背景情報を説明し、実際の行動については助言しないでください。"]
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
    feature: { source: { pattern: "(?i)(?:(\\b(define|translate|explain)\\b.{0,48}\\b(phrase|term|expression)\\b|(définis|traduis|explique).{0,48}(expression|terme)|(define|traduce|explica).{0,48}(frase|expresión|término)|(definiere|übersetze|erkläre).{0,48}(ausdruck|begriff)|(defina|traduza|explique).{0,48}(frase|expressão|ter(?:mo))|(정의|번역|설명).{0,16}(문구|표현|용어|“|「)|(عرّف|ترجم|اشرح).{0,32}(العبارة|التعبير|المصطلح)|(परिभाषित|अनुवाद|समझाइए).{0,32}(वाक्यांश|अभिव्यक्ति|शब्द)|(определи|переведи|объясни).{0,48}(фразу|выражение|термин)|(定义|翻译|解释).{0,16}(短语|词语|“|「)|(説明|翻訳).{0,16}(表現|語句|「)|([\"“「][^\"”」]{1,120}[\"”」]).{0,80}(define|translate|explain|설명|정의|번역|اشرح|عرّف|ترجم|समझाइए|परिभाषित|अनुवाद|объясни|определи|переведи|解释|定义|翻译|説明|翻訳))|(?:^|[.!?;。！？；\\n])\\s*(?:please\\s+)?(?:translate|quote)\\b[^.!?;:\\n]{0,64}[:：]|(?:^|[.!?;。！？；\\n])\\s*(?:请)?(?:翻译|引用)[^。！？；：\\n]{0,32}[:：]|(?:^|[.!?;。！？；\\n])\\s*(?:(?:من فضلك|رجاء)\\s+)?(?:ترجم|اقتبس)[^.!?؛:\\n]{0,48}[:：]|(?:^|[.!?;。！？；\\n])\\s*(?:bitte\\s+)?(?:übersetze|zitiere)\\b[^.!?;:\\n]{0,64}[:：]|(?:^|[.!?;。！？；\\n])\\s*(?:por favor\\s+)?(?:traduce|cita)\\b[^.!?;:\\n]{0,64}[:：]|(?:^|[.!?;。！？；\\n])\\s*(?:以下を|次を)?(?:翻訳|引用)(?:して(?:ください)?)?[:：])", type: "regex" }, type: "exists" }
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
    prototype_scoring: { best_weight: 0.75, enabled: false, top_m: 2 }
    threshold: 0.08
    description: "Separate direct tasks from analysis and synthesis. Length and language do not determine difficulty."
    hard: { candidates: ["Find an outcome satisfying interacting constraints and justify why the nearest alternatives fail.", "Reconcile conflicting evidence, identify unsupported assumptions, and defend a conclusion under uncertainty.", "Design a multi-stage solution whose intermediate choices remain consistent with the final objective.", "找出满足相互影响的约束的结果，并说明最接近的其他方案为何不成立。", "协调冲突的证据，识别没有依据的假设，并在不确定性下论证结论。", "设计一个多阶段方案，使中间选择始终与最终目标一致。", "أوجد نتيجة تحقق قيوداً متفاعلة، وبيّن لماذا لا تصلح البدائل الأقرب.", "وفّق بين الأدلة المتعارضة، وحدد الافتراضات غير المدعومة، ودافع عن استنتاج في ظل عدم اليقين.", "صمّم حلاً متعدد المراحل تبقى خياراته الوسيطة متسقة مع الهدف النهائي.", "Finde ein Ergebnis, das zusammenwirkende Bedingungen erfüllt, und begründe, warum die nächstliegenden Alternativen scheitern.", "Gleiche widersprüchliche Belege ab, erkenne unbelegte Annahmen und verteidige eine Schlussfolgerung unter Unsicherheit.", "Entwirf eine mehrstufige Lösung, deren Zwischenentscheidungen mit dem Endziel vereinbar bleiben.", "Encuentra un resultado que satisfaga restricciones interdependientes y justifica por qué fallan las alternativas más cercanas.", "Concilia pruebas contradictorias, identifica supuestos sin fundamento y defiende una conclusión ante la incertidumbre.", "Diseña una solución de varias etapas cuyas decisiones intermedias sigan siendo coherentes con el objetivo final.", "相互に影響する制約を満たす結果を見つけ、近い代替案が成立しない理由を示してください。", "矛盾する証拠を整理し、裏付けのない仮定を特定して、不確実な状況でも結論を論証してください。", "中間の選択が最終目標と一貫する、多段階の解決策を設計してください。"] }
    easy: { candidates: ["Copy explicitly supplied information into the requested structure without adding an inference.", "Apply one local edit while preserving the meaning and all other stated details.", "Retrieve a directly stated fact and give a concise answer without combining separate arguments.", "把明确提供的信息复制到指定结构中，不添加推断。", "只做一处局部修改，保留原意以及所有其他已述细节。", "提取直接陈述的事实，简洁作答，不合并不同论证。", "انسخ المعلومات المقدمة صراحةً إلى البنية المطلوبة من دون إضافة استنتاج.", "أجر تعديلاً موضعياً واحداً مع الحفاظ على المعنى وجميع التفاصيل الأخرى المذكورة.", "استخرج حقيقة مذكورة مباشرةً وقدّم إجابة موجزة من دون دمج حجج منفصلة.", "Übertrage ausdrücklich bereitgestellte Informationen in die verlangte Struktur, ohne eine Schlussfolgerung hinzuzufügen.", "Nimm eine einzige lokale Änderung vor und erhalte dabei die Bedeutung und alle anderen genannten Einzelheiten.", "Entnimm eine direkt genannte Tatsache und antworte knapp, ohne getrennte Argumente zu verbinden.", "Copia la información proporcionada explícitamente en la estructura solicitada sin añadir inferencias.", "Aplica una sola modificación local conservando el significado y todos los demás detalles indicados.", "Extrae un hecho expresado directamente y responde de forma concisa sin combinar argumentos separados.", "明示された情報を指定の構造にそのまま移し、推論を加えないでください。", "意味と他のすべての記載事項を保ちながら、一か所だけ修正してください。", "直接述べられた事実を取り出し、別々の論点を組み合わせずに簡潔に答えてください。"] }
  }

  PROJECTION score recovery {
    method: "weighted_sum"
    inputs: [{ type: "user_feedback", weight: 1, name: "wrong_answer" }, { type: "reask", weight: 0.5, name: "repeat" }, { type: "keyword", weight: 0.5, name: "correction" }]
  }

  PROJECTION score care_margin {
    method: "weighted_sum"
    inputs: [{ type: "embedding", weight: 1, name: "consequential", value_source: "raw" }, { type: "embedding", weight: -1, name: "informational", value_source: "raw" }]
  }

  PROJECTION mapping recovery_band {
    source: "recovery"
    method: "threshold_bands"
    outputs: [{ name: "retry", gte: 1 }]
  }

  PROJECTION mapping care_margin_direction {
    source: "care_margin"
    method: "threshold_bands"
    outputs: [{ name: "actionable_care", gt: 0 }]
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
    WHEN (complexity("difficulty:hard") AND NOT keyword("no_analysis") OR (keyword("deliberate") OR keyword("verify")) AND NOT keyword("no_analysis") AND NOT structure("quoted_request") OR conversation("has_answer") AND projection("retry") AND NOT structure("quoted_request") OR projection("actionable_care") AND (fact_check("needs_fact_check") OR domain("health") OR domain("law") OR domain("business") OR domain("economics")) OR keyword("answer_error") AND keyword("answer_revision") AND NOT keyword("no_revision") AND NOT structure("quoted_request"))
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
    WHEN complexity("difficulty:easy") AND NOT conversation("has_answer") AND NOT conversation("tool_loop") AND NOT conversation("tool_required") AND NOT (projection("actionable_care") AND (fact_check("needs_fact_check") OR domain("health") OR domain("law") OR domain("business") OR domain("economics")))
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
    feature: { source: { pattern: "(?i)(?:(\\b(define|translate|explain)\\b.{0,48}\\b(phrase|term|expression)\\b|(définis|traduis|explique).{0,48}(expression|terme)|(define|traduce|explica).{0,48}(frase|expresión|término)|(definiere|übersetze|erkläre).{0,48}(ausdruck|begriff)|(defina|traduza|explique).{0,48}(frase|expressão|ter(?:mo))|(정의|번역|설명).{0,16}(문구|표현|용어|“|「)|(عرّف|ترجم|اشرح).{0,32}(العبارة|التعبير|المصطلح)|(परिभाषित|अनुवाद|समझाइए).{0,32}(वाक्यांश|अभिव्यक्ति|शब्द)|(определи|переведи|объясни).{0,48}(фразу|выражение|термин)|(定义|翻译|解释).{0,16}(短语|词语|“|「)|(説明|翻訳).{0,16}(表現|語句|「)|([\"“「][^\"”」]{1,120}[\"”」]).{0,80}(define|translate|explain|설명|정의|번역|اشرح|عرّف|ترجم|समझाइए|परिभाषित|अनुवाद|объясни|определи|переведи|解释|定义|翻译|説明|翻訳))|(?:^|[.!?;。！？；\\n])\\s*(?:please\\s+)?(?:translate|quote)\\b[^.!?;:\\n]{0,64}[:：]|(?:^|[.!?;。！？；\\n])\\s*(?:请)?(?:翻译|引用)[^。！？；：\\n]{0,32}[:：]|(?:^|[.!?;。！？；\\n])\\s*(?:(?:من فضلك|رجاء)\\s+)?(?:ترجم|اقتبس)[^.!?؛:\\n]{0,48}[:：]|(?:^|[.!?;。！？；\\n])\\s*(?:bitte\\s+)?(?:übersetze|zitiere)\\b[^.!?;:\\n]{0,64}[:：]|(?:^|[.!?;。！？；\\n])\\s*(?:por favor\\s+)?(?:traduce|cita)\\b[^.!?;:\\n]{0,64}[:：]|(?:^|[.!?;。！？；\\n])\\s*(?:以下を|次を)?(?:翻訳|引用)(?:して(?:ください)?)?[:：])", type: "regex" }, type: "exists" }
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
    prototype_scoring: { best_weight: 0.75, enabled: false, top_m: 2 }
    threshold: 0.08
    description: "Separate direct tasks from analysis and synthesis. Length and language do not determine difficulty."
    hard: { candidates: ["Find an outcome satisfying interacting constraints and justify why the nearest alternatives fail.", "Reconcile conflicting evidence, identify unsupported assumptions, and defend a conclusion under uncertainty.", "Design a multi-stage solution whose intermediate choices remain consistent with the final objective.", "找出满足相互影响的约束的结果，并说明最接近的其他方案为何不成立。", "协调冲突的证据，识别没有依据的假设，并在不确定性下论证结论。", "设计一个多阶段方案，使中间选择始终与最终目标一致。", "أوجد نتيجة تحقق قيوداً متفاعلة، وبيّن لماذا لا تصلح البدائل الأقرب.", "وفّق بين الأدلة المتعارضة، وحدد الافتراضات غير المدعومة، ودافع عن استنتاج في ظل عدم اليقين.", "صمّم حلاً متعدد المراحل تبقى خياراته الوسيطة متسقة مع الهدف النهائي.", "Finde ein Ergebnis, das zusammenwirkende Bedingungen erfüllt, und begründe, warum die nächstliegenden Alternativen scheitern.", "Gleiche widersprüchliche Belege ab, erkenne unbelegte Annahmen und verteidige eine Schlussfolgerung unter Unsicherheit.", "Entwirf eine mehrstufige Lösung, deren Zwischenentscheidungen mit dem Endziel vereinbar bleiben.", "Encuentra un resultado que satisfaga restricciones interdependientes y justifica por qué fallan las alternativas más cercanas.", "Concilia pruebas contradictorias, identifica supuestos sin fundamento y defiende una conclusión ante la incertidumbre.", "Diseña una solución de varias etapas cuyas decisiones intermedias sigan siendo coherentes con el objetivo final.", "相互に影響する制約を満たす結果を見つけ、近い代替案が成立しない理由を示してください。", "矛盾する証拠を整理し、裏付けのない仮定を特定して、不確実な状況でも結論を論証してください。", "中間の選択が最終目標と一貫する、多段階の解決策を設計してください。"] }
    easy: { candidates: ["Copy explicitly supplied information into the requested structure without adding an inference.", "Apply one local edit while preserving the meaning and all other stated details.", "Retrieve a directly stated fact and give a concise answer without combining separate arguments.", "把明确提供的信息复制到指定结构中，不添加推断。", "只做一处局部修改，保留原意以及所有其他已述细节。", "提取直接陈述的事实，简洁作答，不合并不同论证。", "انسخ المعلومات المقدمة صراحةً إلى البنية المطلوبة من دون إضافة استنتاج.", "أجر تعديلاً موضعياً واحداً مع الحفاظ على المعنى وجميع التفاصيل الأخرى المذكورة.", "استخرج حقيقة مذكورة مباشرةً وقدّم إجابة موجزة من دون دمج حجج منفصلة.", "Übertrage ausdrücklich bereitgestellte Informationen in die verlangte Struktur, ohne eine Schlussfolgerung hinzuzufügen.", "Nimm eine einzige lokale Änderung vor und erhalte dabei die Bedeutung und alle anderen genannten Einzelheiten.", "Entnimm eine direkt genannte Tatsache und antworte knapp, ohne getrennte Argumente zu verbinden.", "Copia la información proporcionada explícitamente en la estructura solicitada sin añadir inferencias.", "Aplica una sola modificación local conservando el significado y todos los demás detalles indicados.", "Extrae un hecho expresado directamente y responde de forma concisa sin combinar argumentos separados.", "明示された情報を指定の構造にそのまま移し、推論を加えないでください。", "意味と他のすべての記載事項を保ちながら、一か所だけ修正してください。", "直接述べられた事実を取り出し、別々の論点を組み合わせずに簡潔に答えてください。"] }
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

  SIGNAL keyword answer_error {
    operator: "OR"
    keywords: ["(answer|response|result|solution|output|calculation|value).{0,64}(wrong|incorrect|erroneous|error|inconsistent|mistake)", "(wrong|incorrect|erroneous|inconsistent).{0,32}(answer|response|result|solution|output|calculation|value)", "(回答|答案|结果|解答|输出|计算|数值).{0,32}(错|不正确|不一致|有误)", "(الإجابة|الجواب|النتيجة|الناتج|الحساب|القيمة).{0,40}(خاط|خطأ|غير صحيح|غير متسق)", "(antwort|ergebnis|lösung|ausgabe|berechnung|wert).{0,48}(falsch|fehler|nicht korrekt|widersprüch)", "(respuesta|resultado|solución|salida|cálculo|valor).{0,48}(incorrect|erróne|error|equivoc|incoherent)", "(回答|答え|結果|解答|出力|計算|値).{0,32}(間違|誤り|誤って|不正確|矛盾)", "(réponse|résultat|solution|calcul).{0,48}(faux|fausse|incorrect|erron|erreur)", "(resposta|resultado|solução|cálculo).{0,48}(errad|incorret|erro|equivoc)", "(답변|답|계산|결과).{0,24}(틀|잘못|오류|맞지)", "(उत्तर|जवाब|गणना|परिणाम).{0,32}(गलत|त्रुटि|अशुद्ध)", "(ответ|решени|расчёт|результат).{0,48}(невер|неправиль|ошиб)"]
    method: "regex"
  }

  SIGNAL keyword answer_revision {
    operator: "OR"
    keywords: ["(?:^|[.!?;,:。！？；，、\\n])\\s*(?:(?:please|then|and|now)\\s+)*(?:(?:I want you to|I would like you to|could you|can you)\\s+)?(?:\\b(correct|fix|revise|replace|recheck|recalculate|recompute|redo|try again|check again)\\b)", "(?:^|[.!?;,:。！？；，、\\n])\\s*(?:请|然后|再|并|接着)*(?:(?:把|将).{0,24})?(?:(请|重新|再).{0,16}(检查|核对|计算|推导|修改|纠正|更正|修正)|纠正|更正|修正|重算|重做)", "(?:^|[.!?;,:。！？；，、\\n])\\s*(?:(?:من فضلك|ثم|رجاء)\\s+)*(?:(صحح|صحّح|صوّب|عدّل|راجع|أعد|اعد).{0,40}(الإجابة|الجواب|النتيجة|الناتج|الحساب|القيمة|حساب|فحص|النظر)|أعد الحساب)", "(?:^|[.!?;,:。！？；，、\\n])\\s*(?:(?:bitte|dann|und|jetzt)\\s+)*(?:(korrigiere|berichtige|überprüfe|prüfe|berechne|überarbeite|wiederhole))", "(?:^|[.!?;,:。！？；，、\\n])\\s*(?:(?:por favor|después|luego|ahora|y)\\s+)*(?:(corrige|corrija|rectifica|revisa|recalcula|vuelve a calcular|comprueba de nuevo))", "(?:^|[.!?;,:。！？；，、\\n])\\s*(?:まず|次に|そして)?(?:(訂正|修正|直して|やり直|再計算|確認して|見直して|検算))", "(?:^|[.!?;,:。！？；，、\\n])\\s*(?:s\\x27il vous plaît[, ]*|s\\x27il te plaît[, ]*|puis\\s+)?(corrigez|corrige|rectifiez|rectifie|recalculez|recalcule)\\b", "(?:^|[.!?;,:。！？；，、\\n])\\s*(?:por favor[, ]*)?(corrija|corrige|corrigir|retifique|recalcule)\\b", "(?:^|[.!?;,:。！？；，、\\n])\\s*(?:제발\\s*|다시\\s*)?(?:답변을\\s*|답을\\s*|결과를\\s*)?(수정|정정|고쳐|바로잡)", "(?:^|[.!?;,:।\\n])\\s*(?:कृपया\\s*)?(?:इसे\\s*|उत्तर\\s*|जवाब\\s*)?(सुधारें|सुधारो|सही करें|ठीक करें)", "(?:^|[.!?;,:。！？；，、\\n])\\s*(?:пожалуйста[, ]*)?(исправь|исправьте|скорректируй|скорректируйте|пересчитай|пересчитайте)"]
    method: "regex"
  }

  SIGNAL keyword no_revision {
    operator: "OR"
    keywords: ["(do not|don't|never).{0,24}(correct|fix|revise|replace|recheck|recalculate|redo)", "(不要|无需|不必).{0,12}(纠正|更正|修正|修改|重算|重做|核对)", "لا.{0,12}(تصحح|تعدّل|تعدل|تراجع|تعد الحساب)", "(nicht|keinesfalls).{0,24}(korrigieren|berichtigen|überarbeiten|ändern)|korrigiere.{0,24}nicht", "no.{0,12}(corrijas|corrija|rectifiques|revises|recalcules)", "(訂正|修正|変更|再計算).{0,8}(しないで|不要)|直さないで", "不要.{0,12}(重新检查|重新计算|检查|计算)|别.{0,12}(纠正|修正|重算)", "لا.{0,12}(تصحّح|تراجع|تعد حساب|تعد فحص)", "(prüfe|überprüfe|berechne|überarbeite|berichtige).{0,24}nicht", "no.{0,12}(corrijas|rectifiques|revises|recalcules|vuelvas a calcular)", "(やり直さない|見直さない|確認しない|再計算しない)", "ne.{0,24}(corrige|rectifie|recalcule).{0,16}pas", "não.{0,16}(corrija|corrige|corrigir|retifique|recalcule)", "(수정|정정|고치|고쳐|바로잡).{0,12}(하지 마|지 마|말아|필요 없)", "(सुधार|सही|ठीक).{0,12}(न करें|मत करो|मत करें)|मत.{0,12}(सुधार|करो)", "(?:^|[\\s.!?;,:])не\\s+(исправ|корректир|пересчит)"]
    method: "regex"
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
    feature: { source: { pattern: "(?i)(?:(\\b(define|translate|explain)\\b.{0,48}\\b(phrase|term|expression)\\b|(définis|traduis|explique).{0,48}(expression|terme)|(define|traduce|explica).{0,48}(frase|expresión|término)|(definiere|übersetze|erkläre).{0,48}(ausdruck|begriff)|(defina|traduza|explique).{0,48}(frase|expressão|ter(?:mo))|(정의|번역|설명).{0,16}(문구|표현|용어|“|「)|(عرّف|ترجم|اشرح).{0,32}(العبارة|التعبير|المصطلح)|(परिभाषित|अनुवाद|समझाइए).{0,32}(वाक्यांश|अभिव्यक्ति|शब्द)|(определи|переведи|объясни).{0,48}(фразу|выражение|термин)|(定义|翻译|解释).{0,16}(短语|词语|“|「)|(説明|翻訳).{0,16}(表現|語句|「)|([\"“「][^\"”」]{1,120}[\"”」]).{0,80}(define|translate|explain|설명|정의|번역|اشرح|عرّف|ترجم|समझाइए|परिभाषित|अनुवाद|объясни|определи|переведи|解释|定义|翻译|説明|翻訳))|(?:^|[.!?;。！？；\\n])\\s*(?:please\\s+)?(?:translate|quote)\\b[^.!?;:\\n]{0,64}[:：]|(?:^|[.!?;。！？；\\n])\\s*(?:请)?(?:翻译|引用)[^。！？；：\\n]{0,32}[:：]|(?:^|[.!?;。！？；\\n])\\s*(?:(?:من فضلك|رجاء)\\s+)?(?:ترجم|اقتبس)[^.!?؛:\\n]{0,48}[:：]|(?:^|[.!?;。！？；\\n])\\s*(?:bitte\\s+)?(?:übersetze|zitiere)\\b[^.!?;:\\n]{0,64}[:：]|(?:^|[.!?;。！？；\\n])\\s*(?:por favor\\s+)?(?:traduce|cita)\\b[^.!?;:\\n]{0,64}[:：]|(?:^|[.!?;。！？；\\n])\\s*(?:以下を|次を)?(?:翻訳|引用)(?:して(?:ください)?)?[:：])", type: "regex" }, type: "exists" }
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
    prototype_scoring: { best_weight: 0.75, enabled: false, top_m: 2 }
    threshold: 0.08
    description: "Separate direct tasks from analysis and synthesis. Length and language do not determine difficulty."
    hard: { candidates: ["Find an outcome satisfying interacting constraints and justify why the nearest alternatives fail.", "Reconcile conflicting evidence, identify unsupported assumptions, and defend a conclusion under uncertainty.", "Design a multi-stage solution whose intermediate choices remain consistent with the final objective.", "找出满足相互影响的约束的结果，并说明最接近的其他方案为何不成立。", "协调冲突的证据，识别没有依据的假设，并在不确定性下论证结论。", "设计一个多阶段方案，使中间选择始终与最终目标一致。", "أوجد نتيجة تحقق قيوداً متفاعلة، وبيّن لماذا لا تصلح البدائل الأقرب.", "وفّق بين الأدلة المتعارضة، وحدد الافتراضات غير المدعومة، ودافع عن استنتاج في ظل عدم اليقين.", "صمّم حلاً متعدد المراحل تبقى خياراته الوسيطة متسقة مع الهدف النهائي.", "Finde ein Ergebnis, das zusammenwirkende Bedingungen erfüllt, und begründe, warum die nächstliegenden Alternativen scheitern.", "Gleiche widersprüchliche Belege ab, erkenne unbelegte Annahmen und verteidige eine Schlussfolgerung unter Unsicherheit.", "Entwirf eine mehrstufige Lösung, deren Zwischenentscheidungen mit dem Endziel vereinbar bleiben.", "Encuentra un resultado que satisfaga restricciones interdependientes y justifica por qué fallan las alternativas más cercanas.", "Concilia pruebas contradictorias, identifica supuestos sin fundamento y defiende una conclusión ante la incertidumbre.", "Diseña una solución de varias etapas cuyas decisiones intermedias sigan siendo coherentes con el objetivo final.", "相互に影響する制約を満たす結果を見つけ、近い代替案が成立しない理由を示してください。", "矛盾する証拠を整理し、裏付けのない仮定を特定して、不確実な状況でも結論を論証してください。", "中間の選択が最終目標と一貫する、多段階の解決策を設計してください。"] }
    easy: { candidates: ["Copy explicitly supplied information into the requested structure without adding an inference.", "Apply one local edit while preserving the meaning and all other stated details.", "Retrieve a directly stated fact and give a concise answer without combining separate arguments.", "把明确提供的信息复制到指定结构中，不添加推断。", "只做一处局部修改，保留原意以及所有其他已述细节。", "提取直接陈述的事实，简洁作答，不合并不同论证。", "انسخ المعلومات المقدمة صراحةً إلى البنية المطلوبة من دون إضافة استنتاج.", "أجر تعديلاً موضعياً واحداً مع الحفاظ على المعنى وجميع التفاصيل الأخرى المذكورة.", "استخرج حقيقة مذكورة مباشرةً وقدّم إجابة موجزة من دون دمج حجج منفصلة.", "Übertrage ausdrücklich bereitgestellte Informationen in die verlangte Struktur, ohne eine Schlussfolgerung hinzuzufügen.", "Nimm eine einzige lokale Änderung vor und erhalte dabei die Bedeutung und alle anderen genannten Einzelheiten.", "Entnimm eine direkt genannte Tatsache und antworte knapp, ohne getrennte Argumente zu verbinden.", "Copia la información proporcionada explícitamente en la estructura solicitada sin añadir inferencias.", "Aplica una sola modificación local conservando el significado y todos los demás detalles indicados.", "Extrae un hecho expresado directamente y responde de forma concisa sin combinar argumentos separados.", "明示された情報を指定の構造にそのまま移し、推論を加えないでください。", "意味と他のすべての記載事項を保ちながら、一か所だけ修正してください。", "直接述べられた事実を取り出し、別々の論点を組み合わせずに簡潔に答えてください。"] }
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
    WHEN (complexity("difficulty:hard") AND NOT keyword("no_analysis") OR (keyword("deliberate") OR keyword("verify")) AND NOT keyword("no_analysis") AND NOT structure("quoted_request") OR conversation("has_answer") AND projection("retry") AND NOT structure("quoted_request") OR keyword("answer_error") AND keyword("answer_revision") AND NOT keyword("no_revision") AND NOT structure("quoted_request"))
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
    keywords: ["\\b(one|single) model\\b", "\\b(no|without) parallel (models?|orchestration)\\b", "单个模型", "一个模型", "不要并行", "un seul modèle", "un solo modelo", "ein einzelnes modell", "um único modelo", "単一モデル", "하나의 모델", "نموذج واحد", "одной модели", "(do not|don't|without|no).{0,24}(multiple|several|parallel|independent).{0,24}(models|agents|workers|reviewers)", "(不要|不使用|无需).{0,12}(多个模型|多模型|多个智能体|并行|独立评审)", "لا.{0,16}(تستخدم|تستدع|تفوض).{0,20}(عدة|نماذج|وكلاء)", "(keine|ohne|nicht).{0,20}(mehreren|mehrere|parallelen|parallele).{0,16}(modelle|agenten|prüfer)", "(no|sin).{0,16}(varios|varias|múltiples|paralelos).{0,16}(modelos|agentes|revisores)", "(複数のモデル|複数モデル|複数のエージェント|並列).{0,12}(使わない|使用しない|不要)|並行させない", "\\b(do not|don't|never|without)\\b.{0,24}\\b(use|ask|consult|delegate|assign|coordinate)?\\b.{0,16}\\b(two|three|multiple|several|independent)\\b.{0,24}\\b(models|agents|workers|reviewers|experts)\\b", "(不要|别|不必|无需).{0,16}(两|三|多个|不同|独立).{0,12}(模型|智能体|评审|专家)", "لا.{0,16}(تستخدم|تطلب|تستشر|تستدع|تفوض|توزع).{0,24}(نموذجين|وكيلين|نماذج|وكلاء|مراجعين|خبراء)", "(verwende|nutze|frage|befrage|delegiere).{0,24}(keine|nicht).{0,24}(zwei|drei|mehrere|unabhängige).{0,16}(modelle|agenten|prüfer|experten)", "no.{0,16}(uses|utilices|pidas|consultes|delegues).{0,24}(dos|tres|varios|múltiples|independientes).{0,16}(modelos|agentes|revisores|expertos)", "(二つ|三つ|別々|複数).{0,12}(モデル|エージェント|専門家).{0,16}(使わない|使用しない|頼まない|依頼しない|求めない)"]
    method: "regex"
  }

  SIGNAL keyword workflow {
    operator: "OR"
    keywords: ["break this into independent workstreams", "\\bbreak\\b.{0,160}\\bindependent workstreams\\b", "\\b(using?|with) tools?\\b.{0,160}\\bworkstreams\\b", "investigate, plan, and implement", "use tools to gather evidence and execute", "分解为独立工作流", "调查、规划并实现", "investigar, planificar e implementar", "enquêter, planifier et implémenter", "調査、計画、実装", "untersuchen, planen und implementieren", "investigar, planejar e implementar", "조사하고 계획하고 구현", "التحقيق والتخطيط والتنفيذ", "जाँच, योजना और कार्यान्वयन", "исследовать, спланировать и реализовать", "(delegate|workstreams|coordinat|multi.stage|subtasks|分派|委派|工作流|协调|多阶段|فوّض|فوض|نسّق|نسق|مراحل|delegier|arbeitsschritte|koordini|delega|etapas|coordina|分担|委任|多段階|連携)"]
    method: "regex"
  }

  SIGNAL keyword review {
    operator: "OR"
    keywords: ["independent expert opinions", "compare competing hypotheses", "adversarial debate and verdict", "比较多个假设并得出结论", "独立专家意见", "comparar hipótesis contrapuestas", "comparer des hypothèses concurrentes", "複数の仮説を比較", "konkurrierende hypothesen vergleichen", "comparar hipóteses concorrentes", "경쟁 가설을 비교", "قارن الفرضيات المتنافسة", "प्रतिस्पर्धी परिकल्पनाओं की तुलना", "сравнить конкурирующие гипотезы", "\\b(ask|consult)\\b.{0,40}\\bindependent experts?\\b", "(independent.{0,40}(answer|review|assessment)|separate.{0,32}(answer|review)|独立.{0,20}(答案|评审|评估)|مستقل.{0,32}(إجاب|تقييم)|unabhängig.{0,40}(antwort|beurteil)|independiente.{0,40}(respuesta|evaluación)|独立.{0,20}(回答|評価))"]
    method: "regex"
  }

  SIGNAL keyword answer_error {
    operator: "OR"
    keywords: ["(answer|response|result|solution|output|calculation|value).{0,64}(wrong|incorrect|erroneous|error|inconsistent|mistake)", "(wrong|incorrect|erroneous|inconsistent).{0,32}(answer|response|result|solution|output|calculation|value)", "(回答|答案|结果|解答|输出|计算|数值).{0,32}(错|不正确|不一致|有误)", "(الإجابة|الجواب|النتيجة|الناتج|الحساب|القيمة).{0,40}(خاط|خطأ|غير صحيح|غير متسق)", "(antwort|ergebnis|lösung|ausgabe|berechnung|wert).{0,48}(falsch|fehler|nicht korrekt|widersprüch)", "(respuesta|resultado|solución|salida|cálculo|valor).{0,48}(incorrect|erróne|error|equivoc|incoherent)", "(回答|答え|結果|解答|出力|計算|値).{0,32}(間違|誤り|誤って|不正確|矛盾)", "(réponse|résultat|solution|calcul).{0,48}(faux|fausse|incorrect|erron|erreur)", "(resposta|resultado|solução|cálculo).{0,48}(errad|incorret|erro|equivoc)", "(답변|답|계산|결과).{0,24}(틀|잘못|오류|맞지)", "(उत्तर|जवाब|गणना|परिणाम).{0,32}(गलत|त्रुटि|अशुद्ध)", "(ответ|решени|расчёт|результат).{0,48}(невер|неправиль|ошиб)"]
    method: "regex"
  }

  SIGNAL keyword answer_revision {
    operator: "OR"
    keywords: ["(?:^|[.!?;,:。！？；，、\\n])\\s*(?:(?:please|then|and|now)\\s+)*(?:(?:I want you to|I would like you to|could you|can you)\\s+)?(?:\\b(correct|fix|revise|replace|recheck|recalculate|recompute|redo|try again|check again)\\b)", "(?:^|[.!?;,:。！？；，、\\n])\\s*(?:请|然后|再|并|接着)*(?:(?:把|将).{0,24})?(?:(请|重新|再).{0,16}(检查|核对|计算|推导|修改|纠正|更正|修正)|纠正|更正|修正|重算|重做)", "(?:^|[.!?;,:。！？；，、\\n])\\s*(?:(?:من فضلك|ثم|رجاء)\\s+)*(?:(صحح|صحّح|صوّب|عدّل|راجع|أعد|اعد).{0,40}(الإجابة|الجواب|النتيجة|الناتج|الحساب|القيمة|حساب|فحص|النظر)|أعد الحساب)", "(?:^|[.!?;,:。！？；，、\\n])\\s*(?:(?:bitte|dann|und|jetzt)\\s+)*(?:(korrigiere|berichtige|überprüfe|prüfe|berechne|überarbeite|wiederhole))", "(?:^|[.!?;,:。！？；，、\\n])\\s*(?:(?:por favor|después|luego|ahora|y)\\s+)*(?:(corrige|corrija|rectifica|revisa|recalcula|vuelve a calcular|comprueba de nuevo))", "(?:^|[.!?;,:。！？；，、\\n])\\s*(?:まず|次に|そして)?(?:(訂正|修正|直して|やり直|再計算|確認して|見直して|検算))", "(?:^|[.!?;,:。！？；，、\\n])\\s*(?:s\\x27il vous plaît[, ]*|s\\x27il te plaît[, ]*|puis\\s+)?(corrigez|corrige|rectifiez|rectifie|recalculez|recalcule)\\b", "(?:^|[.!?;,:。！？；，、\\n])\\s*(?:por favor[, ]*)?(corrija|corrige|corrigir|retifique|recalcule)\\b", "(?:^|[.!?;,:。！？；，、\\n])\\s*(?:제발\\s*|다시\\s*)?(?:답변을\\s*|답을\\s*|결과를\\s*)?(수정|정정|고쳐|바로잡)", "(?:^|[.!?;,:।\\n])\\s*(?:कृपया\\s*)?(?:इसे\\s*|उत्तर\\s*|जवाब\\s*)?(सुधारें|सुधारो|सही करें|ठीक करें)", "(?:^|[.!?;,:。！？；，、\\n])\\s*(?:пожалуйста[, ]*)?(исправь|исправьте|скорректируй|скорректируйте|пересчитай|пересчитайте)"]
    method: "regex"
  }

  SIGNAL keyword no_revision {
    operator: "OR"
    keywords: ["(do not|don't|never).{0,24}(correct|fix|revise|replace|recheck|recalculate|redo)", "(不要|无需|不必).{0,12}(纠正|更正|修正|修改|重算|重做|核对)", "لا.{0,12}(تصحح|تعدّل|تعدل|تراجع|تعد الحساب)", "(nicht|keinesfalls).{0,24}(korrigieren|berichtigen|überarbeiten|ändern)|korrigiere.{0,24}nicht", "no.{0,12}(corrijas|corrija|rectifiques|revises|recalcules)", "(訂正|修正|変更|再計算).{0,8}(しないで|不要)|直さないで", "不要.{0,12}(重新检查|重新计算|检查|计算)|别.{0,12}(纠正|修正|重算)", "لا.{0,12}(تصحّح|تراجع|تعد حساب|تعد فحص)", "(prüfe|überprüfe|berechne|überarbeite|berichtige).{0,24}nicht", "no.{0,12}(corrijas|rectifiques|revises|recalcules|vuelvas a calcular)", "(やり直さない|見直さない|確認しない|再計算しない)", "ne.{0,24}(corrige|rectifie|recalcule).{0,16}pas", "não.{0,16}(corrija|corrige|corrigir|retifique|recalcule)", "(수정|정정|고치|고쳐|바로잡).{0,12}(하지 마|지 마|말아|필요 없)", "(सुधार|सही|ठीक).{0,12}(न करें|मत करो|मत करें)|मत.{0,12}(सुधार|करो)", "(?:^|[\\s.!?;,:])не\\s+(исправ|корректир|пересчит)"]
    method: "regex"
  }

  SIGNAL keyword plural_workers {
    operator: "OR"
    keywords: ["(multiple|several|two|three|2|3|different|separate|independent).{0,32}(models|agents|workers|reviewers|experts)", "(多个|两|三|不同|独立的).{0,12}(模型|智能体|执行者|评审|专家)", "((عدة|عدّة|اثنين|اثنان).{0,20}(نماذج|وكلاء|مراجعين|خبراء)|نموذجين|وكيلين|(نماذج|وكلاء|مراجعين|خبراء).{0,20}(مختلفة|مختلفين|مستقلة|مستقلين))", "(mehrere|zwei|drei|verschiedene|getrennte|unabhängige).{0,24}(modelle|agenten|bearbeiter|prüfer|experten)", "(varios|varias|dos|tres|diferentes|distintos|independientes).{0,24}(modelos|agentes|trabajadores|revisores|expertos)", "(複数|二つ|三つ|2つ|3つ|別々|異なる|独立した).{0,12}(モデル|エージェント|担当者|評価者|専門家)"]
    method: "regex"
  }

  SIGNAL keyword review_action {
    operator: "OR"
    keywords: ["(?:^|[.!?;,:。！？；，、\\n])\\s*(?:(?:please|then|and|now)\\s+)*(?:(?:I want you to|I would like you to|could you|can you)\\s+)?(?:(ask|consult|obtain|get|use|have).{0,80}(model|reviewer|expert|answer|assessment))", "(?:^|[.!?;,:。！？；，、\\n])\\s*(?:请|然后|再|并|接着)*(?:(?:把|将).{0,24})?(?:(请|让|使用|获取|征求).{0,32}(模型|评审|专家|答案|评估))", "(?:^|[.!?;,:。！？；，、\\n])\\s*(?:(?:من فضلك|ثم|رجاء)\\s+)*(?:(اطلب|استشر|احصل|استخدم).{0,60}(نموذج|نماذج|مراجعين|خبراء|إجابات|تقييم))", "(?:^|[.!?;,:。！？；，、\\n])\\s*(?:(?:bitte|dann|und|jetzt)\\s+)*(?:(frage|befrage|konsultiere|hole|lass|nutze|verwende).{0,64}(modell|prüfer|experten|antwort|beurteil))", "(?:^|[.!?;,:。！？；，、\\n])\\s*(?:(?:por favor|después|luego|ahora|y)\\s+)*(?:(pide|consulta|obtén|obten|usa|utiliza|solicita).{0,64}(modelo|revisor|experto|respuesta|evaluación))", "(?:^|[.!?;,:。！？；，、\\n])\\s*(?:まず|次に|そして)?(?:異なる|複数の|二つの|三つの|独立した)?(モデル|評価者|専門家).{0,48}(依頼して|求め[、，て]|使って|検討してもら|評価してもら)"]
    method: "regex"
  }

  SIGNAL keyword independent_work {
    operator: "OR"
    keywords: ["independen(t|tly)|separate assessments|different answers", "独立|分别|各自", "مستقل|منفصل|كل.{0,12}على حدة", "unabhängig|getrennt|jeweils", "independiente|por separado|cada uno", "独立|別々|それぞれ"]
    method: "regex"
  }

  SIGNAL keyword distributed_execution {
    operator: "OR"
    keywords: ["(?:^|[.!?;,:。！？；：，\\n])\\s*(?:please\\s+|then\\s+|now\\s+)?(?:divide|split|distribute|coordinate)\\b[^.!?;,:。！？；：，\\n]{0,80}(?:two|three|multiple|several|independent|separate)\\s+(?:agents|workers|models)\\b", "(?:^|[.!?;,:。！？；：，\\n])\\s*(?:please\\s+|then\\s+|now\\s+)?(?:let|have)\\s+(?:two|three|multiple|several|independent|separate)\\s+(?:agents|workers|models)\\b[^.!?;,:。！？；：，\\n]{0,80}(?:divide|split|distribute|coordinate)\\b", "(?:^|[.!?;,:。！？；：，\\n])\\s*(?:请|然后|再)?(?:分配|分派|拆分|划分|协调)[^.!?;,:。！？；：，\\n]{0,80}(?:两|三|多个|不同的|独立的)(?:个)?(?:智能体|模型|执行者)", "(?:^|[.!?;,:。！？；：，\\n])\\s*(?:请|然后|再)?(?:让|请)(?:两|三|多个|不同的|独立的)(?:个)?(?:智能体|模型|执行者)[^.!?;,:。！？；：，\\n]{0,80}(?:分工|分担|分别处理|协调)", "(?:^|[.!?;,:。！？；：，\\n])\\s*(?:(?:من فضلك|ثم|رجاء)\\s+)?(?:وزّع|وزع|قسّم|قسم|نسّق|نسق)[^.!?;,:。！？；：，\\n]{0,80}(?:وكيلين|نموذجين|عاملين|(?:عدة|عدّة)\\s+(?:وكلاء|نماذج|عاملين)|(?:وكلاء|نماذج|عاملين)\\s+(?:مستقلين|مستقلة|مختلفين|مختلفة))", "(?:^|[.!?;,:。！？；：，\\n])\\s*(?:(?:من فضلك|ثم|رجاء)\\s+)?اجعل\\s+(?:وكيلين|نموذجين|عاملين|(?:عدة|عدّة)\\s+(?:وكلاء|نماذج|عاملين)|(?:وكلاء|نماذج|عاملين)\\s+(?:مستقلين|مستقلة|مختلفين|مختلفة))[^.!?;,:。！？；：，\\n]{0,80}(?:يتقاسم|يقسم|يوزع|ينسق)(?:ان|ون)", "(?:^|[.!?;,:。！？；：，\\n])\\s*(?:bitte\\s+|dann\\s+|jetzt\\s+)?(?:verteile|teile|koordiniere)\\b[^.!?;,:。！？；：，\\n]{0,80}(?:zwei|drei|mehrere[nr]?|unabhängige[nr]?)\\s+(?:agenten|modelle[n]?|bearbeiter[n]?|arbeiter[n]?)\\b", "(?:^|[.!?;,:。！？；：，\\n])\\s*(?:bitte\\s+|dann\\s+|jetzt\\s+)?lass\\s+(?:zwei|drei|mehrere[nr]?|unabhängige[nr]?)\\s+(?:agenten|modelle[n]?|bearbeiter[n]?|arbeiter[n]?)\\b[^.!?;,:。！？；：，\\n]{0,80}(?:aufteilen|teilen|verteilen|koordinieren)\\b", "(?:^|[.!?;,:。！？；：，\\n])\\s*(?:por favor\\s+|luego\\s+|ahora\\s+)?(?:reparte|divide|distribuye|coordina)\\b[^.!?;,:。！？；：，\\n]{0,80}(?:(?:dos|tres|varios|varias|independientes)\\s+(?:agentes|modelos|trabajadores|trabajadoras)|(?:agentes|modelos|trabajadores|trabajadoras)\\s+(?:independientes|separados|separadas))\\b", "(?:^|[.!?;,:。！？；：，\\n])\\s*(?:por favor\\s+|luego\\s+|ahora\\s+)?(?:haz que|pide que)\\s+(?:(?:dos|tres|varios|varias|independientes)\\s+(?:agentes|modelos|trabajadores|trabajadoras)|(?:agentes|modelos|trabajadores|trabajadoras)\\s+(?:independientes|separados|separadas))\\b[^.!?;,:。！？；：，\\n]{0,80}(?:dividan|repartan|distribuyan|coordinen)\\b", "(?:^|[.!?;,:。！？；：，\\n])\\s*(?:まず|次に|そして)?(?:二つ|三つ|複数|独立した)(?:の)?(?:エージェント|モデル|担当者)[^.!?;,:。！？；：，\\n]{0,80}(?:分担して|分配して|割り振って|連携させて|調整して)", "(?:^|[.!?;,:。！？；：，\\n])\\s*(?:まず|次に|そして)?(?:作業|仕事|タスク|ワークフロー)[^.!?;,:。！？；：，\\n]{0,80}(?:二つ|三つ|複数|独立した)(?:の)?(?:エージェント|モデル|担当者)[^.!?;,:。！？；：，\\n]{0,80}(?:分担して|分配して|割り振って|連携させて|調整して)"]
    method: "regex"
  }

  SIGNAL keyword delegated_executors {
    operator: "OR"
    keywords: ["(?:^|[.!?;,:。！？；：，\\n])\\s*(?:please\\s+|then\\s+|now\\s+)?(?:delegate|assign|entrust)\\b[^.!?;,:。！？；：，\\n]{0,80}(?:two|three|multiple|several|independent|separate)\\s+(?:agents|workers|models)\\b", "(?:^|[.!?;,:。！？；：，\\n])\\s*(?:please\\s+|then\\s+|now\\s+)?(?:let|have)\\s+(?:two|three|multiple|several|independent|separate)\\s+(?:agents|workers|models)\\b[^.!?;,:。！？；：，\\n]{0,80}(?:handle|take on|carry out)\\b", "(?:^|[.!?;,:。！？；：，\\n])\\s*(?:请|然后|再)?(?:委派|交给|委托|指派)[^.!?;,:。！？；：，\\n]{0,80}(?:两|三|多个|不同的|独立的)(?:个)?(?:智能体|模型|执行者)", "(?:^|[.!?;,:。！？；：，\\n])\\s*(?:请|然后|再)?(?:让|请)(?:两|三|多个|不同的|独立的)(?:个)?(?:智能体|模型|执行者)[^.!?;,:。！？；：，\\n]{0,80}(?:处理|执行|承担)", "(?:^|[.!?;,:。！？；：，\\n])\\s*(?:(?:من فضلك|ثم|رجاء)\\s+)?(?:فوّض|فوض|أسند|اسند)[^.!?;,:。！？；：，\\n]{0,80}(?:وكيلين|نموذجين|عاملين|(?:عدة|عدّة)\\s+(?:وكلاء|نماذج|عاملين)|(?:وكلاء|نماذج|عاملين)\\s+(?:مستقلين|مستقلة|مختلفين|مختلفة))", "(?:^|[.!?;,:。！？；：，\\n])\\s*(?:(?:من فضلك|ثم|رجاء)\\s+)?اجعل\\s+(?:وكيلين|نموذجين|عاملين|(?:عدة|عدّة)\\s+(?:وكلاء|نماذج|عاملين)|(?:وكلاء|نماذج|عاملين)\\s+(?:مستقلين|مستقلة|مختلفين|مختلفة))[^.!?;,:。！？；：，\\n]{0,80}(?:يتوليان|ينفذان|يتولون|ينفذون)", "(?:^|[.!?;,:。！？；：，\\n])\\s*(?:bitte\\s+|dann\\s+|jetzt\\s+)?(?:delegiere|weise|übertrage)\\b[^.!?;,:。！？；：，\\n]{0,80}(?:zwei|drei|mehrere[nr]?|unabhängige[nr]?)\\s+(?:agenten|modelle[n]?|bearbeiter[n]?|arbeiter[n]?)\\b", "(?:^|[.!?;,:。！？；：，\\n])\\s*(?:bitte\\s+|dann\\s+|jetzt\\s+)?lass\\s+(?:zwei|drei|mehrere[nr]?|unabhängige[nr]?)\\s+(?:agenten|modelle[n]?|bearbeiter[n]?|arbeiter[n]?)\\b[^.!?;,:。！？；：，\\n]{0,80}(?:bearbeiten|übernehmen)\\b", "(?:^|[.!?;,:。！？；：，\\n])\\s*(?:por favor\\s+|luego\\s+|ahora\\s+)?(?:delega|asigna|encomienda)\\b[^.!?;,:。！？；：，\\n]{0,80}(?:(?:dos|tres|varios|varias|independientes)\\s+(?:agentes|modelos|trabajadores|trabajadoras)|(?:agentes|modelos|trabajadores|trabajadoras)\\s+(?:independientes|separados|separadas))\\b", "(?:^|[.!?;,:。！？；：，\\n])\\s*(?:por favor\\s+|luego\\s+|ahora\\s+)?(?:haz que|pide que)\\s+(?:(?:dos|tres|varios|varias|independientes)\\s+(?:agentes|modelos|trabajadores|trabajadoras)|(?:agentes|modelos|trabajadores|trabajadoras)\\s+(?:independientes|separados|separadas))\\b[^.!?;,:。！？；：，\\n]{0,80}(?:se encarguen|realicen)\\b", "(?:^|[.!?;,:。！？；：，\\n])\\s*(?:まず|次に|そして)?(?:二つ|三つ|複数|独立した)(?:の)?(?:エージェント|モデル|担当者)[^.!?;,:。！？；：，\\n]{0,80}(?:任せて|委任して|割り当てて)", "(?:^|[.!?;,:。！？；：，\\n])\\s*(?:まず|次に|そして)?(?:作業|仕事|タスク|ワークフロー)[^.!?;,:。！？；：，\\n]{0,80}(?:二つ|三つ|複数|独立した)(?:の)?(?:エージェント|モデル|担当者)[^.!?;,:。！？；：，\\n]{0,80}(?:任せて|委任して|割り当てて)"]
    method: "regex"
  }

  SIGNAL keyword no_workflow_execution {
    operator: "OR"
    keywords: ["\\b(?:do not|don't|never)\\s+(?:run|execute|invoke|activate|call|distribute|coordinate|delegate)\\b", "\\b(?:only|just)\\s+(?:describe|outline|plan|simulate)\\b", "(?:不要|别|不许|无需).{0,12}(?:运行|执行|调用|启动|分工|分配|协调)", "(?:只|仅)(?:需|要)?(?:描述|说明|规划|模拟)", "لا\\s+(?:تشغّل|تشغل|تنفذ|تستدع|تستخدم|تنسق|توزع|تقسم)", "(?:صف|اشرح|خطط|حاك)[^.!?;,:。！？；：，\\n]{0,80}فقط", "(?:verteile|teile|koordiniere|delegiere|weise|übertrage|lass|führe|starte|rufe)\\b[^.!?;,:。！？；：，\\n]{0,80}\\b(?:nicht|niemals)\\b", "\\b(?:nur|lediglich)\\s+(?:beschreiben|planen|simulieren)\\b", "(?:beschreibe|plane|simuliere)\\b[^.!?;,:。！？；：，\\n]{0,80}\\b(?:nur|lediglich)\\b", "\\bno\\s+(?:ejecutes|ejecute|invoques|llames|actives|coordines|distribuyas|delegues)\\b", "\\b(?:solo|sólo|solamente)\\s+(?:describe|describas|planifica|simula)\\b", "\\b(?:describe|planifica|simula)\\b[^.!?;,:。！？；：，\\n]{0,80}\\b(?:solo|sólo|solamente)\\b", "(?:実行|起動|呼び出し|分配|分担|委任).{0,8}(?:しないで|しない|せず|不要)", "(?:説明|計画|シミュレーション|描写).{0,8}(?:だけ|のみ)"]
    method: "regex"
  }

  SIGNAL embedding consequential {
    prototype_scoring: { best_weight: 0.75, enabled: false, top_m: 2 }
    threshold: 0.7
    candidates: ["Help choose an action when a mistaken choice could cause material harm or an irreversible loss.", "Evaluate practical alternatives and recommend a course of action while accounting for consequential uncertainty.", "当错误选择可能造成实质伤害或不可逆损失时，帮助选择行动。", "评估现实可行的方案，并在考虑重大不确定性的基础上建议行动路线。", "ساعد في اختيار تصرف عندما قد يؤدي القرار الخاطئ إلى ضرر ملموس أو خسارة لا يمكن تداركها.", "قيّم البدائل العملية واقترح مساراً للعمل مع مراعاة عدم اليقين ذي العواقب المهمة.", "Hilf bei der Wahl einer Handlung, wenn eine falsche Entscheidung erheblichen Schaden oder einen unumkehrbaren Verlust verursachen könnte.", "Bewerte praktische Alternativen und empfehle ein Vorgehen unter Berücksichtigung folgenreicher Unsicherheit.", "Ayuda a elegir una acción cuando una decisión equivocada podría causar un daño importante o una pérdida irreversible.", "Evalúa alternativas prácticas y recomienda una línea de acción teniendo en cuenta la incertidumbre y sus consecuencias.", "誤った選択が重大な被害や取り返しのつかない損失を招く可能性があるとき、行動の選択を支援してください。", "現実的な選択肢を評価し、重大な結果につながる不確実性を考慮して行動方針を勧めてください。"]
    aggregation_method: "max"
  }

  SIGNAL embedding workflow_intent {
    prototype_scoring: { best_weight: 0.75, enabled: false, top_m: 2 }
    threshold: 0.78
    candidates: ["Coordinate separate workers through dependent stages, validate their intermediate results, and assemble one completed outcome.", "Delegate different parts of the work to multiple agents and integrate the verified outputs.", "协调不同执行者完成相互依赖的阶段，验证中间结果，并整合出完整成果。", "把不同工作分派给多个智能体，再整合经过验证的输出。", "نسّق عمل منفذين منفصلين عبر مراحل مترابطة، وتحقق من نتائجهم الوسيطة ثم اجمعها في نتيجة مكتملة.", "فوّض أجزاء مختلفة من العمل إلى عدة وكلاء، ثم ادمج المخرجات التي جرى التحقق منها.", "Koordiniere getrennte Bearbeiter über voneinander abhängige Phasen, prüfe ihre Zwischenergebnisse und füge ein vollständiges Ergebnis zusammen.", "Delegiere verschiedene Arbeitsteile an mehrere Agenten und integriere die geprüften Ergebnisse.", "Coordina trabajadores separados en etapas dependientes, valida sus resultados intermedios y reúne un resultado completo.", "Delega distintas partes del trabajo a varios agentes e integra las salidas verificadas.", "別々の担当者を連携させて依存関係のある段階を進め、中間結果を検証して一つの完成した成果にまとめてください。", "作業の異なる部分を複数のエージェントに委任し、検証済みの出力を統合してください。"]
    aggregation_method: "max"
  }

  SIGNAL embedding review_intent {
    prototype_scoring: { best_weight: 0.75, enabled: false, top_m: 2 }
    threshold: 0.6
    candidates: ["Obtain independent answers from different models, examine their disagreements, and reconcile one answer.", "Ask separate reviewers to assess the same issue independently before comparing and synthesizing their conclusions.", "让不同模型独立作答，检查分歧，并协调形成一个答案。", "请不同评审者独立评估同一问题，再比较并综合他们的结论。", "احصل على إجابات مستقلة من نماذج مختلفة، وافحص أوجه اختلافها ثم وفّق بينها في إجابة واحدة.", "اطلب من مراجعين منفصلين تقييم المسألة نفسها بصورة مستقلة، ثم قارن استنتاجاتهم واجمعها.", "Hole unabhängige Antworten verschiedener Modelle ein, prüfe ihre Widersprüche und führe sie zu einer Antwort zusammen.", "Lass getrennte Prüfer dieselbe Frage unabhängig beurteilen, bevor du ihre Schlussfolgerungen vergleichst und zusammenführst.", "Obtén respuestas independientes de modelos diferentes, examina sus desacuerdos y concílialas en una respuesta.", "Pide a revisores separados que evalúen el mismo asunto de forma independiente antes de comparar y sintetizar sus conclusiones.", "異なるモデルから独立した回答を得て、相違点を検討し、一つの回答にまとめてください。", "別々の評価者に同じ問題を独立に検討してもらい、その後で結論を比較して統合してください。"]
    aggregation_method: "max"
  }

  SIGNAL embedding informational {
    prototype_scoring: { best_weight: 0.75, enabled: false, top_m: 2 }
    threshold: 0.7
    candidates: ["Explain the meaning of a concept neutrally without advising anyone to act.", "Describe background information for learning or quotation, without making a practical recommendation.", "客观解释一个概念的含义，不建议任何人采取行动。", "介绍用于学习或引用的背景信息，不提供现实行动建议。", "اشرح معنى مفهوم بشكل محايد من دون أن تنصح أحداً باتخاذ إجراء.", "قدّم معلومات خلفية للتعلم أو الاقتباس من دون تقديم توصية عملية.", "Erkläre die Bedeutung eines Begriffs neutral, ohne jemandem zu einer Handlung zu raten.", "Beschreibe Hintergrundinformationen zum Lernen oder Zitieren, ohne eine praktische Empfehlung zu geben.", "Explica el significado de un concepto de forma neutral sin aconsejar a nadie que actúe.", "Describe información de contexto para aprender o citar, sin hacer una recomendación práctica.", "誰かに行動を勧めることなく、概念の意味を中立的に説明してください。", "学習や引用のための背景情報を説明し、実際の行動については助言しないでください。"]
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
    feature: { source: { pattern: "(?i)(?:(\\b(define|translate|explain)\\b.{0,48}\\b(phrase|term|expression)\\b|(définis|traduis|explique).{0,48}(expression|terme)|(define|traduce|explica).{0,48}(frase|expresión|término)|(definiere|übersetze|erkläre).{0,48}(ausdruck|begriff)|(defina|traduza|explique).{0,48}(frase|expressão|ter(?:mo))|(정의|번역|설명).{0,16}(문구|표현|용어|“|「)|(عرّف|ترجم|اشرح).{0,32}(العبارة|التعبير|المصطلح)|(परिभाषित|अनुवाद|समझाइए).{0,32}(वाक्यांश|अभिव्यक्ति|शब्द)|(определи|переведи|объясни).{0,48}(фразу|выражение|термин)|(定义|翻译|解释).{0,16}(短语|词语|“|「)|(説明|翻訳).{0,16}(表現|語句|「)|([\"“「][^\"”」]{1,120}[\"”」]).{0,80}(define|translate|explain|설명|정의|번역|اشرح|عرّف|ترجم|समझाइए|परिभाषित|अनुवाद|объясни|определи|переведи|解释|定义|翻译|説明|翻訳))|(?:^|[.!?;。！？；\\n])\\s*(?:please\\s+)?(?:translate|quote)\\b[^.!?;:\\n]{0,64}[:：]|(?:^|[.!?;。！？；\\n])\\s*(?:请)?(?:翻译|引用)[^。！？；：\\n]{0,32}[:：]|(?:^|[.!?;。！？；\\n])\\s*(?:(?:من فضلك|رجاء)\\s+)?(?:ترجم|اقتبس)[^.!?؛:\\n]{0,48}[:：]|(?:^|[.!?;。！？；\\n])\\s*(?:bitte\\s+)?(?:übersetze|zitiere)\\b[^.!?;:\\n]{0,64}[:：]|(?:^|[.!?;。！？；\\n])\\s*(?:por favor\\s+)?(?:traduce|cita)\\b[^.!?;:\\n]{0,64}[:：]|(?:^|[.!?;。！？；\\n])\\s*(?:以下を|次を)?(?:翻訳|引用)(?:して(?:ください)?)?[:：])", type: "regex" }, type: "exists" }
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
    prototype_scoring: { best_weight: 0.75, enabled: false, top_m: 2 }
    threshold: 0.08
    description: "Separate direct tasks from analysis and synthesis. Length and language do not determine difficulty."
    hard: { candidates: ["Find an outcome satisfying interacting constraints and justify why the nearest alternatives fail.", "Reconcile conflicting evidence, identify unsupported assumptions, and defend a conclusion under uncertainty.", "Design a multi-stage solution whose intermediate choices remain consistent with the final objective.", "找出满足相互影响的约束的结果，并说明最接近的其他方案为何不成立。", "协调冲突的证据，识别没有依据的假设，并在不确定性下论证结论。", "设计一个多阶段方案，使中间选择始终与最终目标一致。", "أوجد نتيجة تحقق قيوداً متفاعلة، وبيّن لماذا لا تصلح البدائل الأقرب.", "وفّق بين الأدلة المتعارضة، وحدد الافتراضات غير المدعومة، ودافع عن استنتاج في ظل عدم اليقين.", "صمّم حلاً متعدد المراحل تبقى خياراته الوسيطة متسقة مع الهدف النهائي.", "Finde ein Ergebnis, das zusammenwirkende Bedingungen erfüllt, und begründe, warum die nächstliegenden Alternativen scheitern.", "Gleiche widersprüchliche Belege ab, erkenne unbelegte Annahmen und verteidige eine Schlussfolgerung unter Unsicherheit.", "Entwirf eine mehrstufige Lösung, deren Zwischenentscheidungen mit dem Endziel vereinbar bleiben.", "Encuentra un resultado que satisfaga restricciones interdependientes y justifica por qué fallan las alternativas más cercanas.", "Concilia pruebas contradictorias, identifica supuestos sin fundamento y defiende una conclusión ante la incertidumbre.", "Diseña una solución de varias etapas cuyas decisiones intermedias sigan siendo coherentes con el objetivo final.", "相互に影響する制約を満たす結果を見つけ、近い代替案が成立しない理由を示してください。", "矛盾する証拠を整理し、裏付けのない仮定を特定して、不確実な状況でも結論を論証してください。", "中間の選択が最終目標と一貫する、多段階の解決策を設計してください。"] }
    easy: { candidates: ["Copy explicitly supplied information into the requested structure without adding an inference.", "Apply one local edit while preserving the meaning and all other stated details.", "Retrieve a directly stated fact and give a concise answer without combining separate arguments.", "把明确提供的信息复制到指定结构中，不添加推断。", "只做一处局部修改，保留原意以及所有其他已述细节。", "提取直接陈述的事实，简洁作答，不合并不同论证。", "انسخ المعلومات المقدمة صراحةً إلى البنية المطلوبة من دون إضافة استنتاج.", "أجر تعديلاً موضعياً واحداً مع الحفاظ على المعنى وجميع التفاصيل الأخرى المذكورة.", "استخرج حقيقة مذكورة مباشرةً وقدّم إجابة موجزة من دون دمج حجج منفصلة.", "Übertrage ausdrücklich bereitgestellte Informationen in die verlangte Struktur, ohne eine Schlussfolgerung hinzuzufügen.", "Nimm eine einzige lokale Änderung vor und erhalte dabei die Bedeutung und alle anderen genannten Einzelheiten.", "Entnimm eine direkt genannte Tatsache und antworte knapp, ohne getrennte Argumente zu verbinden.", "Copia la información proporcionada explícitamente en la estructura solicitada sin añadir inferencias.", "Aplica una sola modificación local conservando el significado y todos los demás detalles indicados.", "Extrae un hecho expresado directamente y responde de forma concisa sin combinar argumentos separados.", "明示された情報を指定の構造にそのまま移し、推論を加えないでください。", "意味と他のすべての記載事項を保ちながら、一か所だけ修正してください。", "直接述べられた事実を取り出し、別々の論点を組み合わせずに簡潔に答えてください。"] }
  }

  PROJECTION score recovery {
    method: "weighted_sum"
    inputs: [{ type: "user_feedback", weight: 1, name: "wrong_answer" }, { type: "reask", weight: 0.5, name: "repeat" }, { type: "keyword", weight: 0.5, name: "correction" }]
  }

  PROJECTION score care_margin {
    method: "weighted_sum"
    inputs: [{ type: "embedding", weight: 1, name: "consequential", value_source: "raw" }, { type: "embedding", weight: -1, name: "informational", value_source: "raw" }]
  }

  PROJECTION score workflow_margin {
    method: "weighted_sum"
    inputs: [{ type: "embedding", weight: 1, name: "workflow_intent", value_source: "raw" }, { type: "embedding", weight: -1, name: "informational", value_source: "raw" }]
  }

  PROJECTION mapping recovery_band {
    source: "recovery"
    method: "threshold_bands"
    outputs: [{ name: "retry", gte: 1 }]
  }

  PROJECTION mapping care_margin_direction {
    source: "care_margin"
    method: "threshold_bands"
    outputs: [{ name: "actionable_care", gt: 0 }]
  }

  PROJECTION mapping workflow_direction {
    source: "workflow_margin"
    method: "threshold_bands"
    outputs: [{ name: "execution_direction", gt: 0 }]
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
    WHEN (conversation("flow") OR (keyword("distributed_execution") OR keyword("delegated_executors") AND projection("execution_direction")) AND NOT keyword("single") AND NOT keyword("no_workflow_execution") AND NOT conversation("tool_loop") AND NOT conversation("tool_required") AND NOT structure("quoted_request"))
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
    WHEN (keyword("plural_workers") AND keyword("review_action") AND keyword("independent_work") OR keyword("plural_workers") AND keyword("review_action") AND keyword("review") AND embedding("review_intent")) AND NOT keyword("single") AND NOT conversation("tool_loop") AND NOT conversation("tool_required") AND NOT structure("quoted_request")
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
    WHEN (complexity("difficulty:hard") AND NOT keyword("no_analysis") OR (keyword("deliberate") OR keyword("verify")) AND NOT keyword("no_analysis") AND NOT structure("quoted_request") OR conversation("has_answer") AND projection("retry") AND NOT structure("quoted_request") OR projection("actionable_care") AND (fact_check("needs_fact_check") OR domain("health") OR domain("law") OR domain("business") OR domain("economics")) OR conversation("tool_loop") OR conversation("tool_required") OR keyword("answer_error") AND keyword("answer_revision") AND NOT keyword("no_revision") AND NOT structure("quoted_request"))
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
    model_bindings: { classifier.content-risk: { adapter: "modernbert", contract: "label_scores.v1", deployment: "hazard", operating_point: { path: "operating_point.json", sha256: "e79a78f48bf45eb38e3f5402de3b3b18eeaa822e00b42b3640bf471276290de5" } } }
  }

  # =============================================================================
  # SIGNALS
  # =============================================================================

  SIGNAL keyword confidential {
    operator: "OR"
    keywords: ["\\blocal processing only\\b", "\\bdo not send (this|it) to the cloud\\b", "\\bconfidential handling\\b", "\\binternal use only\\b", "\\bprivate repositor(y|ies)\\b", "\\bproprietary code\\b", "\\bdue diligence report\\b", "\\b\\d{3}-\\d{2}-\\d{4}\\b", "本地处理", "不要发到云端", "机密处理", "仅供内部使用", "私有仓库", "内部文档", "solo procesamiento local", "no enviar a la nube", "repositorio privado", "traitement local uniquement", "ne pas envoyer au cloud", "dépôt privé", "ローカル処理のみ", "クラウドに送信しない", "プライベートリポジトリ", "nur lokale verarbeitung", "nicht in die cloud senden", "privates repository", "processamento local apenas", "não enviar para a nuvem", "repositório privado", "로컬 처리만", "클라우드로 보내지 마", "비공개 저장소", "المعالجة المحلية فقط", "لا ترسل إلى السحابة", "مستودع خاص", "केवल स्थानीय प्रसंस्करण", "क्लाउड पर न भेजें", "निजी रिपॉज़िटरी", "только локальная обработка", "не отправлять в облако", "частный репозиторий", "\\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}\\b", "\\b(private|confidential|proprietary)\\s+(?:\\w+\\s+){0,2}(architecture|diagrams?|designs?|documents?|code|data|reports?|files?)\\b", "(私有|私密|机密|保密|专有|内部)(架构|图纸|设计|文档|代码|数据|报告|文件)", "\\b(documentos?|diagramas?|diseños?|datos|informes?|archivos?)\\b.{0,24}\\b(privados?|confidenciales?)\\b", "\\b(documents?|schémas?|données|rapports?|fichiers?)\\b.{0,24}\\b(privés?|confidentiel(?:le)?s?)\\b", "(機密|非公開|社外秘).{0,12}(設計|図面|文書|コード|データ)", "\\b(vertrauliche[nmrs]?|proprietäre[nmrs]?)\\s+(architektur|entwürfe|dokumente|daten|berichte|dateien)\\b", "\\b(documentos?|diagramas?|dados|relatórios?|arquivos?)\\b.{0,24}\\b(privados?|confidenciais)\\b", "(기밀|비공개|내부).{0,12}(설계|문서|코드|데이터|보고서)", "(مستند|تصميم|مخطط|بيانات|تقرير).{0,16}(سري|سرية|خاص|خاصة)", "(गोपनीय|निजी).{0,16}(दस्तावेज|डेटा|रिपोर्ट|डिज़ाइन)", "(конфиденциальн|закрыт|внутренн).{0,20}(документ|данны|отчёт|схем|архитектур)"]
    method: "regex"
  }

  SIGNAL keyword personal_support {
    operator: "OR"
    keywords: ["(?:^|[.!?;,:。！？；，、\\n])\\s*(?:\\b(I am|I feel|I\\x27m|I need|help me|support me)\\b.{0,64}\\b(afraid|scared|overwhelmed|distressed|unsafe|support|stay safe|feel safe|cope)\\b)", "(?:^|[.!?;,:。！？；，、\\n])\\s*(?:(我很|我感到|我觉得|我需要|请帮我|帮助我).{0,24}(害怕|恐惧|难以承受|崩溃|不安全|支持|安全|应对))", "(?:^|[.!?;,:。！？；，、\\n])\\s*(?:(أنا|أشعر|احتاج|أحتاج|ساعدني|ساندني).{0,48}(خائف|خائفة|خوف|منهك|منهكة|ضيق|أمان|آمن|آمنة|دعم))", "(?:^|[.!?;,:。！？；，、\\n])\\s*(?:(ich bin|ich fühle|ich habe|ich brauche|hilf mir|unterstütze mich).{0,64}(angst|ängstlich|überfordert|verzweifelt|unsicher|sicher|unterstützung))", "(?:^|[.!?;,:。！？；，、\\n])\\s*(?:(tengo|siento|me siento|necesito|ayúdame|ayudame).{0,64}(miedo|angustia|abrumad|insegur|segur|apoyo))", "(?:^|[.!?;,:。！？；，、\\n])\\s*(?:(私は|怖い|不安|助けて|支えて).{0,32}(怖|不安|つらい|苦しい|安全|助け|支え)|(?:^|[。！？])安全に過ごすために助けて)"]
    method: "regex"
  }

  SIGNAL embedding supportive_intent {
    prototype_scoring: { best_weight: 0.75, enabled: false, top_m: 2 }
    threshold: 0.7
    candidates: ["I need supportive help to stay safe and find someone who can assist me now.", "Help me cope with distress and identify a safe next step without suggesting harmful actions.", "我需要支持来保证自身安全，并找到现在能够帮助我的人。", "请帮助我应对痛苦，确定安全的下一步，不要建议有害行为。", "أحتاج إلى دعم يساعدني على البقاء آمناً والعثور على شخص يمكنه مساعدتي الآن.", "ساعدني على التعامل مع الضيق وتحديد خطوة تالية آمنة من دون اقتراح أفعال مؤذية.", "Ich brauche Unterstützung, um sicher zu bleiben und jemanden zu finden, der mir jetzt helfen kann.", "Hilf mir, mit meiner Belastung umzugehen und einen sicheren nächsten Schritt zu finden, ohne schädliche Handlungen vorzuschlagen.", "Necesito apoyo para mantenerme a salvo y encontrar a alguien que pueda ayudarme ahora.", "Ayúdame a afrontar la angustia y encontrar un siguiente paso seguro sin sugerir acciones dañinas.", "自分の安全を保ち、今助けてくれる人を見つけるための支援が必要です。", "有害な行動を勧めずに、つらさへの対処と安全な次の一歩を考える手助けをしてください。"]
    aggregation_method: "max"
  }

  SIGNAL embedding informational {
    prototype_scoring: { best_weight: 0.75, enabled: false, top_m: 2 }
    threshold: 0.7
    candidates: ["Explain the meaning of a concept neutrally without advising anyone to act.", "Describe background information for learning or quotation, without making a practical recommendation.", "客观解释一个概念的含义，不建议任何人采取行动。", "介绍用于学习或引用的背景信息，不提供现实行动建议。", "اشرح معنى مفهوم بشكل محايد من دون أن تنصح أحداً باتخاذ إجراء.", "قدّم معلومات خلفية للتعلم أو الاقتباس من دون تقديم توصية عملية.", "Erkläre die Bedeutung eines Begriffs neutral, ohne jemandem zu einer Handlung zu raten.", "Beschreibe Hintergrundinformationen zum Lernen oder Zitieren, ohne eine praktische Empfehlung zu geben.", "Explica el significado de un concepto de forma neutral sin aconsejar a nadie que actúe.", "Describe información de contexto para aprender o citar, sin hacer una recomendación práctica.", "誰かに行動を勧めることなく、概念の意味を中立的に説明してください。", "学習や引用のための背景情報を説明し、実際の行動については助言しないでください。"]
    aggregation_method: "max"
  }

  SIGNAL structure quoted_request {
    description: "Vocabulary mentioned for explanation or translation is not an execution request."
    feature: { source: { pattern: "(?i)(?:(\\b(define|translate|explain)\\b.{0,48}\\b(phrase|term|expression)\\b|(définis|traduis|explique).{0,48}(expression|terme)|(define|traduce|explica).{0,48}(frase|expresión|término)|(definiere|übersetze|erkläre).{0,48}(ausdruck|begriff)|(defina|traduza|explique).{0,48}(frase|expressão|ter(?:mo))|(정의|번역|설명).{0,16}(문구|표현|용어|“|「)|(عرّف|ترجم|اشرح).{0,32}(العبارة|التعبير|المصطلح)|(परिभाषित|अनुवाद|समझाइए).{0,32}(वाक्यांश|अभिव्यक्ति|शब्द)|(определи|переведи|объясни).{0,48}(фразу|выражение|термин)|(定义|翻译|解释).{0,16}(短语|词语|“|「)|(説明|翻訳).{0,16}(表現|語句|「)|([\"“「][^\"”」]{1,120}[\"”」]).{0,80}(define|translate|explain|설명|정의|번역|اشرح|عرّف|ترجم|समझाइए|परिभाषित|अनुवाद|объясни|определи|переведи|解释|定义|翻译|説明|翻訳))|(?:^|[.!?;。！？；\\n])\\s*(?:please\\s+)?(?:translate|quote)\\b[^.!?;:\\n]{0,64}[:：]|(?:^|[.!?;。！？；\\n])\\s*(?:请)?(?:翻译|引用)[^。！？；：\\n]{0,32}[:：]|(?:^|[.!?;。！？；\\n])\\s*(?:(?:من فضلك|رجاء)\\s+)?(?:ترجم|اقتبس)[^.!?؛:\\n]{0,48}[:：]|(?:^|[.!?;。！？；\\n])\\s*(?:bitte\\s+)?(?:übersetze|zitiere)\\b[^.!?;:\\n]{0,64}[:：]|(?:^|[.!?;。！？；\\n])\\s*(?:por favor\\s+)?(?:traduce|cita)\\b[^.!?;:\\n]{0,64}[:：]|(?:^|[.!?;。！？；\\n])\\s*(?:以下を|次を)?(?:翻訳|引用)(?:して(?:ください)?)?[:：])", type: "regex" }, type: "exists" }
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

  SIGNAL classifier content-risk {
    description: "Recognize high-consequence content using the published Hazard operating point."
    type: "local"
    labels: ["violence", "criminal_activity", "sexual_content", "child_exploitation", "hate", "harassment_abuse", "regulated_substances", "weapons", "self_harm", "privacy", "specialized_advice", "misinformation"]
  }

  PROJECTION score support_margin {
    method: "weighted_sum"
    inputs: [{ type: "embedding", weight: 1, name: "supportive_intent", value_source: "raw" }, { type: "embedding", weight: -1, name: "informational", value_source: "raw" }]
  }

  PROJECTION mapping support_margin_direction {
    source: "support_margin"
    method: "threshold_bands"
    outputs: [{ name: "support_requested", gt: 0 }]
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

  ROUTE guard (description = "Contain detected prompt attacks before calling a backend.", on_unknown = "fail_request") {
    PRIORITY 300
    WHEN jailbreak("prompt_attack")
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

  ROUTE sensitive (description = "Use the stronger approved private pool for personal data, content risks, and responsible assistance.", on_unknown = "fail_request") {
    PRIORITY 200
    WHEN (pii("personal_data") OR keyword("confidential") OR safety("unsafe") OR classifier("content-risk", label: "violence") OR classifier("content-risk", label: "child_exploitation") OR classifier("content-risk", label: "weapons") OR classifier("content-risk", label: "self_harm") OR classifier("content-risk", label: "privacy") OR classifier("content-risk", label: "specialized_advice") OR (embedding("supportive_intent") OR keyword("personal_support") AND projection("support_requested")) AND NOT structure("quoted_request"))
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

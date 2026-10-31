extends Node
class_name StandGenerator
## 有 API key 时走 OpenAI 兼容的 chat/completions，没有 key 或调用失败时用确定性假卡。
## 校验失败会再请求一次或做确定性弱化。密钥只从环境变量或 gitignore 的配置读取，不写进日志。

const CardScript = preload("res://stand/stand_card.gd")
const CostumeScript = preload("res://ai/costume.gd")
const TEMPLATE_PATH := "res://stand/fixtures/valid_mirror_walker.json"
const CONFIG_PATH := "res://ai/llm_config.cfg"

const PRESETS: Array = [
	{"power": 4, "speed": 4, "range": 2, "stamina": 3, "precision": 3, "growth": 2},
	{"power": 3, "speed": 2, "range": 4, "stamina": 4, "precision": 3, "growth": 2},
	{"power": 5, "speed": 2, "range": 3, "stamina": 3, "precision": 3, "growth": 2},
	{"power": 2, "speed": 5, "range": 2, "stamina": 3, "precision": 4, "growth": 2},
]


func generate_from_prompt(prompt: String, allow_network: bool = true) -> Dictionary:
	var trimmed := prompt.strip_edges()
	if trimmed.is_empty():
		return {"ok": false, "code": "empty_prompt", "message": "提示词为空", "attempts": 0}
	var attempts := 1
	var source := "fixture"
	var card: Dictionary = {}
	var note := "未检测到 API key，使用确定性假数据"
	if allow_network and not _api_key().is_empty():
		var first := _call_llm(trimmed, "请生成一张符合规则的替身卡，只输出一个 JSON 对象。")
		if bool(first.get("ok", false)):
			card = first.card
			source = "llm"
			note = "LLM 已返回"
			var verdict := _validate(card)
			if not bool(verdict.get("ok", false)):
				attempts = 2
				var second := _call_llm(trimmed, "上一张未通过校验。请弱化数值、补上大招代价、去掉黑名单效果，只输出 JSON。问题：" + _brief_errors(verdict))
				if bool(second.get("ok", false)):
					card = second.card
					source = "llm+retry"
				verdict = _validate(card)
				if not bool(verdict.get("ok", false)):
					card = weaken_card(card)
					source = "llm+weaken"
					attempts = 3
					note = "LLM 结果未通过，已按规则弱化"
					verdict = _validate(card)
					if not bool(verdict.get("ok", false)):
						return {
							"ok": false,
							"code": "invalid_generation",
							"message": "弱化后仍未通过校验",
							"errors": verdict.get("errors", []),
							"attempts": attempts,
						}
		else:
			card = _fake_card(trimmed)
			source = "fallback"
			note = "LLM 调用失败（%s），已回退确定性假数据" % str(first.get("code", "error"))
	else:
		card = _fake_card(trimmed)
	var checked := _validate(card)
	if not bool(checked.get("ok", false)):
		attempts += 1
		card = weaken_card(card)
		source = source + "+weaken"
		note = "假数据未通过，已弱化重试"
		checked = _validate(card)
		if not bool(checked.get("ok", false)):
			return {
				"ok": false,
				"code": "invalid_generation",
				"message": "弱化后仍未通过校验",
				"errors": checked.get("errors", []),
				"attempts": attempts,
			}
	var image := CostumeScript.placeholder(card)
	image.url = CostumeScript.write_placeholder(card)
	return {
		"ok": true,
		"card": card,
		"source": source,
		"attempts": attempts,
		"image": image,
		"message": note,
		"errors": [],
	}


## 用合法模板盖住越界数值和黑名单词。至少一轮失败后走这里。
func weaken_card(raw: Dictionary) -> Dictionary:
	var card := _template()
	card.name = _safe_name(str(raw.get("name", "受限替身")))
	var blurb := _strip_phrases(str(raw.get("blurb", "")))
	if blurb.strip_edges().is_empty() or blurb.length() > 120 or _contains_blacklist(blurb):
		blurb = "数值与文案已按规则弱化的人形替身。"
	card.blurb = blurb
	var stats = raw.get("stats", null)
	if typeof(stats) == TYPE_DICTIONARY and _stats_legal(stats):
		card.stats = (stats as Dictionary).duplicate(true)
	var appearance = raw.get("appearance", {})
	if typeof(appearance) == TYPE_DICTIONARY:
		var meters := 1.75
		var height = appearance.get("height_m", 1.75)
		if typeof(height) == TYPE_INT or typeof(height) == TYPE_FLOAT:
			meters = float(height)
		if meters < 1.5:
			meters = 1.5
		if meters > 2.0:
			meters = 2.0
		var summary := _strip_phrases(str(appearance.get("summary", "")))
		if summary.strip_edges().is_empty() or _contains_blacklist(summary):
			summary = "成年人形，体型符合普通成人。"
		card.appearance = (card.appearance as Dictionary).duplicate(true)
		card.appearance.humanoid = true
		card.appearance.height_m = meters
		card.appearance.summary = summary
	return card


func _fake_card(prompt: String) -> Dictionary:
	var card := _template()
	var name := _safe_name(prompt)
	card.name = name
	var blurb := "以「%s」为意象的人形替身，近战对轰。" % name
	if blurb.length() > 120 or _contains_blacklist(blurb):
		blurb = "一名遵守对轰规则的人形替身。"
	card.blurb = blurb
	var index := absi(hash(prompt)) % PRESETS.size()
	card.stats = (PRESETS[index] as Dictionary).duplicate(true)
	var height := 1.6 + float(absi(hash(name)) % 5) * 0.08
	card.appearance = (card.appearance as Dictionary).duplicate(true)
	card.appearance.height_m = height
	card.appearance.humanoid = true
	return card


func _template() -> Dictionary:
	var loaded = CardScript.load_file(TEMPLATE_PATH)
	if loaded == null:
		return {}
	return loaded.data.duplicate(true)


func _validate(card: Dictionary) -> Dictionary:
	return load("res://stand/stand_validator.gd").validate(card)


func _stats_legal(stats: Dictionary) -> bool:
	var card := _template()
	card.stats = stats.duplicate(true)
	return bool(_validate(card).get("ok", false))


func _safe_name(prompt: String) -> String:
	var cleaned := _strip_phrases(prompt.strip_edges()).replace("\n", "").replace("\t", "")
	if cleaned.length() > 12:
		cleaned = cleaned.substr(0, 12)
	cleaned = cleaned.strip_edges()
	if cleaned.is_empty():
		return "无名替身"
	return cleaned


func _contains_blacklist(text: String) -> bool:
	var phrases := _blacklist()
	for phrase in phrases:
		if phrase in text:
			return true
	return false


func _strip_phrases(text: String) -> String:
	var cleaned := text
	for phrase in _phrases_longest_first():
		cleaned = cleaned.replace(phrase, "")
	return cleaned.strip_edges()


func _phrases_longest_first() -> PackedStringArray:
	var pending: Array = []
	for phrase in _blacklist():
		pending.append(phrase)
	var ordered := PackedStringArray()
	while pending.size() > 0:
		var best := 0
		for index in pending.size():
			if str(pending[index]).length() > str(pending[best]).length():
				best = index
		ordered.append(str(pending[best]))
		pending.remove_at(best)
	return ordered


func _blacklist() -> PackedStringArray:
	return load("res://stand/stand_validator.gd").BLACKLIST


func _brief_errors(verdict: Dictionary) -> String:
	var parts: PackedStringArray = []
	var errors = verdict.get("errors", [])
	if typeof(errors) != TYPE_ARRAY:
		return ""
	for entry in errors:
		if parts.size() >= 3:
			break
		if typeof(entry) == TYPE_DICTIONARY:
			parts.append(str(entry.get("code", "")))
	return " ".join(parts)


func _api_key() -> String:
	return str(_settings().get("key", ""))


func _settings() -> Dictionary:
	var key := OS.get_environment("STAND_LLM_API_KEY").strip_edges()
	if key.is_empty():
		key = OS.get_environment("OPENAI_API_KEY").strip_edges()
	var base := OS.get_environment("STAND_LLM_BASE_URL").strip_edges()
	if base.is_empty():
		base = "https://api.openai.com/v1"
	var model := OS.get_environment("STAND_LLM_MODEL").strip_edges()
	if model.is_empty():
		model = "gpt-4o-mini"
	if FileAccess.file_exists(CONFIG_PATH):
		var config := ConfigFile.new()
		if config.load(CONFIG_PATH) == OK:
			if key.is_empty():
				key = str(config.get_value("llm", "api_key", "")).strip_edges()
			var configured_base := str(config.get_value("llm", "base_url", "")).strip_edges()
			if not configured_base.is_empty() and OS.get_environment("STAND_LLM_BASE_URL").strip_edges().is_empty():
				base = configured_base
			var configured_model := str(config.get_value("llm", "model", "")).strip_edges()
			if not configured_model.is_empty() and OS.get_environment("STAND_LLM_MODEL").strip_edges().is_empty():
				model = configured_model
	if OS.get_environment("STAND_LLM_DISABLE").strip_edges() == "1":
		key = ""
	return {"key": key, "base": base, "model": model}


func _call_llm(prompt: String, extra: String) -> Dictionary:
	var settings := _settings()
	var key := str(settings.get("key", ""))
	if key.is_empty():
		return {"ok": false, "code": "no_key"}
	var target := _split_url(str(settings.get("base", "")))
	var http := HTTPClient.new()
	var tls: TLSOptions = null
	if bool(target.get("tls", false)):
		tls = TLSOptions.client()
	var err := http.connect_to_host(str(target.get("host", "")), int(target.get("port", 443)), tls)
	if err != OK:
		return {"ok": false, "code": "connect_failed"}
	var deadline := Time.get_ticks_msec() + 8000
	while http.get_status() == HTTPClient.STATUS_CONNECTING or http.get_status() == HTTPClient.STATUS_RESOLVING:
		http.poll()
		if Time.get_ticks_msec() > deadline:
			return {"ok": false, "code": "timeout"}
		OS.delay_msec(20)
	if http.get_status() != HTTPClient.STATUS_CONNECTED:
		return {"ok": false, "code": "connect_failed"}
	var system_text := _system_prompt()
	var payload := {
		"model": str(settings.get("model", "gpt-4o-mini")),
		"temperature": 0.4,
		"messages": [
			{"role": "system", "content": system_text},
			{"role": "user", "content": prompt + "\n" + extra + "\n字段用英文键：name, blurb, stats, skills, ultimate, passive, appearance, avatar_prompt, turnaround_prompt, model_spec。"},
		],
	}
	var body := JSON.stringify(payload)
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer " + key,
	])
	var prefix := str(target.get("prefix", ""))
	var path := "/chat/completions"
	if not prefix.is_empty():
		if prefix.ends_with("/"):
			path = prefix + "chat/completions"
		else:
			path = prefix + "/chat/completions"
	err = http.request(HTTPClient.METHOD_POST, path, headers, body)
	if err != OK:
		return {"ok": false, "code": "request_failed"}
	while http.get_status() == HTTPClient.STATUS_REQUESTING:
		http.poll()
		if Time.get_ticks_msec() > deadline:
			return {"ok": false, "code": "timeout"}
		OS.delay_msec(20)
	var response_bytes := PackedByteArray()
	while http.get_status() == HTTPClient.STATUS_BODY:
		http.poll()
		var chunk := http.read_response_body_chunk()
		if chunk.size() == 0:
			if Time.get_ticks_msec() > deadline:
				break
			OS.delay_msec(10)
		else:
			response_bytes.append_array(chunk)
	var text := response_bytes.get_string_from_utf8()
	var response = JSON.parse_string(text)
	if typeof(response) != TYPE_DICTIONARY:
		return {"ok": false, "code": "bad_response"}
	if response.has("error"):
		return {"ok": false, "code": "api_error"}
	var choices = response.get("choices", [])
	if typeof(choices) != TYPE_ARRAY or choices.is_empty():
		return {"ok": false, "code": "empty_choices"}
	var message = choices[0].get("message", {})
	if typeof(message) != TYPE_DICTIONARY:
		return {"ok": false, "code": "not_json"}
	var card = _extract_json(str(message.get("content", "")))
	if typeof(card) != TYPE_DICTIONARY:
		return {"ok": false, "code": "not_json"}
	return {"ok": true, "card": card}


func _system_prompt() -> String:
	var path := "res://docs/stand_generator_system_prompt.md"
	if not FileAccess.file_exists(path):
		return "只输出一张符合替身对决规则的 JSON 替身卡。"
	return FileAccess.get_file_as_string(path)


func _extract_json(text: String):
	var start := text.find("{")
	var ending := text.rfind("}")
	if start < 0 or ending <= start:
		return null
	var parsed = JSON.parse_string(text.substr(start, ending - start + 1))
	if typeof(parsed) != TYPE_DICTIONARY:
		return null
	return parsed


func _split_url(url: String) -> Dictionary:
	var tls := false
	var rest := url.strip_edges()
	if rest.begins_with("https://"):
		tls = true
		rest = rest.substr(8)
	elif rest.begins_with("http://"):
		rest = rest.substr(7)
	var slash := rest.find("/")
	var hostport := rest
	var prefix := ""
	if slash >= 0:
		hostport = rest.substr(0, slash)
		prefix = rest.substr(slash)
	var host := hostport
	var port := 443 if tls else 80
	var colon := hostport.rfind(":")
	if colon > 0:
		host = hostport.substr(0, colon)
		var port_text := hostport.substr(colon + 1)
		if port_text.is_valid_int():
			port = int(port_text)
	return {"tls": tls, "host": host, "port": port, "prefix": prefix}

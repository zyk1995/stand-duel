extends Node
class_name StandGenerator
## W0 不出卡。W3 再接 LLM。护栏文本见 docs/stand_generator_system_prompt.md。


func generate_from_prompt(_prompt: String) -> Dictionary:
	return {
		"ok": false,
		"code": "not_implemented",
		"message": "提示词出卡留到 W3",
	}

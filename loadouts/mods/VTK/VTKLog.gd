extends RefCounted
## Единая точка отладочного вывода мода.
## По умолчанию выключена: print() в релизе - это шум в консоли и логе игры,
## а также утечка внутренних путей. Включается галочкой "Debug log" в MCM.

static var enabled := false
static var _warned: Dictionary = {}

static func log(msg) -> void:
	if enabled:
		print(msg)

## Единый fail-closed резолв привязок внутрь игры: о промахе сообщаем один
## раз на путь (V11), чтобы обновление игры не превращалось в молчание.
static func warn_once(path: String, msg: String = "") -> void:
	if not enabled:
		return
	if _warned.has(path):
		return
	_warned[path] = true
	print("[VTK][WARN] " + (msg if msg != "" else ("missing: " + path)))

extends RefCounted
## Единая точка отладочного вывода мода.
## По умолчанию выключена: print() в релизе - это шум в консоли и логе игры,
## а также утечка внутренних путей. Включается галочкой "Debug log" в MCM.

static var enabled := false

static func log(msg) -> void:
	if enabled:
		print(msg)

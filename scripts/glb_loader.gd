extends RefCounted
## Запасной загрузчик .glb: если Godot ещё не импортировал файл,
## читаем его напрямую через GLTFDocument.
## Подключать так: const GlbLoader := preload("res://scripts/glb_loader.gd")

static func load_scene(path: String) -> Node3D:
	if not FileAccess.file_exists(path):
		print("[glb] файла нет: ", path)
		return null

	var doc := GLTFDocument.new()
	var state := GLTFState.new()

	var err := doc.append_from_file(path, state)
	if err != OK:
		print("[glb] не разобрал ", path, " (код ", err, ")")
		return null

	var root := doc.generate_scene(state)
	if root == null:
		print("[glb] пустая сцена: ", path)
		return null

	print("[glb] загружен напрямую: ", path.get_file())
	return root as Node3D

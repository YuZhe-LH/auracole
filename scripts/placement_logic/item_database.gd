extends RefCounted
class_name ItemDatabase

const IMAGE_PATH: String = "res://resources/placement_logic/device_images/"

const ITEM_ORDER: Array[String] = [
	"矿石开采机",
	"沉淀池",
	"反应池",
	"反应堆",
	"龙骨水车",
	"水坝接口"
]


static func create() -> Dictionary:
	return {
		"矿石开采机": {
			"name": "矿石开采机",
			"icon": _load_icon("kuangshikaicaiji.png"),
			"stock": 1000,
			"size": Vector2i(3, 3)
		},
		"沉淀池": {
			"name": "沉淀池",
			"icon": _load_icon("chendianchi.png"),
			"stock": 1000,
			"size": Vector2i(3, 4)
		},
		"反应池": {
			"name": "反应池",
			"icon": _load_icon("fanyingchi.png"),
			"stock": 1000,
			"size": Vector2i(3, 2)
		},
		"反应堆": {
			"name": "反应堆",
			"icon": _load_icon("fanyingdui.png"),
			"stock": 1000,
			"size": Vector2i(5, 5)
		},
		"龙骨水车": {
			"name": "龙骨水车",
			"icon": _load_icon("longgushuiche.png"),
			"stock": 1000,
			"size": Vector2i(3, 3)
		},
		"水坝接口": {
			"name": "水坝接口",
			"icon": _load_icon("shuibajiekou.png"),
			"stock": 1000,
			"size": Vector2i(2, 2)
		}
	}


static func _load_icon(file_name: String) -> Texture2D:
	var path := IMAGE_PATH + file_name
	if not ResourceLoader.exists(path):
		print("警告：图片未找到: %s" % path)
		return null

	var res := load(path)
	if res is Texture2D:
		return res as Texture2D

	var fallback := _load_icon_fallback(path)
	if fallback != null:
		print("警告：纹理导入缓存异常，已使用回退加载: %s" % path)
		return fallback

	print("警告：图片无法作为纹理加载: %s" % path)
	return null


static func _load_icon_fallback(path: String) -> Texture2D:
	var image := Image.new()
	var err := image.load(path)
	if err != OK:
		return null
	return ImageTexture.create_from_image(image)

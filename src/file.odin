package obj_viewer

import rd "../Redef/src"
import "core:encoding/json"
import "core:log"
import "core:math"
import lg "core:math/linalg"
import "core:os"
import "core:slice"
import "core:strings"
import stbi "vendor:stb/image"


AssetInstance :: struct {
	asset:           string,
	name:            string,
	position, scale: vec3,
}

SaveFile :: struct {
	checkpoint: [2]vec3,
	assets:     map[string]string, // name, path
	entities:   []EntitySerialized,
}

EntitySerialized :: struct {
	id:      EntityID,
	name:    string,
	asset:   string,
	physics: PhysicsSerialized,
}

PhysicsSerialized :: struct {
	dyn:                              bool,
	position, scale, rotation, speed: vec3,
	aabb:                             AABB,
}

write_save_file :: proc(scene: Scene, loc := #caller_location) {
	save := SaveFile {
		entities = make([]EntitySerialized, len(scene.entities), context.temp_allocator),
		assets   = make(map[string]string, context.temp_allocator),
	}
	if !g.player.noclip do save.checkpoint = g.player.checkpoint
	else do save.checkpoint = get_player_translation()

	for a in scene.assets {
		save.assets[a.name] = a.path
	}

	for e, i in scene.entities {

		rx, ry, rz := lg.euler_angles_from_quaternion(e.physics.rotation, .XYZ)
		save.entities[i] = EntitySerialized {
			id = e.id,
			asset = e.asset_name, // TODO: fix this
			name = e.name,
			physics = PhysicsSerialized {
				dyn = e.physics.dyn,
				position = e.physics.position,
				scale = e.physics.scale,
				speed = e.physics.speed,
				rotation = {rx, ry, rz},
				aabb = e.physics.aabb,
			},
		}
	}
	json_data, err := json.marshal(
		save,
		opt = {pretty = true, mjson_keys_use_quotes = true},
		allocator = context.temp_allocator,
	)
	if err != nil {
		log.errorf("Error marshaling json: %v", err)
	}
	write_err := os.write_entire_file("out/savefile.json", json_data)
	assert(err == nil)
	log.infof("%v: Save file writing successful", loc)
}

load_save_file :: proc(path: string) -> SaveFile {
	result: SaveFile
	json_filename := strings.concatenate({path, ".json"}, context.temp_allocator)
	json_data, err := os.read_entire_file_from_path(json_filename, context.temp_allocator)
	if err != nil {
		log.errorf("Failed to load save file: %v - %v", path, err)
		return result
	}

	json_err := json.unmarshal(json_data, &result)
	if json_err != nil {
		log.errorf("Failed to read savefile: %v", json_err)
	}

	return result
}

load_scene :: proc(path: string) -> Scene {
	entity_from_serialized :: proc(scene: Scene, serialized: EntitySerialized) -> Entity {
        entity: Entity
		entity.id = serialized.id
		assert(used_ids[serialized.id] == false)
		used_ids[serialized.id] = true
		entity.name = serialized.name
		entity.physics = Physics {
			dyn      = serialized.physics.dyn,
			position = serialized.physics.position,
			scale    = serialized.physics.scale,
			speed    = serialized.physics.speed,
			rotation = lg.quaternion_from_euler_angles(
				serialized.physics.rotation.x,
				serialized.physics.rotation.y,
				serialized.physics.rotation.z,
				.XYZ,
			),
			aabb     = serialized.physics.aabb,
		}
		for asset, index in scene.assets {
			if asset.name == serialized.asset {
				entity.asset_name = serialized.asset
				entity.renderable = &scene.renderables[index]
				break
			}
		}

		return entity
	}
	scene: Scene
	save_file := load_save_file(path)
	defer free_save_file(save_file)
	create_player(save_file.checkpoint.x, save_file.checkpoint.y)

	assets: [dynamic]Asset
	for asset, asset_path in save_file.assets {
		data := load_asset_data(asset_path)
		append(&assets, Asset{asset, asset_path, data})
	}
	scene.assets = assets[:]

	scene.renderables = make([]Renderable, len(scene.assets))
	for &asset, i in scene.assets {
		scene.renderables[i] = create_render_object(&asset)
	}

	for entity in save_file.entities {
		append(&scene.entities, entity_from_serialized(scene, entity))
	}

	return scene
}

free_save_file :: proc(savefile: SaveFile) {
	delete(savefile.assets)
	delete(savefile.entities)
}

load_sprite :: proc(path: string, loc := #caller_location) -> Sprite {
	pixels, size := load_pixels_byte(path); assert(pixels != nil)
	size_u32: [2]u32 = {u32(size.x), u32(size.y)}
	texture := rd.create_texture(pixels, size_u32.x, size_u32.y)
	free_pixels(pixels)

	file_name := strings.split(path, "/", context.temp_allocator)
	name_split := strings.split(file_name[len(file_name) - 1], ".", context.temp_allocator)
	name := strings.clone(name_split[0])

	return Sprite{name, texture, size}
}

load_pixels_byte :: proc(path: string, loc := #caller_location) -> (pixels: []byte, size: [2]i32) {
	path_cstr := strings.clone_to_cstring(path, context.temp_allocator)
	pixel_data := stbi.load(path_cstr, &size.x, &size.y, nil, 4)
	if pixel_data == nil {
		log.errorf("%v: Pixel data nill", path, location = loc)
		panic("")
	}
	pixels = slice.bytes_from_ptr(pixel_data, int(size.x * size.y * 4))
	assert(pixels != nil)
	return
}

load_cubemap_texture :: proc(paths: [rd.CubeFace]string) -> rd.TextureCube {
	pixels: [rd.CubeFace][]byte
	size: u32
	for path, side in paths {
		side_pixels, img_size := load_pixels_byte(path)
		assert(side_pixels != nil)
		pixels[side] = side_pixels
		assert(img_size.x == img_size.y)
		if size == 0 do size = u32(img_size.x)
		else do assert(u32(img_size.x) == size)
	}

	// texture := upload_cubemap_texture_sides(copy_pass, pixels, size)
	texture := rd.create_texture_cube(size, pixels)
	for side_pixels in pixels do free_pixels(side_pixels)
	return texture
}

free_pixels_byte :: proc(pixels: []byte) {stbi.image_free(raw_data(pixels))}
free_pixels_u16 :: proc(pixels: []u16) {stbi.image_free(raw_data(pixels))}
free_pixels :: proc {
	free_pixels_byte,
	free_pixels_u16,
}

load_pixels_u16 :: proc(path: string) -> (pixels: []u16, size: [2]i32) {
	path_cstr := strings.clone_to_cstring(path, context.temp_allocator)
	pixel_data := stbi.load_16(path_cstr, &size.x, &size.y, nil, 1); assert(pixel_data != nil)
	pixels = slice.from_ptr(pixel_data, int(size.x * size.y))
	assert(pixels != nil)
	return
}

@(private = "file")
get_pixel_color :: proc(pixels: []byte, row, col: i32, width: i32) -> vec3 {
	index := (row * width + col) * 4

	r := f32(pixels[index + 0]) / 255.0
	g := f32(pixels[index + 1]) / 255.0
	b := f32(pixels[index + 2]) / 255.0

	return vec3{r, g, b}
}

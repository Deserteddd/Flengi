package obj_viewer

import "core:strings"
import "base:runtime"
import "core:slice"
import "core:fmt"
import "core:log"
import "core:os"
import "core:encoding/json"
import stbi "vendor:stb/image"
import rd "../Redef/src"


AssetInstance :: struct {
    asset:    string,
    name:     string,
    position,
    scale:    vec3   
}

SaveFile :: struct {
    checkpoint: [2]vec3,
    assets:     map[string]string, // name, path
    entities:   []EntitySerialized
}

EntitySerialized :: struct {
    id: EntityID,
    name: string,
    asset: string,
    physics: Physics
}

// write_save_file :: proc(scene: Scene, loc := #caller_location) {
//     save: SaveFile = {
//         instances = make([]AssetInstance, len(scene.entities), context.temp_allocator),
//         assets = make(map[string]string, context.temp_allocator)
//     }
//     save.checkpoint = g.player.checkpoint
//     for a in scene.assets {
//         save.assets[a.name] = a.path
//     }

//     for e, i in scene.entities {
//         save.instances[i] = AssetInstance {
//             asset    = e.name, // TODO: fix this
//             name     = e.name,
//             position = e.transform.translation,
//             scale    = e.transform.scale
//         }
//     }
//     json_data, err := json.marshal(
//         save, 
//         opt = {
//             pretty = true,
//             mjson_keys_use_quotes = true
//         },
//         allocator = context.temp_allocator
//     )
//     assert(err == nil)
//     write_err := os.write_entire_file("out/savefile.json", json_data)
//     assert(err == nil)
//     fmt.printfln("%v: Save file writing successful", loc)
// }

load_sprite :: proc(path: string, loc := #caller_location) -> Sprite {
    pixels, size := load_pixels_byte(path); assert(pixels != nil)
    size_u32: [2]u32 = {u32(size.x), u32(size.y)}
    texture := rd.create_texture(pixels, size_u32.x, size_u32.y)
    free_pixels(pixels)

    file_name  := strings.split(path, "/", context.temp_allocator)
    name_split := strings.split(file_name[len(file_name)-1], ".", context.temp_allocator)
    name       := strings.clone(name_split[0])

    return Sprite {
        name,
        texture,
        size
    }
}

load_save_file :: proc(path: string) -> SaveFile {
    json_filename := strings.concatenate({path, ".json"}, context.temp_allocator)
    json_data, err := os.read_entire_file_from_path(json_filename, context.temp_allocator)
    assert(err == nil)

    result: SaveFile
    json_err := json.unmarshal(json_data, &result)
    assert(json_err == nil)

    return result
}

load_scene :: proc(path: string) -> Scene {
    entity_from_serialized :: proc(assets: ^[]Asset, serialized: EntitySerialized) -> Entity {
        entity: Entity
        entity.id = serialized.id
        entity.name = serialized.name
        entity.physics = serialized.physics
        for &asset in assets {
            if asset.name == serialized.asset {
                entity.asset = &asset
                break
            }
        }
        
        return entity
    }
    scene: Scene
    save_file := load_save_file(path)
    defer free_save_file(save_file)

    assets: [dynamic]Asset
    for asset, path in save_file.assets {
        data := load_asset_data(path)
        append(&assets, Asset {
            asset,
            path,
            data
        })
    }
    scene.assets = assets[:]
    
    for entity in save_file.entities {
        append(&scene.entities, entity_from_serialized(&scene.assets, entity))
    }

    return scene
}

free_save_file :: proc(savefile: SaveFile) {
    delete(savefile.assets)
    delete(savefile.entities)
}

load_pixels_byte :: proc(path: string, loc := #caller_location) -> (pixels: []byte, size: [2]i32) {
    path_cstr := strings.clone_to_cstring(path, context.temp_allocator);
    pixel_data := stbi.load(path_cstr, &size.x, &size.y, nil, 4)
    if pixel_data == nil {
        log.errorf("%v: Pixel data nill", path, location = loc)
        panic("")
    }
    pixels = slice.bytes_from_ptr(pixel_data, int(size.x * size.y * 4))
    assert(pixels != nil)
    return
}

free_pixels_byte :: proc (pixels: []byte) {stbi.image_free(raw_data(pixels))}
free_pixels_u16  :: proc (pixels: []u16)  {stbi.image_free(raw_data(pixels))}
free_pixels :: proc {free_pixels_byte, free_pixels_u16}

load_pixels_u16 :: proc(path: string) -> (pixels: []u16, size: [2]i32) {
    path_cstr := strings.clone_to_cstring(path, context.temp_allocator);
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
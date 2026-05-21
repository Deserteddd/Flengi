package obj_viewer

import "core:fmt"
import "core:slice"
import lg "core:math/linalg"
import rd "../Redef/src"

EntityID :: distinct i32

Entity :: struct {
    id:         EntityID,
    name:       string,
    asset:      ^Asset,
    renderable: ^Renderable,
    physics:    Physics
}

Transform :: struct {
    translation:    vec3,
    scale:          vec3,
    rotation:       quaternion128,
}


spawn :: proc(scene: ^Scene, index: i32, under_player: bool) -> (id: EntityID, ok: bool) {
    if i32(len(scene.assets)) > index {
        id = entity_from_asset(scene, scene.assets[index].name) or_return
        if under_player {
            for &e in scene.entities {
                if e.id == id {
                    e.physics.position = get_player_translation().x - {0, e.physics.aabb.max.y, 0}+0.01
                }
            }
        } else {
            screen_size := rd.get_window_size()
            origin, dir := ray_from_screen(g.camera, screen_size/2, screen_size)
            set_entity_transform(scene, id, origin + 10*dir)
        }
        ok = true
    }
    return
}

remove_entity :: proc(scene: ^Scene, id: EntityID) -> bool {
    if id == -1 do return false
    for e, i in scene.entities {
        if e.id == id {
            ordered_remove_soa(&scene.entities, i)
        }
    }
    return true
}

entity_from_asset :: proc(scene: ^Scene, asset_name: string, entity_name: string = "") -> (id: EntityID, ok: bool) {
    entity: Entity
    for &asset, i in scene.assets {
        if asset.name == asset_name {
            entity.renderable = &scene.renderables[i]
            entity.asset = &asset
            break
        }
    }
    ids := slice.from_ptr(scene.entities.id, len(scene.entities))
    id = lowest_free_id(ids)
    if entity_name == "" do entity.name = fmt.aprintf("%v-%v", asset_name, id)
    else do entity.name = entity_name
    entity.id = id
    entity.physics.scale = 1
    entity.physics.aabb  = entity.asset.data.header.aabb
    append_soa(&scene.entities, entity)
    ok = true
    return
}

set_entity_transform :: proc(
    scene: ^Scene, 
    id: EntityID, 
    pos: vec3, 
    scale: vec3 = 1,
    rotation: quaternion128 = {}
) {
    for &e in scene.entities {
        if e.id == id {
            e.physics.position = pos
            e.physics.scale    = scale
            e.physics.rotation = rotation
            break
        }
    }
}

// is_visible :: proc(entity: Entity, frustum_planes: [6]vec4) -> bool {
//     if entity.asset == nil do return false
//     for aabb in entity.asset.aabbs {
//         if aabb_intersects_frustum(frustum_planes, {
//             aabb.min * entity.transform.scale + entity.transform.translation,
//             aabb.max * entity.transform.scale + entity.transform.translation
//         }) { return true }
//     }
//     return false
// }

@(private = "file")
lowest_free_id :: proc(ids: []EntityID) -> EntityID {
    len := len(ids)
    for &val in ids {
        for {
            // val := ids[i];
            if val <= 0 || int(val) > len {
                break;
            }
            correct_index := val - 1;
            if ids[correct_index] == val {
                break;
            }
            temp := val;
            val = ids[correct_index];
            ids[correct_index] = temp;
        }
    }

    for val, i in ids {
        if int(val) != i + 1 {
            return EntityID(i + 1);
        }
    }

    return EntityID(len + 1);
}

package obj_viewer

import "core:math"
import "core:log"
import lg "core:math/linalg"
import rd "../Redef/src"

Player :: struct {
    position,
    speed,
    rotation:   vec3,
    bbox:       AABB,
    airborne,
    noclip:     bool,
    checkpoint: [2]vec3,                // Position, Rotation
}

create_player :: proc(pos: vec3 = 0, rotation: vec3 = 0) {
    g.player = {
        position = pos,
        rotation = rotation,
        bbox = AABB {
            min = pos + {-0.3, 0, -0.3},
            max = pos + {0.3, 2.0, 0.3}
        },
        checkpoint = {pos, rotation},
    }
}

get_player_translation :: proc() -> [2]vec3 {
    return {
        g.player.position,
        g.player.rotation
    }
}

get_entity_aabb :: #force_inline proc(entity: Entity) -> AABB {
    return AABB {
        min = entity.physics.aabb.min * entity.physics.scale + entity.physics.position,
        max = entity.physics.aabb.max * entity.physics.scale + entity.physics.position
    }
}

update_player :: proc(scene: Scene) {
    G :: 25
    p := &g.player
    dt := g.dt
    wishveloc := player_wish_speed()
    airborne_at_start := p.airborne
    if p.noclip {
        p.speed = 0
        delta_pos := wishveloc * f32(dt) * 16
        p.position += delta_pos
        p.bbox.min += delta_pos
        p.bbox.max += delta_pos
    } else {
        if wishveloc.y > 0 && !p.airborne {
            p.speed.y = 9
            p.airborne = true
        } else if !p.airborne {
            p.speed += wishveloc
        } else {
            air_accelerate(&wishveloc, f32(dt))
            p.speed.y -= f32(G * dt)
            p.speed.y = math.max(p.speed.y, -20)
        }
        delta_pos := p.speed * f32(dt)
        p.position += delta_pos
        p.bbox.min += delta_pos
        p.bbox.max += delta_pos
    }

    found_collision: bool
    
    win_size := rd.get_window_size()
    ray_origin, ray_dir := ray_from_screen(g.camera, win_size/2, win_size)
    closest_hit: f32 = math.F32_MAX
    closest_entity: EntityID = 0

    proj_matrix := create_proj_matrix(g.camera)
    view_matrix := create_view_matrix(g.camera)
    vp := proj_matrix * view_matrix
    frustum := get_furustum_planes(vp)
    for &entity in scene.entities {
        aabb := get_entity_aabb(entity)
        entity.in_frustum = aabb_intersects_frustum(frustum,  aabb)
        if aabbs_collide(p.bbox, aabb) && !p.noclip {
            found_collision = true
            mtv := resolve_aabb_collision_mtv(p.bbox, aabb)
            for axis, j in mtv do if axis != 0 {
                p.speed[j] *= 0.9
                if j == 1 { 
                    if axis > 0 { // This means we are standing on a block
                        p.airborne = false
                    } else {
                        p.speed.y = -0.1
                    }
                }
            }
            p.position += mtv
            p.bbox.min += mtv
            p.bbox.max += mtv
        }
        if g.lmb_click {
            intersection := ray_intersect_aabb(ray_origin, ray_dir, aabb)
            if intersection != -1 && intersection < closest_hit {
                closest_hit = intersection
                closest_entity = entity.id
            }
        }

    }
    if !p.noclip {
        if !found_collision do p.airborne = true

        if !airborne_at_start && !p.airborne {
            p.speed *= 0.8
        }

        if lg.length(p.speed.xz) > 20 do p.speed.xz *= 0.9
    }
}

update_camera :: proc() {
    camera := &g.camera
    x, y := rd.get_relative_mouse_movement()
    x *= g.mouse_sense
    y *= g.mouse_sense
    g.player.rotation.y += x
    g.player.rotation.x = math.min(g.player.rotation.x + y, 90)
    if g.player.rotation.x < -90 do g.player.rotation.x = -90
    camera.pitch = g.player.rotation.x
    camera.yaw = g.player.rotation.y
    camera.position = g.player.position
    camera.position.y += 2
}

player_wish_speed :: proc() -> vec3 {
    wish_speed: vec3
    u := f32(int(rd.is_key_down(.SPACE)))
    d := f32(int(rd.is_key_down(.CONTROL)))
    fb := f32(int(rd.is_key_down(.S))-int(rd.is_key_down(.W)))
    lr := f32(int(rd.is_key_down(.D))-int(rd.is_key_down(.A)))

    yaw_cos := math.cos(math.to_radians(g.player.rotation.y))
    yaw_sin := math.sin(math.to_radians(g.player.rotation.y))

    wish_speed.y = u * f32(int(!g.player.airborne))
    if g.player.noclip do wish_speed.y = u-d
    wish_speed.x += (lr * yaw_cos - fb * yaw_sin)
    wish_speed.z += (lr * yaw_sin + fb * yaw_cos)
    return wish_speed
}

air_accelerate :: proc(wishveloc: ^vec3, dt: f32) {
    addspeed, wishspd, accelspeed, currentspeed: f32
    wishveloc^ *= 10
    wishspd = vector_normalize(wishveloc);
    grounded_wishspd := wishspd
    // if wishspd > 2 do wishspd = 2
    wishspd = math.min(wishspd, 2)
    currentspeed = lg.dot(g.player.speed, wishveloc^)
    addspeed = wishspd - currentspeed
    if addspeed <= 0 do return

    accelspeed = grounded_wishspd * 5 * dt
    g.player.speed += accelspeed * wishveloc^
}
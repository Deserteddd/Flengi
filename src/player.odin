package obj_viewer

import "core:math"
import lg "core:math/linalg"
import "core:fmt"
import sdl "vendor:sdl3"

Player :: struct {
    position,
    speed,
    rotation:   vec3,
    bbox:       AABB,
    airborne,
    noclip:     bool,
    checkpoint: [2]vec3,                // Position, Rotation
}

create_player :: proc(pos: vec3 = 0) -> Player {
    return Player {
        position = pos,
        bbox = AABB {
            min = pos + {-0.3, 0, -0.3},
            max = pos + {0.3, 2.0, 0.3}
        },
    }
}

get_player_translation :: proc() -> [2]vec3 {
    return {
        g.player.position,
        g.player.rotation
    }
}

update_player :: proc(scene: Scene, dt: f32) {
    G :: 25
    p := &g.player
    wishveloc := player_wish_speed()
    airborne_at_start := p.airborne
    if p.noclip {
        p.speed = 0
        delta_pos := wishveloc * dt * 20
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
            air_accelerate(&wishveloc, dt)
            p.speed.y -= G * dt
            p.speed.y = math.max(p.speed.y, -20)
        }
        delta_pos := p.speed * dt
        p.position += delta_pos
        p.bbox.min += delta_pos
        p.bbox.max += delta_pos
    }

    found_collision: bool
    
    win_size := get_window_size()
    ray_origin, ray_dir := ray_from_screen(g.fps_camera, win_size/2, win_size)
    closest_hit: f32 = math.F32_MAX
    closest_entity: EntityID = -1

    for &entity in scene.entities {
        aabbs := entity_aabbs(entity)
        for aabb in aabbs {
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
            if g.mb_click == .LEFT {
                intersection := ray_intersect_aabb(ray_origin, ray_dir, aabb)
                if intersection != -1 && intersection < closest_hit {
                    closest_hit = intersection
                    closest_entity = entity.id
                }
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

    if g.mb_click == .LEFT {
        for &e, i in scene.entities {
            if e.id == closest_entity {
                g.editor.selected_entity = e.id
                break
            }
        }
    }
}

update_player_camera :: proc(camera: ^Camera) {
    x, y: f32
    _ = sdl.GetRelativeMouseState(&x, &y)
    g.player.rotation.y += x * 0.03
    g.player.rotation.x = math.min(g.player.rotation.x + y*0.03, 90)
    if g.player.rotation.x < -90 do g.player.rotation.x = -90
    camera.pitch = g.player.rotation.x
    camera.yaw = g.player.rotation.y
    camera.position = g.player.position
    camera.position.y += 2
}

player_wish_speed :: proc() -> vec3 {
    key_state := sdl.GetKeyboardState(nil)
    wish_speed: vec3
    sc :: sdl.Scancode
    u := f32(int(key_state[sc.SPACE]))
    d := f32(int(key_state[sc.LCTRL]))
    fb := f32(int(key_state[sc.S])-int(key_state[sc.W]))
    lr := f32(int(key_state[sc.D])-int(key_state[sc.A]))

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
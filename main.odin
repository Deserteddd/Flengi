package obj_viewer

import "core:log"
import "core:time"
import "core:os"
import lg "core:math/linalg"
import rd "../Redef"
import im "shared:imgui"
import im_win32 "shared:imgui/imgui_impl_win32"

g := struct {
    player:         Player,
    camera:         Camera,
    renderer:       Renderer,
    selected:       EntityID,
    frame:          uint,
    ui_context:     ^im.Context, 
    mouse_sense,
    dt:             f32,
    time:           time.Time,
    lmb_click,
    rmb_click,
    vsync,
    fullscreen,
    running: bool

} {
    mouse_sense = 0.04,
    running = true,
    vsync   = true,
    camera = {
        fov = 90
    }
}

main :: proc() {
    context.logger = log.create_console_logger()
    init()
    scene := load_scene("savefile")
    run(&scene)
    rd.destroy_window()
}

init :: proc() {
    ok := rd.create_window("Demo window", 1280, 720, ODIN_DEBUG); assert(ok)
    rd.set_relative_mouse_mode()
    RND_Init()
    rd.set_vsync(g.vsync)
    init_imgui()
    g.camera.fov = 90
    g.time = time.now()
}

run :: proc(scene: ^Scene) {
    now := time.now()
    main_loop: for {
        defer {
            free_all(context.temp_allocator)
            g.frame += 1
            g.lmb_click = false
            g.rmb_click = false
            // if g.frame % 100 == 0 {
            //     log.info(1000/(time.duration_milliseconds(time.since(now))/100))
            //     now = time.now()
            // }
        }
        g.dt = f32(rd.get_dt() / 1000)
        for event in rd.pump_event_iter(){
            #partial switch ev in event {
                case rd.Quit:
                    break main_loop
                case rd.KeyboardEvent:
                    mod := ev.mod
                    if ev.type == .KeyDown do #partial switch ev.key {
                        case .ESCAPE:
                            if ev.type == .KeyDown {
                                g.running = !g.running
                                rd.set_relative_mouse_mode(g.running)
                            }
                        case .F2:
                            if ev.type == .KeyDown {
                                g.vsync = !g.vsync
                                rd.set_vsync(g.vsync)
                                log.debugf("Vsync %v", g.vsync ? "on" : "off")
                            }
                        case .E:
                            reset_player_pos()
                            g.player.noclip = false
                        case .C: if .CONTROL in mod do break main_loop
                        case .Q: if !g.player.airborne || g.player.noclip do g.player.checkpoint = get_player_translation()
                        case .N: g.player.noclip = !g.player.noclip
                        case .S: if .CONTROL in mod && !g.running do write_save_file(scene^)
                        case .NUM1: if len(scene.assets) > 0 do spawn_entity(scene, scene.assets[0].name, false)
                        case .NUM2: if len(scene.assets) > 1 do spawn_entity(scene, scene.assets[1].name, false)
                        case .NUM3: if len(scene.assets) > 2 do spawn_entity(scene, scene.assets[2].name, false)
                        case .NUM4: if len(scene.assets) > 3 do spawn_entity(scene, scene.assets[3].name, false)
                        case .NUM5: if len(scene.assets) > 4 do spawn_entity(scene, scene.assets[4].name, false)
                        case .NUM6: if len(scene.assets) > 5 do spawn_entity(scene, scene.assets[5].name, false)
                    }
                case rd.MouseEvent:
                #partial switch ev.type {
                    case .LPress: g.lmb_click = true
                    case .RPress: g.rmb_click = true
                }
            }
        }

        update(scene)
        rd.clear({135, 206, 250, 255})
        draw_scene(scene)
        if !g.running do draw_imgui(scene)
        else do draw_sprite(g.renderer.crosshair)
        rd.frame_end()
    }
}

update :: proc(scene: ^Scene) -> (exit: bool) {
    if !g.running {
        if g.lmb_click {
            mx, my := rd.get_mouse_position()
            win_size := rd.get_window_size()
            ray_origin, ray_dir := ray_from_screen(g.camera, {mx, my}, win_size)
            closest_hit: f32 = max(f32)
            closest_entity: EntityID = 0
            for &entity in scene.entities {
                ensure(entity.id != 0)
                intersection := ray_intersect_aabb(ray_origin, ray_dir, get_entity_aabb(entity))
                if intersection != -1 && intersection < closest_hit {
                    closest_hit = intersection
                    closest_entity = entity.id
                }
            }
            if closest_entity != 0 {
                g.selected = closest_entity
            }
        }
        return
    }
    p := &g.player
    update_camera()
    update_player()
    //
    if g.lmb_click {
        index := spawn_entity(scene, "mappi", true)
        scene.entities[index].physics.scale = {1, 0.2, 1}
        scene.entities[index].physics.position += {0, 2, 0}
    }

    proj_matrix := create_proj_matrix(g.camera)
    view_matrix := create_view_matrix(g.camera)
    vp := proj_matrix * view_matrix
    frustum := get_furustum_planes(vp)

    win_size := rd.get_window_size()
    origin, dir := ray_from_screen(g.camera, win_size / 2, win_size)
    closest_hit: f32 = max(f32)
    closest_entity_index := -1
    found_collision: bool
    airborne_at_start := p.airborne


    for &entity, i in scene.entities {
        //Rotate
        if entity.asset_name == "helmet" {
            entity.physics.rotation *= lg.quaternion_angle_axis_f32(g.dt * 0.5, {0, 1, 0})
        }

        // Get aabb and check visibility
        aabb := get_entity_aabb(entity)
        entity.in_frustum = aabb_intersects_frustum(frustum,  aabb)

        // Check collisions
        if aabbs_collide(p.bbox, aabb) && !p.noclip {
            found_collision = true
            mtv := resolve_aabb_collision_mtv(p.bbox, aabb)
            for axis, j in mtv do if axis != 0 {
                p.speed[j] *= 0.9
                if j == 1 {
                    if axis > 0 {
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

        // Hit scan
        intersection := ray_intersect_aabb(origin, dir, get_entity_aabb(entity))
        if intersection != -1 && intersection < closest_hit {
            closest_hit = intersection
            closest_entity_index = i
        }
    }

    if !p.noclip {
        if !found_collision do g.player.airborne = true

        if !airborne_at_start && !p.airborne {
            p.speed *= 0.8
        }

        if lg.length(p.speed.xz) > 20 do p.speed.xz *= 0.9
    }

    if g.rmb_click do remove_entity_by_index(scene, closest_entity_index)

    g.renderer.p_light.position = g.player.position + {0, 2, 0}
    return
}

update_camera :: proc() {
    camera := &g.camera
    x, y := rd.get_relative_mouse_movement()
    x *= g.mouse_sense
    y *= g.mouse_sense
    g.player.rotation.y += x
    g.player.rotation.x = lg.min(g.player.rotation.x + y, 90)
    if g.player.rotation.x < -90 do g.player.rotation.x = -90
    camera.pitch = g.player.rotation.x
    camera.yaw = g.player.rotation.y
    camera.position = g.player.position
    camera.position.y += 2
}
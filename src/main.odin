package obj_viewer

import "core:log"
import "core:time"
import rand "core:math/rand"
import rd "../Redef/src"

main :: proc() {
    context.logger = log.create_console_logger()
    scene := load_scene("out/savefile")
    init(&scene)
    log.debugf("Program initialized successfully")
    run(&scene)
}

init :: proc(scene: ^Scene) {
    ok := rd.create_window("Demo window", 1280, 720, ODIN_DEBUG); assert(ok)
    rd.set_relative_mouse_mode()
    RND_Init()
    scene.renderables = make([]Renderable, len(scene.assets)) 
    for &asset, i in scene.assets {
        scene.renderables[i] = create_render_object(&asset)
        for &entity in scene.entities {
            if entity.asset == &asset {
                entity.renderable = &scene.renderables[i]
            }
        }
    }
    create_player(g.player.position, g.player.rotation)

    for asset in scene.assets {
        delete(asset.data.file)
    }
    g.camera.fov = 90
    rd.set_vsync(g.vsync)
}



run :: proc(scene: ^Scene) {
    now := time.now()
    main_loop: for {
        defer {
            free_all(context.temp_allocator)
            g.frame += 1
            g.lmb_click = false
            g.rmb_click = false
            if g.frame % 20 == 0 {
                now = time.now()
            }
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
                        case .C:
                            if .CONTROL in mod do break main_loop
                        case .Q:
                            if !g.player.airborne || g.player.noclip do g.player.checkpoint = get_player_translation()
                        case .E:
                            reset_player_pos()
                            g.player.noclip = false
                        case .N: g.player.noclip = !g.player.noclip
                            log.debug(g.player.noclip)
                        case .S: 
                            if .CONTROL in mod && !g.running do write_save_file(scene^)
                        case .NUM1: spawn(scene, 0, false)
                        case .NUM2: spawn(scene, 1, false)
                        case .NUM3: spawn(scene, 2, false)
                        case .NUM4: spawn(scene, 3, false)
                    }
                case rd.MouseEvent: 
                #partial switch ev.type {
                    case .LPress: g.lmb_click = true
                    case .RPress: g.rmb_click = true
                }
            }
        }

        update(scene)
        rd.clear()
        draw_entities(scene)
        draw_sprite(g.renderer.crosshair)
        rd.frame_end()
    }
}

update :: proc(scene: ^Scene) -> (exit: bool) {
    if g.running {
        update_camera()
        update_player(scene^)
    }

    if g.lmb_click {
        spawn(scene, 0, true)
    }

    if g.rmb_click {
        win_size := rd.get_window_size()
        origin, dir := ray_from_screen(g.camera, win_size / 2, win_size)
        closest_hit: f32 = max(f32)
        closest_entity: EntityID = -1
        for entity in scene.entities {
            intersection := ray_intersect_aabb(origin, dir, get_entity_aabb(entity))
            if intersection != -1 && intersection < closest_hit {
                closest_hit = intersection
                closest_entity = entity.id
            }
        }
        remove_entity(scene, closest_entity)
    }

    g.renderer.p_light.position = g.player.position + {0, 2, 0}
    return
}

reset_player_pos :: proc(at_origin := false) {
    if at_origin do g.player.position = 0; 
    else if g.player.checkpoint.x == 0 {
        g.player.position = g.player.checkpoint.x
    } else {
        g.player.position = g.player.checkpoint.x
        g.player.rotation = g.player.checkpoint.y
    }
    g.player.speed = 0
    g.player.bbox = AABB {
        min = g.player.position + {-0.3, 0, -0.3},
        max = g.player.position + {0.3, 2, 0.3}
    }
}
package obj_viewer

import "base:runtime"
import "core:log"
import "core:math/linalg"
import "core:time"
import rd "../../Redef/src"

default_context: runtime.Context

main :: proc() {
    context.logger = log.create_console_logger()
    init()
    log.debugf("Program initialized successfully")
    scene := load_scene("savefile")
    run(&scene)
}

init :: proc() {
    default_context = context

    ok := rd.create_window("Demo window", 1280, 720, true); assert(ok)
    // Set relative mouse mode

    RND_Init()

    create_player()
    g.camera.fov = 90
}

run :: proc(scene: ^Scene) {
    main_loop: for {
        defer {
            free_all(context.temp_allocator)
            g.frame += 1
        }

        g.dt = f32(rd.get_dt() / 1000)
        key_presses: KeyboardEvents
        for event in rd.pump_event_iter(){
            #partial switch ev in event {
                case rd.Quit: 
                    break main_loop
                case rd.KeyboardEvent: 
                    #partial switch ev.key {
                        case .F11: toggle_fullscreen()
                    }
                    append(&key_presses, ev)
                case rd.MouseEvent: #partial switch ev.type {
                    case .LPress: g.lmb_click  = true
                }
            }
        }

        // if update(scene, key_presses) do break main_loop
        rd.clear({0.2, 0.2, 0.2, 1})
        draw_sprite(g.renderer.crosshair)
        rd.frame_end()
    }
}

update :: proc(scene: ^Scene, keys: KeyboardEvents) -> (exit: bool) {
    for elem in 0..<len(keys) {
        key := keys[elem].key
        mod := keys[elem].mod
        #partial switch key {
            case .C:
                if .CONTROL in mod do return true
            case .Q:
                if !g.player.airborne do g.player.checkpoint = get_player_translation()
            case .E:
                reset_player_pos()
                g.player.noclip = false
            case .N: g.player.noclip = !g.player.noclip
        }
    }
    if g.lmb_click {
        spawn(scene, true)
    }
    update_player(scene^)
    update_player_camera(&g.camera)

    g.renderer.p_light.position = g.player.position + {0, 1, 0}
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
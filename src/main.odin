package obj_viewer

import "base:runtime"
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
    create_player()
    for i in 0..<2000 {
        mappi, mappi_ok := entity_from_asset(scene, "mappi"); assert(mappi_ok)
        
        rnd := rand.float32_normal(1, 1)
        set_entity_transform(scene, mappi, {
            rand.float32_normal(0, 100),
            rand.float32_normal(0, 100),
            rand.float32_normal(0, 100),
        }, {rnd, rnd, rnd})

    }
    g.camera.fov = 90
}

create_render_object :: proc(asset: ^Asset) -> Renderable {
    assert(asset != nil)
    ro: Renderable
    ro.vbo = rd.create_vertex_buffer(asset.data.vertices)
    ro.ibo = rd.create_index_buffer(asset.data.indices)
    ro.primitives = &asset.data.primitives
    ro.materials = rd.create_structured_buffer(asset.data.materials, {.Pixel})

    pixels: [dynamic][]byte
    width, height: u32
    for tex_info, i in asset.data.textures {
        img := asset.data.images[i]
        width = tex_info.width
        height = tex_info.height
        append(&pixels, img)
    }
    ro.textures = rd.create_texture_buffer(pixels[:], width, height)
    
    return ro
}

run :: proc(scene: ^Scene) {
    now := time.now()
    main_loop: for {
        defer {
            free_all(context.temp_allocator)
            g.frame += 1
            g.lmb_click = false
            if g.frame % 10 == 0 {
                log.debug(time.duration_milliseconds(time.since(now))/10)
                now = time.now()
            }
        }

        g.dt = f32(rd.get_dt() / 1000)
        key_presses: KeyboardEvents
        for event in rd.pump_event_iter(){
            #partial switch ev in event {
                case rd.Quit: 
                    break main_loop
                case rd.KeyboardEvent: 
                    #partial switch ev.key {
                        case .ESCAPE:
                            if ev.type == .KeyDown {
                                g.running = !g.running
                                rd.set_relative_mouse_mode(g.running)
                            } 
                        case .F11: toggle_fullscreen()
                    }
                    append(&key_presses, ev)
                case rd.MouseEvent: #partial switch ev.type {
                    case .LPress: g.lmb_click  = true
                }
            }
        }

        if update(scene, key_presses) do break main_loop
        rd.clear({0.2, 0.2, 0.2, 1})
        draw_entities(scene)
        draw_sprite(g.renderer.crosshair)
        rd.frame_end()
    }
}

update :: proc(scene: ^Scene, keys: KeyboardEvents) -> (exit: bool) {
    for elem in 0..<len(keys) {
        if keys[elem].type != .KeyDown do continue
        key  := keys[elem].key
        mod  := keys[elem].mod
        #partial switch key {
            case .C:
                if .CONTROL in mod do return true
            case .Q:
                if !g.player.airborne do g.player.checkpoint = get_player_translation()
            case .E:
                reset_player_pos()
                g.player.noclip = false
            case .N: g.player.noclip = !g.player.noclip
                log.debug(g.player.noclip)
            // case .S: 
            //     if .CONTROL in mod do write_save_file(scene^)
            case .NUM1: spawn(scene, 0, false)
            case .NUM2: spawn(scene, 1, false)
            case .NUM3: spawn(scene, 2, false)
            case .NUM4: spawn(scene, 3, false)
        }
    }
    if g.running {
        update_camera()
        update_player(scene^)
    }

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
package obj_viewer

import "core:debug/pe"
import "core:strings"
import "core:fmt"
import "core:log"
import sdl "vendor:sdl3"
import im "shared:imgui"
import im_sdl "shared:imgui/imgui_impl_sdl3"
import im_sdlgpu "shared:imgui/imgui_impl_sdlgpu3"

NONE :: EntityID(0)

Editor :: struct {
    camera:          Camera,
    selected_entity: EntityID,
    dragging:        bool,
    drag_position:   vec2,
    drag_start:      vec2,
    panels:          [PanelLocation]Panel,
    tab_flag:        bool
}

PanelLocation :: enum {
    LEFT,
    RIGHT
}

Panel :: struct {
    rect: Rect,
}

get_entity_ptr :: proc(scene: ^Scene, id: EntityID) -> ^Entity {
    for &e in scene.entities {
        if e.id == id do return &e
    }
    return nil
}

selected_entity :: proc(scene: ^Scene) -> ^Entity {
    for &e in scene.entities {
        if e.id == g.editor.selected_entity do return &e
    }
    return nil
}

selected_entity_id :: proc(scene: ^Scene) -> EntityID {
    if a := selected_entity(scene); a != nil do return a.id
    return 0
}

update_editor :: proc(scene: ^Scene, keys: [dynamic; 64]KeyEvent) -> (exit: bool) {
    // g.editor.camera = g.fps_camera
    for k in keys{
        #partial switch k.key {
            case .S:
                if .LCTRL in k.mod do write_save_file(scene^)
            case .C:
                if .LCTRL in k.mod do return true
            case .ESCAPE:
                if g.editor.dragging do stop_dragging() 
                else do toggle_mode()
            case .DELETE: remove_selected_entity(scene)
            case .RETURN: stop_dragging()
            case .DOWN: cycle_editor_selected(scene^)
            case .UP:   cycle_editor_selected(scene^, false)
            case .TAB:
                cycle_editor_selected(scene^, .LSHIFT not_in k.mod)
                g.editor.tab_flag = true
        }
    } 
    if g.mb_click == .LEFT {
        m_pos: vec2
        _ = sdl.GetMouseState(&m_pos.x, &m_pos.y)
        if !click(m_pos) {
            win_size := get_window_size()
            ray_origin, ray_dir := ray_from_screen(g.fps_camera, m_pos, win_size)
            closest_hit: f32 = max(f32)
            closest_entity: EntityID = -1
            for &entity in scene.entities {
                aabbs := entity_aabbs(entity)
                for aabb in aabbs {
                    intersection := ray_intersect_aabb(ray_origin, ray_dir, aabb)
                    if intersection != -1 && intersection < closest_hit {
                        closest_hit = intersection
                        closest_entity = entity.id
                    }

                }
            }
            g.editor.selected_entity = closest_entity
        }
    }
    if g.editor.dragging {
        m_pos: vec2
        _ = sdl.GetRelativeMouseState(&m_pos.x, &m_pos.y)
        g.editor.drag_position += {m_pos.x, 0}
        io := im.GetIO()
        im.IO_AddMousePosEvent(io, g.editor.drag_position.x-g.editor.drag_position.y, g.editor.drag_position.y)
    }
    return
}

cycle_editor_selected :: proc(scene: Scene, forward := true) {
    e := &g.editor
    if forward {
        e.selected_entity += 1
        if int(e.selected_entity) > len(scene.entities) do e.selected_entity = 1
    } else {
        e.selected_entity -= 1
        if e.selected_entity == 0 do e.selected_entity = EntityID(len(scene.entities))
    }
}

// Return true if a UI element was clicked
click :: proc(m_pos: vec2) -> (clicked_ui_element: bool) {
    for panel, i in g.editor.panels {
        if !in_bounds(m_pos, panel.rect) do continue
        clicked_ui_element = true
    }
    return
}

init_editor :: proc(winsize: [2]i32) {
    e := &g.editor
    e.panels[.LEFT] = {
        rect = {0, 0, 300, f32(winsize.y)},
    }
    e.panels[.RIGHT] = {
        rect = {f32(winsize.x)-300, 0, 300, f32(winsize.y)},
    }
    e.camera.fov = 90

}

start_dragging :: proc(loc := #caller_location) {
    if g.editor.dragging do return
    x, y: f32
    flags := sdl.GetMouseState(&x, &y)
    if flags == {} do return
    log.debug("Started dragging", location = loc)
    g.editor.dragging = true
    g.editor.drag_position = {x, y}
    g.editor.drag_start    = {x, y}
    ok := sdl.SetWindowRelativeMouseMode(g.window, true); assert(ok)
    _ = sdl.GetRelativeMouseState(nil, nil)
}

stop_dragging :: proc(loc := #caller_location) {
    if !g.editor.dragging do return
    log.debug("Stopped dragging", location = loc)
    g.editor.dragging = false
    g.editor.drag_position = 0
    ok := sdl.SetWindowRelativeMouseMode(g.window, false); assert(ok)
    sdl.WarpMouseInWindow(g.window, g.editor.drag_start.x, g.editor.drag_start.y)
}

draw_editor :: proc(frame: Frame) {
    bind_pipeline(frame, .QUAD)
    for panel in g.editor.panels {
        draw_rect(panel.rect, frame)
    }
}

draw_imgui :: proc(scene: ^Scene, frame: Frame) {
    im_sdlgpu.NewFrame()
    im_sdl.NewFrame()
    im.NewFrame()
    w, h: i32
    sdl.GetWindowSize(g.window, &w, &h)
    if g.mode == .EDIT {
        if im.Begin("properties", nil, {.NoTitleBar, .NoResize, .NoMove}) {
            defer im.End()
            im.SetWindowPos(0)
            im.SetWindowSize({g.editor.panels[.LEFT].rect.w, g.editor.panels[.RIGHT].rect.h})
            if im.BeginTabBar("PropertiesTabs") {
                defer im.EndTabBar()

                // --- General Tab ---
                if im.BeginTabItem("Point light") {
                    defer im.EndTabItem()
                    if im.DragFloat("FOV", &g.fov, 1, 50, 140) do start_dragging()
                    im.LabelText("", "Point Light")
                    if im.DragFloat("intensity", &g.renderer.p_light.power, 1, 0, 10000) do start_dragging()
                    im.ColorPicker3("color", &g.renderer.p_light.color, {.InputRGB})
                }
                if im.BeginTabItem("Spot light") {
                    defer im.EndTabItem()
                    if im.DragFloat("Pitch", &g.renderer.s_light.angle.x, 0.1) do start_dragging()
                    if im.DragFloat("Yaw",   &g.renderer.s_light.angle.y, 0.1) do start_dragging()
                    if im.DragFloat3("Position", &g.renderer.s_light.pos) do start_dragging()
                }
            }
        }
        if im.Begin("entities", nil, {.NoTitleBar, .NoResize, .NoMove}) {
            defer im.End()
            rect := g.editor.panels[.RIGHT].rect

            im.SetWindowPos({f32(w)-rect.w, 0})
            im.SetWindowSize({rect.w, rect.h})

            selected_index := -1
            if im.BeginListBox("Entities", {rect.w-rect.w/10, rect.h/8}) {
                for e, i in scene.entities {
                    im.PushIDInt(i32(e.id))
                    name_cstr := strings.unsafe_string_to_cstring(e.name)
                    selected := e.id == g.editor.selected_entity
                    if im.Selectable(name_cstr, selected) {
                        g.editor.selected_entity = e.id
                    }
                    if selected {
                        // im.ScrollToItem()
                        selected_index = i
                    }
                    im.PopID()
                }
                im.EndListBox()
            }
            if selected_index != -1 && im.BeginChild("Lapsonen") {
                s := &scene.entities[selected_index]
                if im.DragFloat3("Position", &s.transform.translation, 0.01) do start_dragging()
                if im.DragFloat3("Scale",    &s.transform.scale, 0.01) do start_dragging()
                if im.Button("Delete") {
                    ok := remove_selected_entity(scene)
                    assert(ok)
                }
                if im.Button("Duplicate") {
                    id, ok := entity_from_model(scene, s.model.name)
                    assert(ok)
                    offset := s.model.aabbs[0].min * 2 * s.transform.scale
                    new_position := s.transform.translation + {offset.x, 0, 0}
                    set_entity_transform(scene, id, new_position, s.transform.scale)
                    g.editor.selected_entity = id
                }
                im.EndChild()

                for &axis in s.transform.scale do axis = max(0.01, axis)
            }

        }
    } else if im.Begin("info", nil, {.NoTitleBar, .NoMouseInputs, .NoMove}) {
        im.SetWindowPos(vec2{f32(w-200), 0})
        im.SetWindowSize(vec2{200, 0})
        rendered := i32(g.debug_info.draw_call_count)
        im.SetNextItemWidth(50)
        im.DragInt("Draw calls", &rendered, flags = {.NoInput})
        im.SetNextItemWidth(50)
        im.LabelText("", "Player")
        im.DragFloat("Vel", &g.debug_info.player_speed, flags = {.NoInput})
        im.DragFloat3("pos", &g.player.position)
        im.LabelText("", "Camera")
        im.DragFloat3("pos", &g.fps_camera.position)
        im.DragFloat("pitch", &g.fps_camera.pitch)
        im.DragFloat("yaw", &g.fps_camera.yaw)
        im.End()
    }
    im.Render()
    im_draw_data := im.GetDrawData()
    im_sdlgpu.PrepareDrawData(im_draw_data, frame.cmd_buff)
    im_color_target := sdl.GPUColorTargetInfo {
        texture = frame.swapchain,
        load_op = .LOAD,
        store_op = .STORE
    }
    im_render_pass := sdl.BeginGPURenderPass(frame.cmd_buff, &im_color_target, 1, nil); assert(im_render_pass != nil)
    im_sdlgpu.RenderDrawData(im_draw_data, frame.cmd_buff, im_render_pass)
    sdl.EndGPURenderPass(im_render_pass)
}

init_imgui :: proc() {
    assert(g.window != nil)
    if g.ui_context != nil {
        im_sdlgpu.Shutdown()
        im_sdl.Shutdown()
        im.Shutdown()
        im.DestroyContext(g.ui_context)
    }
    im.CHECKVERSION()
    g.ui_context = im.CreateContext()
    im_sdl.InitForSDLGPU(g.window)
    im_sdlgpu.Init(&{
        Device = g.gpu,
        ColorTargetFormat = sdl.GetGPUSwapchainTextureFormat(g.gpu, g.window)
    })
    style := im.GetStyle()
    for &color in style.Colors {
        color.rgb = pow(color.rgb, 2.2)
    }
}
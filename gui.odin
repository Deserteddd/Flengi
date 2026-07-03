package obj_viewer

import "core:strings"
import rd "../Redef"
import lg "core:math/linalg"
import im "shared:imgui"
import im_d3d11 "shared:imgui/imgui_impl_dx11"
import im_win32 "shared:imgui/imgui_impl_win32"

init_imgui :: proc() {
    assert(rd.g.graphics_init)
    if g.ui_context != nil {
        im_win32.Shutdown()
        im_d3d11.Shutdown()
        im.Shutdown()
        im.DestroyContext(g.ui_context)
    }
    im.CHECKVERSION()
    g.ui_context = im.CreateContext()
	ok := im_win32.Init(auto_cast rd.g.window.handle); assert(ok)
	ok = im_d3d11.Init(rd.g.graphics.device, rd.g.graphics.ctx); assert(ok)
}

draw_imgui :: proc(scene: ^Scene) {
	io := im.GetIO()
	io.DisplaySize = rd.get_window_size()
	io.DeltaTime = lg.max(g.dt, 1.0 / 1000.0)

	im_win32.NewFrame()
    im_d3d11.NewFrame()
    im.NewFrame()
        if im.Begin("properties", nil, {.NoTitleBar, .NoResize, .NoMove}) {
            defer im.End()
            im.SetWindowPos({0, 0})
            im.SetWindowSize({300, io.DisplaySize.y})
            if im.BeginTabBar("PropertiesTabs") {
                defer im.EndTabBar()

                // --- General Tab ---
                if im.BeginTabItem("Point light") {
                    defer im.EndTabItem()
                    im.DragFloat("FOV", &g.player.fov, 1, 50, 140)
                    im.LabelText("", "Point Light")
                    im.DragFloat("intensity", &g.renderer.p_light.power, 1, 0, 10000)
                    im.ColorPicker3("color", &g.renderer.p_light.color, {.InputRGB})
                }
            }
        }
		if im.Begin("entities", nil, {.NoTitleBar, .NoResize, .NoMove}) {
            defer im.End()
			rect := Rect{f32(io.DisplaySize.x)-300, 0, 300, f32(io.DisplaySize.y)}

            im.SetWindowPos({io.DisplaySize.x-rect.w, 0})
            im.SetWindowSize({rect.w, rect.h})

            selected_index := -1
			im.LabelText("", "Entities")
            if im.BeginListBox(" ", {rect.w-rect.w/10, rect.h/8}) {
                for e, i in scene.entities {
                    im.PushIDInt(i32(e.id))
                    name_cstr := strings.unsafe_string_to_cstring(e.name)
                    selected := e.id == g.selected
                    if im.Selectable(name_cstr, selected) {
                        g.selected = e.id
                    }
                    if selected {
                        // im.ScrollToItem()
                        selected_index = i
                    }
                    im.PopID()
                }
                im.EndListBox()
            }
            // Selected entity options
            if selected_index != -1 && im.BeginChild("Lapsonen") {
				im.Separator()
                s := &scene.entities[selected_index]
				im.LabelText("", "Physics")
                im.DragFloat3("Position", &s.physics.position, 0.01)
                im.DragFloat3("Scale",    &s.physics.scale, 0.01)
				im.Separator()
                if im.Button("Delete") {
                    ok := remove_entity(scene, g.selected)
                    assert(ok)
                }
                if im.Button("Duplicate") {
                    index := entity_from_asset(scene, s.asset_name)
                    offset := s.physics.aabb.min * 2 * s.physics.scale
					scene.entities[index].physics = s.physics				
					scene.entities[index].physics.position += {offset.x, 0, 0}
					scene.entities[index].in_frustum = true
					

                    g.selected = scene.entities[index].id
                }
                im.LabelText("##", "Material overrides")
                {
                    enabled := .Color in s.material_overrides
                    if im.Checkbox("Color", &enabled) {
                        if enabled do s.material_overrides += {.Color}
                        else do s.material_overrides -= {.Color}
                    }
                    if enabled do im.ColorEdit4("##", &s.override_values.color) 
                }
                {
                    enabled := .Metallic in s.material_overrides
                    if im.Checkbox("Metal", &enabled) {
                        if enabled do s.material_overrides += {.Metallic}
                        else do s.material_overrides -= {.Metallic}
                    }
                    if enabled do im.SliderFloat("##", &s.override_values.metallic, 0, 1); 
                }
                {
                    enabled := .Roughness in s.material_overrides
                    if im.Checkbox("Rough", &enabled) {
                        if enabled do s.material_overrides += {.Roughness}
                        else do s.material_overrides -= {.Roughness}
                    }
                    if enabled do im.SliderFloat("###", &s.override_values.roughness, 0, 1); 
                }
                im.EndChild()

                for &axis in s.physics.scale do axis = max(0.01, axis)
            }

        }

    im.Render()
    im_draw_data := im.GetDrawData(); assert(im_draw_data != nil)

	im_d3d11.RenderDrawData(im_draw_data)
}

package obj_viewer


import rd "../Redef"
import lg "core:math/linalg"
import "core:time"

import im "shared:imgui"
import im_d3d11 "shared:imgui/imgui_impl_dx11"
import im_win32 "shared:imgui/imgui_impl_win32"
import "core:strings"

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
    // w, h: i32
    // sdl.GetWindowSize(g.window, &w, &h)
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
                im.EndChild()

                for &axis in s.physics.scale do axis = max(0.01, axis)
            }

        }

    im.Render()
    im_draw_data := im.GetDrawData(); assert(im_draw_data != nil)

	im_d3d11.RenderDrawData(im_draw_data)
}



PointLight :: struct {
	position: vec3,
	power:    f32,
	color:    vec3,
}

FragUBOGlobal :: struct {
	light_pos:       vec3,
	_:               f32,
	light_color:     vec3,
	light_intensity: f32,
	view_pos:        vec3,
	_:				 f32
}

SkyboxUBO :: struct {
	inv_view, inv_proj: matrix[4, 4]f32,
}

VertexAABB :: struct {
	position: vec3,
}

Frame :: struct {
	frustum_planes: [6]vec4,
}

Camera :: struct {
	position: vec3,
	pitch:    f32,
	yaw:      f32,
}



Renderer :: struct {
	vs_ui:            rd.VertexShader,
	ps_ui:            rd.PixelShader,
	vs_text:          rd.VertexShader,
	ps_text:          rd.PixelShader,
	vs_gfx:           rd.VertexShader,
	ps_gfx:           rd.PixelShader,
	vs_skybox:        rd.VertexShader,
	ps_skybox:        rd.PixelShader,
	vs_aabb:          rd.VertexShader,
	ps_aabb:          rd.PixelShader,
	vs_ocean:         rd.VertexShader,
	ps_ocean:         rd.PixelShader,
	fallback_texture: rd.Texture,
	skybox_texture:   rd.TextureCube,
	p_light:          PointLight,
	crosshair:        rd.Texture,
	quad:             Quad,
	plane:			  Plane,
	font_atlases:	  [FontSize]rd.Texture,

	ps_fog:  		  rd.PixelShader,
}

shader_2D :: #load("shaders/2D.hlsl")
shader_text :: #load("shaders/text.hlsl")
shader_gfx :: #load("shaders/gfx.hlsl")
shader_skybox :: #load("shaders/skybox.hlsl")
shader_aabb :: #load("shaders/aabb.hlsl")
shader_ocean :: #load("shaders/ocean.hlsl")

RND_Init :: proc() {
	r := &g.renderer
	ok: bool

	r.quad = init_quad()
	r.crosshair =  load_sprite("assets/images/crosshair.png")

	r.font_atlases = {
		._8  = load_sprite("assets/images/DejaVu Sans Mono-8.png"),
		._10 = load_sprite("assets/images/DejaVu Sans Mono-10.png"),
		._12 = load_sprite("assets/images/DejaVu Sans Mono-12.png"),
		._14 = load_sprite("assets/images/DejaVu Sans Mono-14.png"),
		._16 = load_sprite("assets/images/DejaVu Sans Mono-16.png"),
	}

	r.vs_ui, ok = rd.load_vertex_shader(shader_2D, "vs_main", Vertex2D); assert(ok)
	r.ps_ui, ok = rd.load_pixel_shader(shader_2D, "ps_main"); assert(ok)

	r.vs_text, ok = rd.load_vertex_shader(shader_text, "vs_main", Vertex2D); assert(ok)
	r.ps_text, ok = rd.load_pixel_shader(shader_text, "ps_main"); assert(ok)

	r.vs_gfx, ok = rd.load_vertex_shader(shader_gfx, "vs_main", Vertex); assert(ok)
	r.ps_gfx, ok = rd.load_pixel_shader(shader_gfx, "ps_main"); assert(ok)

	r.vs_skybox, ok = rd.load_vertex_shader(shader_skybox, "vs_main", None); assert(ok)
	r.ps_skybox, ok = rd.load_pixel_shader(shader_skybox, "ps_main"); assert(ok)

	r.vs_aabb, ok = rd.load_vertex_shader(shader_aabb, "vs_main", VertexAABB); assert(ok)
	r.ps_aabb, ok = rd.load_pixel_shader(shader_aabb, "ps_main"); assert(ok)

	r.vs_ocean, ok = rd.load_vertex_shader(shader_ocean, "vs_main", VertexAABB); assert(ok)
	r.ps_ocean, ok = rd.load_pixel_shader(shader_ocean, "ps_main"); assert(ok)

	r.ps_fog, ok = rd.load_pixel_shader(shader_2D, "ps_fog"); assert(ok)

	r.skybox_texture = load_cubemap_texture(
		{
			.PX = "assets/images/skybox_sea/px.png",
			.NX = "assets/images/skybox_sea/nx.png",
			.PY = "assets/images/skybox_sea/py.png",
			.NY = "assets/images/skybox_sea/ny.png",
			.PZ = "assets/images/skybox_sea/pz.png",
			.NZ = "assets/images/skybox_sea/nz.png",
		},
	)

	r.plane = new_plane(200)

	r.p_light.color = 1

}

create_render_object :: proc(asset: ^Asset) -> Renderable {
	assert(asset != nil)
	ro: Renderable
	ro.vbo = rd.create_vertex_buffer(asset.data.vertices)
	ro.ibo = rd.create_index_buffer(asset.data.indices)
	ro.materials = rd.create_structured_buffer(asset.data.materials, {.Pixel})

	primitives: [dynamic]Primitive
	for p in asset.data.primitives {
		append(&primitives, p)
	}
	ro.primitives = primitives[:]

	if len(asset.data.textures) > 0 {
		width := asset.data.textures[0].width
		height := asset.data.textures[0].height
		ro.textures = rd.create_texture_buffer(asset.data.images, width, height)
	}

	aabb_verts := aabb_vertices(asset.data.header.aabb)
	ro.aabb = rd.create_vertex_buffer(aabb_verts[:])

	return ro
}

create_frag_ubo :: #force_inline proc() -> FragUBOGlobal {
	return FragUBOGlobal {
		view_pos = camera_position(),
		light_pos = g.renderer.p_light.position,
		light_color = g.renderer.p_light.color,
		light_intensity = g.renderer.p_light.power,
	}
}

draw_scene :: proc(scene: ^Scene) {
	proj_matrix := create_proj_matrix()
	view_matrix := create_view_matrix()

	rd.bind(&g.renderer.skybox_texture, 0)


	vp := proj_matrix * view_matrix
	rd.push_constant_data(.Vertex, &vp, 0)


	frag_ubo := create_frag_ubo()
	rd.push_constant_data(.Pixel, &frag_ubo, 0)

	rd.set_blend_mode(.Opaque)
	for &ro in scene.renderables {
		rd.bind(&g.renderer.vs_gfx)
		rd.bind(&g.renderer.ps_gfx)
		rd.bind(&ro.textures, 1)
		rd.bind(&ro.materials, 2)
		rd.bind(&ro.vbo)
		rd.bind(&ro.ibo)

		for entity in scene.entities {
			if entity.renderable != &ro || !entity.in_frustum do continue

			model_matrix := lg.matrix4_from_trs(
				entity.physics.position,
				entity.physics.rotation,
				entity.physics.scale,
			)
			rd.push_constant_data(.Vertex, &model_matrix, 1)
			for &primitive in ro.primitives {
				rd.push_constant_data(.Pixel, &primitive.material_id, 1)
				rd.draw_indexed(primitive.index_start, primitive.index_count)
			}

			if !g.running && g.selected == entity.id {
				rd.bind(&g.renderer.vs_aabb); defer rd.bind(&g.renderer.vs_gfx)
				rd.bind(&g.renderer.ps_aabb); defer rd.bind(&g.renderer.ps_gfx)
				rd.bind(&ro.aabb); defer rd.bind(&ro.vbo)
				rd.set_primitive_topology(.lineList); defer rd.set_primitive_topology(.triangleList)
				rd.draw(24)

			}
		}

		if !DEBUG_DRAW do continue
		rd.set_primitive_topology(.lineList)
		defer rd.set_primitive_topology(.triangleList)

		rd.bind(&ro.aabb)
		rd.bind(&g.renderer.vs_aabb)
		rd.bind(&g.renderer.ps_aabb)
		for entity in scene.entities {
			if entity.renderable != &ro || !entity.in_frustum do continue
			model_matrix := lg.matrix4_from_trs(
				entity.physics.position,
				lg.QUATERNIONF32_IDENTITY,
				entity.physics.scale,
			)
			rd.push_constant_data(.Vertex, &model_matrix, 1)
			rd.draw(24)
		}
	}

    // Ocean

	rd.bind(&g.renderer.ps_ocean)
	rd.bind(&g.renderer.vs_ocean)
	rd.bind(&g.renderer.plane.vbo)
	rd.bind(&g.renderer.plane.ibo)

	ocean_ubo := struct {
		vp: matrix[4,4]f32,
		player_position: vec2
	} {
		vp, camera_position().xz
	}
	rd.push_constant_data(.Vertex, &ocean_ubo, 0)

	time := time.duration_seconds(time.since(g.time))
	// time = 1
	rd.push_constant_data(.Vertex, &time, 1)
	
	rd.draw_indexed(0, g.renderer.plane.num_indices)
	rd.set_fill_mode(.Solid)


    // Skybox
	inv_view_mat := lg.inverse(view_matrix)
	inv_proj_mat := lg.inverse(proj_matrix)
	rd.push_constant_data(.Vertex, &SkyboxUBO{inv_view_mat, inv_proj_mat}, 0)
	rd.set_blend_mode(.Skybox)
	rd.bind(&g.renderer.vs_skybox)
	rd.bind(&g.renderer.ps_skybox)
	rd.draw(3)
}


import d3d "vendor:directx/d3d11"
post_process :: proc() {
	// Apply fog
	win_size := rd.get_window_size()
	ubo := UBO2D {
		rect     = {0, 0, win_size.x, win_size.y},
		win_size = win_size,
		use_tex  = true,
	}
	depth_texture := rd.get_depth_texture()

	view_matrix := create_view_matrix()
	proj_matrix := create_proj_matrix()
	
	inv_view_mat := lg.inverse(view_matrix)
	inv_proj_mat := lg.inverse(proj_matrix)

	inv_matricies: struct {v: mat4, p: mat4} = {inv_view_mat, inv_proj_mat}

	r := &g.renderer
	rd.g.graphics.ctx->OMSetRenderTargets(1, &rd.g.graphics.target, nil)
	rd.set_blend_mode(.Alpha)
	rd.bind(&r.vs_ui)
	rd.bind(&g.renderer.ps_fog)
	rd.bind(&r.quad.vbo)
	rd.bind(&r.quad.ibo)
	rd.bind(depth_texture, 0)
	rd.push_constant_data(.Vertex, &ubo, 0)
	rd.push_constant_data(.Pixel, &inv_matricies, 0)
	rd.draw_indexed(0, 6)
	rd.g.graphics.ctx->OMSetRenderTargets(1, &rd.g.graphics.target, rd.g.graphics.dsv)
}



get_furustum_planes :: proc(vp: matrix[4, 4]f32) -> [6]vec4 {
	t := lg.transpose(vp)
	return {t[3] + t[0], t[3] + t[0], t[3] + t[1], t[3] + t[1], t[3] + t[2], t[3] + t[2]}
}


create_view_matrix :: proc() -> lg.Matrix4f32 {
	pitch_matrix := lg.matrix4_rotate_f32(to_radians(g.player.rotation.x), {1, 0, 0})
	yaw_matrix := lg.matrix4_rotate_f32(to_radians(g.player.rotation.y), {0, 1, 0})
	position_matrix := lg.inverse(lg.matrix4_translate_f32(camera_position()))
	return pitch_matrix * yaw_matrix * position_matrix
}

create_proj_matrix :: proc(loc := #caller_location) -> mat4 {
	win_size := rd.get_window_size()
	aspect := win_size.x / win_size.y
	return lg.matrix4_perspective_f32(to_radians(g.player.fov), aspect, 0.01, 1000)
}

// ----------------------------
//        2D Renderer
// ----------------------------
Vertex2D :: struct {
	position: vec2,
	uv:       vec2,
}

Rect :: struct {
	x, y, w, h: f32,
}

Quad :: struct {
	vbo: rd.VertexBuffer,
	ibo: rd.IndexBuffer,
}

UBO2D :: struct {
	rect:     Rect,
	win_size: vec2,
	use_tex:  b32,
	color:    vec4,
}


TextUBO :: struct {
	win_size: vec2,
	pos:	  vec2,
	src:	  Rect,
	tex_size: vec2
}

FontSize :: enum {
	_8,
	_10,
	_12,
	_14,
	_16
}

init_quad :: proc() -> Quad {
	verts := [4]Vertex2D {
		Vertex2D{{-1, -1}, {0, 0}}, // Bottom-left
		Vertex2D{{1, -1}, {1, 0}}, // Bottom-right
		Vertex2D{{1, 1}, {1, 1}}, // Top-right
		Vertex2D{{-1, 1}, {0, 1}}, // Top-left
	}
	indices := [6]u16 {
		0,
		2,
		1, // First triangle
		2,
		0,
		3, // Second triangle
	}

	vbo := rd.create_vertex_buffer(verts[:])
	ibo := rd.create_index_buffer(indices[:])
	return Quad{vbo, ibo}
}

draw_sprite :: proc(sprite: rd.Texture, pos: vec2 = 0, scale: f32 = 1) {
	rd.set_blend_mode(.Alpha)
	sprite := sprite
	win_size := rd.get_window_size()

	x := pos == 0 ? win_size.x / 2 - f32(sprite.width) / 2 : pos.x
	y := pos == 0 ? win_size.y / 2 - f32(sprite.height) / 2 : pos.y

	ubo := UBO2D {
		rect     = {x, y, f32(sprite.width) * scale, f32(sprite.height) * scale},
		win_size = win_size,
		use_tex  = true,
	}

	r := &g.renderer
	rd.bind(&r.vs_ui)
	rd.bind(&r.ps_ui)
	rd.bind(&r.quad.vbo)
	rd.bind(&r.quad.ibo)
	rd.bind(&sprite)
	rd.push_constant_data(.Vertex, &ubo, 0)
	rd.draw_indexed(0, 6)
}


draw_text :: proc(text: string, pos: vec2, size: FontSize) {
	rd.set_blend_mode(.Alpha)
	sprite := g.renderer.font_atlases[size]
	win_size := rd.get_window_size()

	r := &g.renderer
	rd.bind(&r.vs_text)
	rd.bind(&r.ps_text)
	rd.bind(&r.quad.vbo)
	rd.bind(&r.quad.ibo)
	rd.bind(&sprite)

	get_atlas_position :: proc(c: rune) -> vec2 {
		col := int(c)/16
		row := int(c)%16
		return {f32(row), f32(col)}
	}

	col: f32 = 0
	row: f32 = 0
	for char, i in text {
		if char == '\n' {
			row += 1
			col = 0
			continue
		}
		defer col += 1
		atlas_slot := get_atlas_position(char)
		ubo := TextUBO {
			win_size = win_size,
			src      = {
				atlas_slot.x*32+1, atlas_slot.y*32+1, 
				f32(sprite.width)/16-1, f32(sprite.height)/16-1
			},
			tex_size = {f32(sprite.width), f32(sprite.height)},
			pos		 = pos + {col * (8 + f32(size)-1), row * 32}
		}

		rd.push_constant_data(.Vertex, &ubo, 0)
		rd.push_constant_data(.Pixel, &ubo, 0)
		rd.draw_indexed(0, 6)
	}

}

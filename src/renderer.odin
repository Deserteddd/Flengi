package obj_viewer


import "core:log"
import lg "core:math/linalg"
import rd "../Redef/src"

PointLight :: struct {
    position: vec3,
    power:    f32,
    color:    vec3,
}

FragUBOGlobal :: struct {
    light_pos: vec3,
    _: f32,
    light_color: vec3,
    light_intensity: f32,
    view_pos: vec3,
    _: f32,
}

SkyboxUBO :: struct {
    inv_view,
    inv_proj: matrix[4,4]f32
}

Frame :: struct {
    frustum_planes:     [6]vec4,
}

Camera :: struct {
    position:   vec3,
    pitch:      f32,  
    yaw:        f32,
    fov:        f32
}

Renderable :: struct {
    vbo:            rd.VertexBuffer,
    ibo:            rd.IndexBuffer,
    materials:      rd.StructuredBuffer,
    textures:       rd.TextureBuffer,
    primitives:     []Primitive,
}

Renderer :: struct {
    vs_ui:              rd.VertexShader,
    ps_ui:              rd.PixelShader,

    vs_gfx:             rd.VertexShader,
    ps_gfx:             rd.PixelShader,

    vs_skybox:          rd.VertexShader,
    ps_skybox:          rd.PixelShader,

    fallback_texture:   rd.Texture,
    skybox_texture:     rd.TextureCube,
    p_light:            PointLight,
    crosshair:          Sprite,
    quad:               Quad,
}

shader_ui       :: #load("../shaders/ui.hlsl")
shader_gfx      :: #load("../shaders/gfx.hlsl")
shader_skybox   :: #load("../shaders/skybox.hlsl")

RND_Init :: proc() {
    r := &g.renderer
    ok: bool

    r.quad = init_quad()
    r.crosshair = load_sprite("assets/images/crosshair.png")

    r.vs_ui, ok = rd.load_vertex_shader(shader_ui, "vs_main", Vertex2D); assert(ok)
    r.ps_ui, ok = rd.load_pixel_shader(shader_ui, "ps_main"); assert(ok)

    r.vs_gfx, ok = rd.load_vertex_shader(shader_gfx, "vs_main", Vertex); assert(ok)
    r.ps_gfx, ok = rd.load_pixel_shader(shader_gfx, "ps_main"); assert(ok)
    
    r.vs_skybox, ok = rd.load_vertex_shader(shader_skybox, "vs_main", None); assert(ok)
    r.ps_skybox, ok = rd.load_pixel_shader(shader_skybox, "ps_main"); assert(ok)

    r.skybox_texture = load_cubemap_texture({
        .PX = "assets/images/skybox/px.png",
        .NX = "assets/images/skybox/nx.png",
        .PY = "assets/images/skybox/py.png",
        .NY = "assets/images/skybox/ny.png",
        .PZ = "assets/images/skybox/pz.png",
        .NZ = "assets/images/skybox/nz.png",
    })

    r.p_light = {
        position = 0,
        power = 100,
        color = 1
    }

}

create_frag_ubo :: #force_inline proc() -> FragUBOGlobal {
    return FragUBOGlobal {
        view_pos = g.camera.position,
        light_pos = g.renderer.p_light.position,
        light_color = g.renderer.p_light.color,
        light_intensity = g.renderer.p_light.power,
    }
}

draw_entities :: proc(scene: ^Scene) {
    proj_matrix := create_proj_matrix(g.camera)
    view_matrix := create_view_matrix(g.camera)
    vp := proj_matrix * view_matrix
    rd.set_blend_mode(.Opaque)
    rd.bind(&g.renderer.vs_gfx)
    rd.bind(&g.renderer.ps_gfx)
    rd.push_constant_data(.Vertex, &vp, 0)

    frag_ubo := create_frag_ubo()
    rd.push_constant_data(.Pixel, &frag_ubo, 0)
    for &ro in scene.renderables {
        rd.bind(&ro.textures, 0)
        rd.bind(&ro.materials, 1)
        rd.bind(&ro.vbo)
        rd.bind(&ro.ibo)
        
        // single_material: bool
        // if len(ro.primitives) == 1 {
        //     single_material = true
        //     material_id: u32 = 0
        //     rd.push_constant_data(.Pixel, &material_id, 1)
        // }

        for entity in scene.entities {
            if entity.renderable != &ro do continue
            model_matrix := lg.matrix4_from_trs(
                entity.physics.position,
                entity.physics.rotation,
                entity.physics.scale
            )
            rd.push_constant_data(.Vertex, &model_matrix, 1)
            for &primitive in ro.primitives {
                rd.push_constant_data(.Pixel, &primitive.material_id, 1)
                rd.draw_indexed(primitive.index_start, primitive.index_count)
            }
        }
    }

    inv_view_mat := lg.inverse(view_matrix)
    inv_proj_mat := lg.inverse(proj_matrix)

    rd.set_blend_mode(.Skybox)
    rd.bind(&g.renderer.vs_skybox)
    rd.bind(&g.renderer.ps_skybox)
    rd.bind(&g.renderer.skybox_texture)
    rd.push_constant_data(.Vertex, &SkyboxUBO{inv_view_mat, inv_proj_mat}, 0)
    rd.draw(3)
}


toggle_fullscreen :: proc() {
    panic("TODO")
}

get_furustum_planes :: proc() -> [6]vec4 {
    proj_matrix := create_proj_matrix(g.camera)
    view_matrix := create_view_matrix(g.camera)
    vp := proj_matrix * view_matrix
    t := lg.transpose(vp)
    return {
        t[3]+t[0],
        t[3]+t[0],
        t[3]+t[1],
        t[3]+t[1],
        t[3]+t[2],
        t[3]+t[2],
    }
}


create_view_matrix :: proc(camera: Camera) -> lg.Matrix4f32 {
    pitch_matrix := lg.matrix4_rotate_f32(to_radians(camera.pitch), {1, 0, 0})
    yaw_matrix := lg.matrix4_rotate_f32(to_radians(camera.yaw), {0, 1, 0})
    position_matrix := lg.inverse(lg.matrix4_translate_f32(camera.position))
    return pitch_matrix * yaw_matrix * position_matrix
}

create_proj_matrix :: proc(camera: Camera, loc := #caller_location) -> mat4 {
    win_size := rd.get_window_size()
    aspect := win_size.x / win_size.y
    return lg.matrix4_perspective_f32(
        to_radians(camera.fov), 
        aspect, 
        0.01, 
        1000
    )
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

Sprite :: struct {
    name:    string,
    texture: rd.Texture,
    size:    [2]i32
}

Quad :: struct {
    vbo:     rd.VertexBuffer,
    ibo:     rd.IndexBuffer,
}

UBO2D :: struct {
    rect:     Rect,
    win_size: vec2,
    use_tex:  b32,
    _pad:     b32,
    color:    vec4
}

init_quad :: proc() -> Quad {
    verts := [4]Vertex2D {
        Vertex2D{{-1, -1}, {0, 0}}, // Bottom-left
        Vertex2D{{ 1, -1}, {1, 0}}, // Bottom-right
        Vertex2D{{ 1,  1}, {1, 1}}, // Top-right
        Vertex2D{{-1,  1}, {0, 1}}, // Top-left
    }
    indices := [6]u16{
        0, 2, 1, // First triangle
        2, 0, 3, // Second triangle
    }

    vbo := rd.create_vertex_buffer(verts[:])
    ibo := rd.create_index_buffer(indices[:])
    return Quad {vbo, ibo}
}

draw_sprite :: proc(sprite: Sprite, pos: vec2 = 0, scale: f32 = 1) {
    rd.set_blend_mode(.Alpha)
    sprite := sprite
    win_size := rd.get_window_size()

    x := pos == 0 ? win_size.x/2 - f32(sprite.size.x)/2 : pos.x
    y := pos == 0 ? win_size.y/2 - f32(sprite.size.y)/2 : pos.y

    ubo := UBO2D {
        rect = {x, y, f32(sprite.size.x)*scale, f32(sprite.size.y)*scale},
        win_size = rd.get_window_size(),
        use_tex = true,
    }
    
    r := &g.renderer
    rd.bind(&r.vs_ui)
    rd.bind(&r.ps_ui)
    rd.bind(&r.quad.vbo)
    rd.bind(&r.quad.ibo)
    rd.bind(&r.crosshair.texture)
    rd.push_constant_data(.Vertex, &ubo, 0)
    rd.draw_indexed(0, 6)
}
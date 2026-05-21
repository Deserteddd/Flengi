package obj_viewer
import "core:math"
import "core:math/linalg"
import "core:math/rand"
import "core:time"
import rd "../Redef/src"

vec2 :: [2]f32
vec3 :: [3]f32
vec4 :: [4]f32
mat4 :: matrix[4,4]f32

None :: struct{}

to_radians :: math.to_radians_f32
round      :: math.round_f32
pow        :: linalg.pow
max        :: math.max
min        :: math.min

MouseButton :: enum {
    LEFT,
    RIGHT,
    MIDDLE,
}

g := struct {
    player:      Player,
    camera:      Camera,
    renderer:    Renderer,
    selected:    EntityID,
    frame:       uint,
    mouse_sense,
    dt,
    fov:         f32,
    lmb_click,
    rmb_click,
    vsync,
    fullscreen,
    running: bool

} {
    fov = 90,
    mouse_sense = 0.04,
    running = true,
    vsync   = true
}


Mode :: enum {
    PLAY,
    EDIT,
}

TRANSFORM_IDENTITY :: Transform {
    translation = 0,
    scale = 1,
    rotation = 0
}

DebugInfo :: struct {
    frame_time:         time.Duration,
    draw_call_count:    u32,
    player_speed:       f32,
    fps:                u32,
}


Scene :: struct {
    assets:           []Asset,
    renderables:      []Renderable,
    entities:     #soa[dynamic]Entity,
}

in_bounds :: proc(p: vec2, rect: Rect) -> bool {
    return p.x >= rect.x && p.x < rect.x + rect.w && p.y >= rect.y && p.y < rect.y + rect.h
}

to_vec4 :: proc(v: vec3, f: f32) -> vec4 { return vec4{v.x, v.y, v.z, f} }

norm :: proc(v: vec3) -> f32 { return math.sqrt_f32(v.x*v.x + v.y*v.y + v.z*v.z) }

random_range :: proc(min: f32, max: f32) -> f32 {
    return rand.float32() * (max - min) + min
}

aabb_vertices :: proc(bbox: AABB) -> [24]vec3 {
    min := bbox.min
    max := bbox.max

    return {
        vec3{min.x, min.y, min.z},
        vec3{max.x, min.y, min.z},

        vec3{max.x, max.y, min.z},
        vec3{min.x, max.y, min.z},

        vec3{min.x, min.y, min.z},
        vec3{min.x, min.y, max.z},

        vec3{max.x, min.y, max.z},
        vec3{min.x, min.y, max.z},

        vec3{max.x, max.y, max.z},
        vec3{min.x, max.y, max.z},

        vec3{max.x, min.y, max.z},
        vec3{max.x, min.y, min.z},

        vec3{max.x, max.y, min.z},
        vec3{max.x, max.y, max.z},

        vec3{min.x, max.y, min.z},
        vec3{min.x, max.y, max.z},
        
        // Vertical bars
        vec3{min.x, min.y, min.z},
        vec3{min.x, max.y, min.z},

        vec3{max.x, min.y, min.z},
        vec3{max.x, max.y, min.z},

        vec3{min.x, min.y, max.z},
        vec3{min.x, max.y, max.z},

        vec3{max.x, min.y, max.z},
        vec3{max.x, max.y, max.z},
    }
}
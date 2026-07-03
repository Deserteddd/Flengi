package obj_viewer


import "core:os"
import "core:log"
import "core:slice"

Asset :: struct {
    name,
    path: string,
    data: AssetData
}

AssetHeader :: struct {
    vertex_count:       u32,
    index_count:        u32,
    primitive_count:    u32,
    material_count:     u32,
    texture_count:      u32,

    aabb:               AABB,

    vertex_stride:      u32,
    index_stride:       u32,

    vertices_offset:    u32,
    indices_offset:     u32,
    primitives_offset:  u32,
    materials_offset:   u32,
    textures_offset:    u32,
}

AssetData :: struct {
    header:     AssetHeader,
    file:       []byte,
    vertices:   []Vertex,
    indices:    []u32,
    primitives: []Primitive,
    materials:  []Material,
    textures:   []TextureInfo,
    images:     [][]byte
}

Vertex :: struct {
    pos:        vec3,
    normal:     vec3,
    uv:         vec2,
    tangent:    vec4
}

Primitive :: struct {
    index_start: u32,
    index_count: u32,
    material_id: u32,
    vertex_base: u32,
}

Material :: struct {
    base_color_factor:      vec4,
    metallic_factor:        f32,
    roughness_factor:       f32,
    base_color_tex:         u32,
    metallic_roughness_tex: u32,
    normal_tex:             u32,
    occlusion_tex:          u32,
    emissive_tex:           u32,
    emissive_factor:        vec3,
    alpha_mode:             u32, // 0 Opaque, 1 mask, 2 blend
    alpha_cutoff:           f32,
    double_sided:           u32,
    _pad0:                  u32
}

TextureInfo :: struct {
    offset:    u32,
    size:      u32,
    width:     u32,
    height:    u32,
    format:    u32, // Ignore
    mip_count: u32
}


load_asset_data :: proc(path: string, allocator := context.allocator) -> (AssetData, bool) {
    data: AssetData
    path := resolve_project_path(path)
    bin_asset, read_err := os.read_entire_file(path, allocator)
    if read_err != nil {
        log.errorf("Failed to read asset binary \"%v\" (%v)", path, read_err)
        return {}, false
    }
    data.file = bin_asset
    header_ptr := cast(^AssetHeader)&bin_asset[0]
    data.header = header_ptr^
    vert_ptr := cast(^Vertex)&bin_asset[data.header.vertices_offset]
    data.vertices = slice.from_ptr(vert_ptr, int(data.header.vertex_count))

    index_ptr := cast(^u32)&bin_asset[data.header.indices_offset]
    data.indices = slice.from_ptr(index_ptr, int(data.header.index_count))

    primitive_ptr := cast(^Primitive)&bin_asset[data.header.primitives_offset]
    data.primitives = slice.from_ptr(primitive_ptr, int(data.header.primitive_count))

    material_ptr  := cast(^Material)&bin_asset[data.header.materials_offset]
    data.materials = slice.from_ptr(material_ptr, int(data.header.material_count))

    tex_info_ptr := cast(^TextureInfo)&bin_asset[data.header.textures_offset]
    data.textures = slice.from_ptr(tex_info_ptr, int(data.header.texture_count))

    images: [dynamic][]u8
    for tex_info in data.textures {
        img_ptr := &bin_asset[tex_info.offset]
        pixels := slice.from_ptr(img_ptr, int(tex_info.size))
        append(&images, pixels)
    }
    data.images = images[:]

    return data, true
}

create_mesh :: proc(asset: Asset) -> Mesh {
    tris := make([][3]vec3, len(asset.data.indices)/3)
    indices := asset.data.indices
    verts := asset.data.vertices
    for i: int; i<len(asset.data.indices); i += 3 {
        tris[i/3] = {verts[indices[i]].pos, verts[indices[i+1]].pos, verts[indices[i+2]].pos}
    }
    return Mesh{ tris }
}





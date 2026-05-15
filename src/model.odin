package obj_viewer

import rd "../../Redef/src"


Model :: struct {
    name: string,
    path: string,
    vbo: rd.VertexBuffer,
    ibo: rd.IndexBuffer,
    aabbs: []AABB,
}

load_model :: proc(path: string) -> Model {

    return {}
}
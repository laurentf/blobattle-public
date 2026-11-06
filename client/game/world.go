components {
  id: "game"
  component: "/game/game.script"
}
embedded_components {
  id: "chunk_factory"
  type: "factory"
  data: "prototype: \"/game/chunk.go\"\n"
  ""
}
embedded_components {
  id: "blob_factory"
  type: "factory"
  data: "prototype: \"/game/blob.go\"\n"
  ""
}
embedded_components {
  id: "cube_factory"
  type: "factory"
  data: "prototype: \"/game/cube.go\"\n"
  ""
}

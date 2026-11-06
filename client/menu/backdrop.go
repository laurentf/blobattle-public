components {
  id: "backdrop"
  component: "/menu/backdrop.script"
}
embedded_components {
  id: "piece_factory"
  type: "factory"
  data: "prototype: \"/menu/piece.go\"\n"
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
embedded_components {
  id: "liquid_factory"
  type: "factory"
  data: "prototype: \"/game/liquid.go\"\n"
  ""
}
